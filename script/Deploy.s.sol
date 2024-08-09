// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/protocol/PoolManager.sol";
import "../src/protocol/FBTCOracle.sol";
import "../test/mock/MockAggregator.sol";
import "../test/mock/MockERC20.sol";
import "../src/protocol/library/type/DataTypes.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployMyContract is Script {
    function run() external {
        address initialOwner = vm.envAddress("OWNER"); // Replace with actual address
        address fbtc0Address = vm.envAddress("FBTC0"); // Replace with actual address
        address fbtc1Address = vm.envAddress("FBTC1"); // Replace with actual address
        address avalonUSDTVault = vm.envAddress("AVALON_USDT_VAULT");
        address antaphaUSDTVault = vm.envAddress("ANTAPHA_USDT_VAULT");

        vm.startBroadcast();
        MockERC20 usdt = new MockERC20("Tether USD", "USDT", 6);
        console.log("USDT deployed at:", address(usdt));
        usdt.mint(initialOwner, 1000000000000 * 10 ** 6); // Mint 1,000,000 USDT to initialOwner
        console.log(
            "Mint success, initialOwner USDT balance",
            usdt.balanceOf(initialOwner)
        );
        vm.stopBroadcast();

        vm.startBroadcast();
        AggregatorMock mockAggregator = new AggregatorMock();
        mockAggregator.setLatestAnswer(60000 * 1e8); // Assuming 8 decimals for price feed
        console.log("AggregatorMock deployed at:", address(mockAggregator));
        vm.stopBroadcast();

        // Deploy FBTCOracle
        vm.startBroadcast();
        FBTCOracle fbtcOracle = new FBTCOracle(
            mockAggregator,
            initialOwner,
            3600
        );
        console.log("FBTCOracle deployed at:", address(fbtcOracle));
        console.log("BTC Price set", fbtcOracle.getAssetPrice());
        console.log("Oracle decimal", fbtcOracle.decimals());
        vm.stopBroadcast();

        DataTypes.PoolManagerConfig memory poolManagerConfig = DataTypes
            .PoolManagerConfig({
                DEFAULT_LIQUIDATION_THRESHOLD: 9000,
                DEFAULT_POOL_INTEREST_RATE: 800,
                DEFAULT_LTV: 7500,
                DEFAULT_PROTOCOL_INTEREST_RATE: 200,
                USDT: usdt,
                FBTC0: IERC20(fbtc0Address),
                FBTC1: IFBTC1(fbtc1Address),
                FBTCOracle: IFBTCOracle(address(fbtcOracle)),
                AvalonUSDTVault: avalonUSDTVault,
                AntaphaUSDTVault: antaphaUSDTVault
            });

        vm.startBroadcast();

        // Deploy logic contract
        PoolManager poolManager = new PoolManager();
        console.log(
            "PoolManager logic contract deployed at:",
            address(poolManager)
        );

        // Deploy TransparentUpgradeableProxy contract
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(poolManager),
            initialOwner,
            abi.encodeWithSignature("initialize(address)", initialOwner)
        );
        console.log("Proxy deployed at:", address(proxy));

        PoolManager(address(proxy)).setPoolManagerConfig(poolManagerConfig);
        console.log("Proxy setConfig success");

        PoolManager(address(proxy)).setEmergencyController(initialOwner);
        console.log("Proxy setEmergencyController success");
        vm.stopBroadcast();
    }
}
