import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ITokenMessenger, Arbitrum_SpokePool, IERC20 } from "contracts/Arbitrum_SpokePool.sol";
import { Base_SpokePool } from "contracts/Base_SpokePool.sol";

contract DeployScript is Script {
    function run() public {
        uint256 privKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privKey);
        address arbitrumWETH = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
        uint32 depositQuoteTimeBuffer = 7 days;
        uint32 fillDeadlineBuffer = 7 days;
        IERC20 l2Usdc = IERC20(address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831));
        ITokenMessenger cctpTokenMessenger = ITokenMessenger(address(0));

        Arbitrum_SpokePool spokePool = new Arbitrum_SpokePool(
            arbitrumWETH,
            depositQuoteTimeBuffer,
            fillDeadlineBuffer,
            l2Usdc,
            cctpTokenMessenger
        );

        uint32 initDepositId = 1;
        address l2GatewayRouter;
        address crossDomainAdmin = address(0xD1dcdD8e6Fe04c338aC3f76f7D7105bEcab74F77);
        address withdrawalRecipient = address(0xD1dcdD8e6Fe04c338aC3f76f7D7105bEcab74F77);
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(spokePool),
            abi.encodeCall(
                Arbitrum_SpokePool.initialize,
                (initDepositId, l2GatewayRouter, crossDomainAdmin, withdrawalRecipient)
            )
        );
        console2.log("Deployed Arbitrum_SpokePool at address: ", address(proxy));
        console2.log("Deployed Arbitrum_SpokePool impl at address: ", address(spokePool));
    }
}
