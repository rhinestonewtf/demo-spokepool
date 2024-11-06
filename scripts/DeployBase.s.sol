import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ITokenMessenger, Arbitrum_SpokePool, IERC20 } from "contracts/Arbitrum_SpokePool.sol";
import { Base_SpokePool } from "contracts/Base_SpokePool.sol";

contract DeployScript is Script {
    function run() public {
        uint256 privKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privKey);
        address baseWETH = address(0x4200000000000000000000000000000000000006);
        uint32 depositQuoteTimeBuffer = 7 days;
        uint32 fillDeadlineBuffer = 7 days;
        IERC20 l2Usdc = IERC20(address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913));
        ITokenMessenger cctpTokenMessenger = ITokenMessenger(address(0));

        Base_SpokePool spokePool = new Base_SpokePool(
            baseWETH,
            depositQuoteTimeBuffer,
            fillDeadlineBuffer,
            l2Usdc,
            cctpTokenMessenger
        );

        uint32 initDepositId = 1;
        address crossDomainAdmin = address(0xD1dcdD8e6Fe04c338aC3f76f7D7105bEcab74F77);
        address withdrawalRecipient = address(0xD1dcdD8e6Fe04c338aC3f76f7D7105bEcab74F77);
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(spokePool),
            abi.encodeCall(Base_SpokePool.initialize, (initDepositId, crossDomainAdmin, withdrawalRecipient))
        );

        console2.log("Deployed Base_SpokePool at address: ", address(proxy));
        console2.log("Deployed Base_SpokePool impl at address: ", address(spokePool));
    }
}
