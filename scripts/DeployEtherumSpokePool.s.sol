import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Ethereum_SpokePool } from "contracts/Ethereum_SpokePool.sol";

contract DeployScript is Script {
    function deploy(address weth) public {
        uint256 privKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privKey);
        uint32 depositQuoteTimeBuffer = 7 days;
        uint32 fillDeadlineBuffer = 7 days;

        Ethereum_SpokePool spokePool = new Ethereum_SpokePool(weth, depositQuoteTimeBuffer, fillDeadlineBuffer);

        uint32 initDepositId = 1;
        address withdrawalRecipient = address(0xD1dcdD8e6Fe04c338aC3f76f7D7105bEcab74F77);
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(spokePool),
            abi.encodeCall(Ethereum_SpokePool.initialize, (initDepositId, withdrawalRecipient))
        );
        console2.log("Deployed Sepolia_SpokePool at address: ", address(proxy));
        console2.log("Deployed Sepolia_SpokePool impl at address: ", address(spokePool));
    }
}
