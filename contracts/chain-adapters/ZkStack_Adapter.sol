// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./interfaces/AdapterInterface.sol";
import "../external/interfaces/WETH9Interface.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// The BridgeHub is the main interaction point for bridging into ZkStack chains.
interface BridgeHubInterface {
    struct L2TransactionRequestDirect {
        uint256 chainId;
        uint256 mintValue;
        address l2Contract;
        uint256 l2Value;
        bytes l2Calldata;
        uint256 l2GasLimit;
        uint256 l2GasPerPubdataByteLimit;
        bytes[] factoryDeps;
        address refundRecipient;
    }

    /**
     * @notice the mailbox is called directly after the sharedBridge received the deposit.
     * This assumes that either ether is the base token or the msg.sender has approved mintValue allowance for the
     * sharedBridge. This means this is not ideal for contract calls, as the contract would have to handle token
     * allowance of the base Token.
     * @param _request the direct request.
     */
    function requestL2TransactionDirect(L2TransactionRequestDirect calldata _request)
        external
        payable
        returns (bytes32 canonicalTxHash);

    struct L2TransactionRequestTwoBridgesOuter {
        uint256 chainId;
        uint256 mintValue;
        uint256 l2Value;
        uint256 l2GasLimit;
        uint256 l2GasPerPubdataByteLimit;
        address refundRecipient;
        address secondBridgeAddress;
        uint256 secondBridgeValue;
        bytes secondBridgeCalldata;
    }

    /**
     * @notice After depositing funds to the sharedBridge, the secondBridge is called to return the actual L2 message
     * which is sent to the Mailbox. This assumes that either ether is the base token or the msg.sender has approved
     * the sharedBridge with the mintValue, and also the necessary approvals are given for the second bridge. The logic
     * of this bridge is to allow easy depositing for bridges. Each contract that handles the users ERC20 tokens needs
     * approvals from the user, this contract allows the user to approve for each token only its respective bridge.
     * This function is great for contract calls to L2, the secondBridge can be any contract.
     * @param _request the two bridges request.
     */
    function requestL2TransactionTwoBridges(L2TransactionRequestTwoBridgesOuter calldata _request)
        external
        payable
        returns (bytes32 canonicalTxHash);

    /**
     * @notice Gets the shared bridge.
     * @dev The shared bridge manages ERC20 tokens.
     */
    function sharedBridge() external view returns (address);

    /**
     * @notice Gets the base token for a chain.
     * @dev Base token == native token.
     */
    function baseToken(uint256 _chainId) external view returns (address);

    /**
     * @notice Computes the base transaction cost for a transaction.
     * @param _chainId the chain the transaction is being sent to.
     * @param _gasPrice the l1 gas price at time of execution.
     * @param _l2GasLimit the gas limit for the l2 transaction.
     * @param _l2GasPerPubdataByteLimit configuration value that changes infrequently.
     */
    function l2TransactionBaseCost(
        uint256 _chainId,
        uint256 _gasPrice,
        uint256 _l2GasLimit,
        uint256 _l2GasPerPubdataByteLimit
    ) external view returns (uint256);
}

/**
 * @notice Contract containing logic to send messages from L1 to ZkStack with ETH as the gas token.
 * @dev Public functions calling external contracts do not guard against reentrancy because they are expected to be
 * called via delegatecall, which will execute this contract's logic within the context of the originating contract.
 * For example, the HubPool will delegatecall these functions, therefore its only necessary that the HubPool's methods
 * that call this contract's logic guard against reentrancy.
 * @custom:security-contact bugs@across.to
 */

