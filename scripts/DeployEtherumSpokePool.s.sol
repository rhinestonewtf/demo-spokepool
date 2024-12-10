import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Ethereum_SpokePool } from "contracts/Ethereum_SpokePool.sol";

contract DeployScript is Script {
    function run() public virtual {
        deploy(address(0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9));
    }

    function deploy(address weth) public {
        uint256 privKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privKey);
        uint32 depositQuoteTimeBuffer = 7 days;
        uint32 fillDeadlineBuffer = 7 days;

        console2.log("depositQuoteTimeBuffer", depositQuoteTimeBuffer);

        Ethereum_SpokePool spokePool = new Ethereum_SpokePool(weth, depositQuoteTimeBuffer, fillDeadlineBuffer);

        uint32 initDepositId = 1;
        address withdrawalRecipient = address(0xD1dcdD8e6Fe04c338aC3f76f7D7105bEcab74F77);
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(spokePool),
            abi.encodeCall(Ethereum_SpokePool.initialize, (initDepositId, withdrawalRecipient))
        );
        console2.logBytes(abi.encodeCall(Ethereum_SpokePool.initialize, (initDepositId, withdrawalRecipient)));
        console2.logBytes(
            abi.encode(
                address(0x419CAfa9f4D1b7b844F42044bB577714b470eEEc),
                abi.encodeCall(Ethereum_SpokePool.initialize, (initDepositId, withdrawalRecipient))
            )
        );
        console2.log("Deployed Sepolia_SpokePool at address: ", address(proxy));
        console2.log("Deployed Sepolia_SpokePool impl at address: ", address(spokePool));
    }
}
