// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./mock/MockERC20.sol";
import "../src/protocol/PoolManagerConfigurator.sol";
import "../src/protocol/library/type/DataTypes.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PoolManagerStorageTest is Test {
    PoolManagerConfigurator poolManagerConfigurator;
    address admin = address(0x123);
    address user = address(0x456);
    MockERC20 mockUSDT = new MockERC20("USDT", "USDT", 18);
    IERC20 mockFBTC0 = IERC20(address(0x112));
    IFBTC1 mockFBTC1 = IFBTC1(address(0x113));
    IFBTCOracle mockFBTCOracle = IFBTCOracle(address(0x114));

    function setUp() public {
        vm.startPrank(admin);
        poolManagerConfigurator = new PoolManagerConfigurator();
        poolManagerConfigurator.initialize(admin);
        vm.stopPrank();
    }

    function testSetPoolManagerConfig() public {
        vm.startPrank(admin);
        DataTypes.PoolManagerConfig memory config = DataTypes
            .PoolManagerConfig({
                DEFAULT_LIQUIDATION_THRESHOLD: 5000,
                DEFAULT_POOL_INTEREST_RATE: 500,
                DEFAULT_LTV: 500,
                PROTOCOL_FEE_INTEREST_RATE: 100,
                USDT: mockUSDT,
                FBTC0: mockFBTC0,
                FBTC1: mockFBTC1,
                FBTCOracle: mockFBTCOracle,
                AvalonUSDTVault: address(0x789),
                AntaphaUSDTVault: address(0xABC)
            });
        poolManagerConfigurator.setPoolManagerConfig(config);
        vm.stopPrank();

        DataTypes.PoolManagerConfig
            memory storedConfig = poolManagerConfigurator
                .getPoolManagerConfig();

        assertEq(storedConfig.DEFAULT_POOL_INTEREST_RATE, 500);
        assertEq(storedConfig.DEFAULT_LTV, 500);
        assertEq(storedConfig.PROTOCOL_FEE_INTEREST_RATE, 100);
        assertEq(address(storedConfig.USDT), address(mockUSDT));
        assertEq(address(storedConfig.FBTC0), address(mockFBTC0));
        assertEq(address(storedConfig.FBTC1), address(mockFBTC1));
        assertEq(address(storedConfig.FBTCOracle), address(mockFBTCOracle));
        assertEq(storedConfig.AvalonUSDTVault, address(0x789));
        assertEq(storedConfig.AntaphaUSDTVault, address(0xABC));
    }

    function testOnlyAdminCanSetConfig() public {
        vm.startPrank(user);

        DataTypes.PoolManagerConfig memory config = DataTypes
            .PoolManagerConfig({
                DEFAULT_LIQUIDATION_THRESHOLD: 5000,
                DEFAULT_POOL_INTEREST_RATE: 500,
                DEFAULT_LTV: 500,
                PROTOCOL_FEE_INTEREST_RATE: 100,
                USDT: mockUSDT,
                FBTC0: mockFBTC0,
                FBTC1: mockFBTC1,
                FBTCOracle: mockFBTCOracle,
                AvalonUSDTVault: address(0x789),
                AntaphaUSDTVault: address(0xABC)
            });

        vm.expectRevert();
        poolManagerConfigurator.setPoolManagerConfig(config);
        vm.stopPrank();
    }

    function testSetUserPoolConfig() public {
        vm.startPrank(admin);

        DataTypes.UserPoolConfig memory userConfig = DataTypes.UserPoolConfig({
            init: true,
            interestRate: 500,
            loanToValue: 8000,
            liquidationThreshold: 5000
        });

        poolManagerConfigurator.setUserPoolConfig(user, userConfig);

        DataTypes.UserPoolConfig
            memory storedUserConfig = poolManagerConfigurator.getUserPoolConfig(
                user
            );
        assertTrue(storedUserConfig.init);
        assertEq(storedUserConfig.interestRate, 500);
        assertEq(storedUserConfig.loanToValue, 8000);
        assertEq(storedUserConfig.liquidationThreshold, 5000);

        vm.stopPrank();
    }
}
