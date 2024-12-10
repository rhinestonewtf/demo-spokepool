import "./DeployEtherumSpokePool.s.sol";

contract DeploySepoliaScript is DeployScript {
    function run() public {
        // sepolia weth
        address weth = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
        deploy(weth);
    }
}