// solhint-disable-next-line contract-name-camelcase
contract ZkStack_Adapter is AdapterInterface {
    using SafeERC20 for IERC20;

    // We need to pay a base fee to the operator to include our L1 --> L2 transaction.
    // https://era.zksync.io/docs/dev/developer-guides/bridging/l1-l2.html#getting-the-base-cost

    // Limit on L2 gas to spend.
    uint256 public immutable L2_GAS_LIMIT; // typically 2_000_000

    // How much gas is required to publish a byte of data from L1 to L2. 800 is the required value
    // as set here https://github.com/matter-labs/era-contracts/blob/6391c0d7bf6184d7f6718060e3991ba6f0efe4a7/ethereum/contracts/zksync/facets/Mailbox.sol#L226
    // Note, this value can change and will require an updated adapter.
    uint256 public immutable L1_GAS_TO_L2_GAS_PER_PUB_DATA_LIMIT; // Typically 800

    // This address receives any remaining fee after an L1 to L2 transaction completes.
    // If refund recipient = address(0) then L2 msg.sender is used, unless msg.sender is a contract then its address
    // gets aliased.
    address public immutable L2_REFUND_ADDRESS;

    // L2 chain id
    uint256 public immutable CHAIN_ID;

    // BridgeHub address
    BridgeHubInterface public immutable BRIDGE_HUB;

    // Set l1Weth at construction time to make testing easier.
    WETH9Interface public immutable L1_WETH;

    // SharedBridge address, which is read from the BridgeHub at construction.
    address public immutable SHARED_BRIDGE;

    event ZkStackMessageRelayed(bytes32 canonicalTxHash);
    error ETHGasTokenRequired();

    /**
     * @notice Constructs new Adapter.
     * @param _l1Weth WETH address on L1.
     * @param _l2RefundAddress address that recieves excess gas refunds on L2.
     */
    constructor(
        uint256 _chainId,
        BridgeHubInterface _bridgeHub,
        WETH9Interface _l1Weth,
        address _l2RefundAddress,
        uint256 _l2GasLimit,
        uint256 _l1GasToL2GasPerPubDataLimit
    ) {
        CHAIN_ID = _chainId;
        BRIDGE_HUB = _bridgeHub;
        L1_WETH = _l1Weth;
        L2_REFUND_ADDRESS = _l2RefundAddress;
        L2_GAS_LIMIT = _l2GasLimit;
        L1_GAS_TO_L2_GAS_PER_PUB_DATA_LIMIT = _l1GasToL2GasPerPubDataLimit;
        SHARED_BRIDGE = BRIDGE_HUB.sharedBridge();
        address gasToken = BRIDGE_HUB.baseToken(CHAIN_ID);
        if (gasToken != address(1)) {
            revert ETHGasTokenRequired();
        }
    }

    /**
     * @notice Send cross-chain message to target on ZkStack.
     * @dev The HubPool must hold enough ETH to pay for the L2 txn.
     * @param target Contract on L2 that will receive message.
     * @param message Data to send to target.
     */
    function relayMessage(address target, bytes memory message) external payable override {
        uint256 txBaseCost = _computeETHTxCost(L2_GAS_LIMIT);

        // Returns the hash of the requested L2 transaction. This hash can be used to follow the transaction status.
        bytes32 canonicalTxHash = BRIDGE_HUB.requestL2TransactionDirect{ value: txBaseCost }(
            BridgeHubInterface.L2TransactionRequestDirect({
                chainId: CHAIN_ID,
                mintValue: txBaseCost,
                l2Contract: target,
                l2Value: 0,
                l2Calldata: message,
                l2GasLimit: L2_GAS_LIMIT,
                l2GasPerPubdataByteLimit: L1_GAS_TO_L2_GAS_PER_PUB_DATA_LIMIT,
                factoryDeps: new bytes[](0),
                refundRecipient: L2_REFUND_ADDRESS
            })
        );

        emit MessageRelayed(target, message);
        emit ZkStackMessageRelayed(canonicalTxHash);
    }

    /**
     * @notice Bridge tokens to ZkStack.
     * @dev The HubPool must hold enough ETH to pay for the L2 txn.
     * @param l1Token L1 token to deposit.
     * @param l2Token L2 token to receive.
     * @param amount Amount of L1 tokens to deposit and L2 tokens to receive.
     * @param to Bridge recipient.
     */
    function relayTokens(
        address l1Token,
        address l2Token, // l2Token is unused.
        uint256 amount,
        address to
    ) external payable override {
        // A bypass proxy seems to no longer be needed to avoid deposit limits. The tracking of these limits seems to be deprecated.
        // See: https://github.com/matter-labs/era-contracts/blob/bce4b2d0f34bd87f1aaadd291772935afb1c3bd6/l1-contracts/contracts/bridge/L1ERC20Bridge.sol#L54-L55
        uint256 txBaseCost = _computeETHTxCost(L2_GAS_LIMIT);

        bytes32 txHash;
        if (l1Token == address(L1_WETH)) {
            // If the l1Token is WETH then unwrap it to ETH then send the ETH to the standard bridge along with the base
            // cost.
            L1_WETH.withdraw(amount);
            txHash = BRIDGE_HUB.requestL2TransactionDirect{ value: amount + txBaseCost }(
                BridgeHubInterface.L2TransactionRequestDirect({
                    chainId: CHAIN_ID,
                    mintValue: txBaseCost,
                    l2Contract: to,
                    l2Value: 0,
                    l2Calldata: "",
                    l2GasLimit: L2_GAS_LIMIT,
                    l2GasPerPubdataByteLimit: L1_GAS_TO_L2_GAS_PER_PUB_DATA_LIMIT,
                    factoryDeps: new bytes[](0),
                    refundRecipient: L2_REFUND_ADDRESS
                })
            );
        } else {
            // An ERC20 that is not WETH.
            IERC20(l1Token).safeIncreaseAllowance(SHARED_BRIDGE, amount);
            txHash = BRIDGE_HUB.requestL2TransactionTwoBridges{ value: txBaseCost }(
                BridgeHubInterface.L2TransactionRequestTwoBridgesOuter({
                    chainId: CHAIN_ID,
                    mintValue: txBaseCost,
                    l2Value: 0,
                    l2GasLimit: L2_GAS_LIMIT,
                    l2GasPerPubdataByteLimit: L1_GAS_TO_L2_GAS_PER_PUB_DATA_LIMIT,
                    refundRecipient: L2_REFUND_ADDRESS,
                    secondBridgeAddress: BRIDGE_HUB.sharedBridge(),
                    secondBridgeValue: 0,
                    secondBridgeCalldata: _secondBridgeCalldata(to, l1Token, amount)
                })
            );
        }

        emit TokensRelayed(l1Token, l2Token, amount, to);
        emit ZkStackMessageRelayed(txHash);
    }

    /**
     * @notice Computes the calldata for the "second bridge", which handles sending non native tokens.
     * @param l2Recipient recipient of the tokens.
     * @param l1Token the l1 address of the token. Note: ETH is encoded as address(1).
     * @param amount number of tokens to send.
     * @return abi encoded bytes.
     */
    function _secondBridgeCalldata(
        address l2Recipient,
        address l1Token,
        uint256 amount
    ) internal pure returns (bytes memory) {
        return abi.encode(l1Token, amount, l2Recipient);
    }

    /**
     * @notice For a given l2 gas limit, this computes the amount of ETH needed and
     * returns the amount.
     * @param l2GasLimit L2 gas limit for the message.
     * @return amount of ETH that this contract needs to provide in order for the l2 transaction to succeed.
     */
    function _computeETHTxCost(uint256 l2GasLimit) internal view returns (uint256) {
        return BRIDGE_HUB.l2TransactionBaseCost(CHAIN_ID, tx.gasprice, l2GasLimit, L1_GAS_TO_L2_GAS_PER_PUB_DATA_LIMIT);
    }
}