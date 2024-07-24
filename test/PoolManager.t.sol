// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./mock/MockERC20.sol";
import "./mock/MockAggregator.sol";
import "./mock/MockFBTC1.sol";
import "./mock/MockPoolManager.sol";
import "../src/protocol/FBTCOracle.sol";
import "../src/protocol/library/type/DataTypes.sol";

contract PoolManagerTest is Test {
    MockERC20 mockUSDT = new MockERC20("USDT", "USDT", 6);
    MockERC20 mockFBTC0 = new MockERC20("FBTC0", "FBTC0", 8);
    MockFBTC1 mockFBTC1 = new MockFBTC1(address(mockFBTC0));

    uint8 USDTDecimal = 6;
    uint8 FBTCDecimal = 8;
    uint8 OracleDecimal = 8;
    uint256 ltv = 5000;
    uint256 lts = 8000;
    uint256 poolInterest = 500;
    uint256 protocolInterest = 100;
    uint256 denominator = 10000;

    FBTCOracle public fbtcOracle;
    AggregatorMock public aggregatorMock;
    MockPoolManager public poolManager;

    address public owner = address(0x001);
    address public oracleOwner = address(0x002);
    address public avalonUSDTVault = address(0x003);
    address public antaphaUSDTVault = address(0x004);
    address public emergencyContoller = address(0x005);
    address public user = address(0x010);

    error EnforcedPause();

    function setUp() public {
        vm.startPrank(owner);
        aggregatorMock = new AggregatorMock();
        fbtcOracle = new FBTCOracle(aggregatorMock, oracleOwner, 1000 days);
        DataTypes.PoolManagerConfig memory config = DataTypes
            .PoolManagerConfig({
                DEFAULT_LIQUIDATION_THRESHOLD: lts,
                DEFAULT_POOL_INTEREST_RATE: poolInterest,
                DEFAULT_LTV: ltv,
                DEFAULT_PROTOCOLL_INTEREST_RATE: protocolInterest,
                USDT: mockUSDT,
                FBTC0: mockFBTC0,
                FBTC1: mockFBTC1,
                FBTCOracle: fbtcOracle,
                AvalonUSDTVault: avalonUSDTVault,
                AntaphaUSDTVault: antaphaUSDTVault
            });
        poolManager = new MockPoolManager();
        poolManager.initialize(owner);
        poolManager.setPoolManagerConfig(config);
        poolManager.setEmergencyController(emergencyContoller);
        vm.stopPrank();
    }

    function testCreatePool_Failed() public {
        address nonAdmin = address(0x123);
        vm.startPrank(emergencyContoller);
        poolManager.pause();
        vm.expectRevert(EnforcedPause.selector);
        poolManager.createPool(user);
        poolManager.unpause();
        vm.stopPrank();

        vm.prank(nonAdmin);
        vm.expectRevert(
            abi.encodeWithSignature(
                "OwnableUnauthorizedAccount(address)",
                nonAdmin
            )
        );
        poolManager.createPool(user);

        vm.prank(address(owner));
        poolManager.createPool(user);

        vm.prank(address(owner));
        vm.expectRevert("Pool already initialized");
        poolManager.createPool(user);
    }

    function testCreatePool_Success() public {
        DataTypes.UserPoolConfig memory initialConfig = poolManager
            .getUserPoolConfig(owner);
        assertFalse(initialConfig.init);

        vm.prank(address(owner));
        poolManager.createPool(user);

        DataTypes.UserPoolConfig memory userPoolConfig = poolManager
            .getUserPoolConfig(user);

        DataTypes.PoolManagerConfig memory storedConfig = poolManager
            .getPoolManagerConfig();

        DataTypes.PoolManagerReserveInformation
            memory poolManagerReserve = poolManager
                .getPoolManagerReserveInformation();

        assertTrue(userPoolConfig.init);
        assertEq(
            userPoolConfig.poolInterestRate,
            storedConfig.DEFAULT_POOL_INTEREST_RATE
        );
        assertEq(
            userPoolConfig.liquidationThreshold,
            storedConfig.DEFAULT_LIQUIDATION_THRESHOLD
        );
        assertEq(
            userPoolConfig.protocolInterestRate,
            storedConfig.DEFAULT_PROTOCOLL_INTEREST_RATE
        );
        assertEq(userPoolConfig.loanToValue, storedConfig.DEFAULT_LTV);
        assertEq(poolManagerReserve.userAmount, 1);
        assertEq(poolManager.getUserList()[0], user);

        vm.prank(address(owner));
        poolManager.createPool(owner);
        poolManagerReserve = poolManager.getPoolManagerReserveInformation();
        assertEq(poolManagerReserve.userAmount, 2);
        assertEq(poolManager.getUserList()[1], owner);
    }

    function testSupply_Failed() public {
        uint256 amount = 1000 * 10 ** FBTCDecimal;
        mockFBTC0.mint(owner, amount);
        assertEq(mockFBTC0.balanceOf(owner), amount);

        mockFBTC0.approve(address(poolManager), amount);

        vm.startPrank(emergencyContoller);
        poolManager.pause();
        vm.expectRevert(EnforcedPause.selector);
        poolManager.supply(amount);
        poolManager.unpause();
        vm.stopPrank();

        vm.expectRevert("Pool not initialized");
        poolManager.supply(amount);
    }

    function testSupply_Success() public {
        uint256 amount = 1000 * 10 ** FBTCDecimal;

        vm.prank(owner);
        poolManager.createPool(user);
        vm.stopPrank();

        mockFBTC0.mint(user, amount);
        assertEq(mockFBTC0.balanceOf(user), amount);

        vm.startPrank(user);
        mockFBTC0.approve(address(poolManager), amount);

        poolManager.supply(amount);

        DataTypes.UserPoolReserveInformation memory reserveInfo = poolManager
            .getUserPoolReserveInformation(user);

        DataTypes.PoolManagerReserveInformation
            memory poolManagerReserve = poolManager
                .getPoolManagerReserveInformation();

        assertEq(mockFBTC0.balanceOf(address(mockFBTC1)), amount);
        assertEq(mockFBTC1.balanceOf(address(poolManager)), amount);
        assertEq(reserveInfo.collateral, amount);
        assertEq(poolManagerReserve.collateral, amount);
        assertEq(mockFBTC0.balanceOf(user), 0);
    }

    function testBorrow_Failed() public {
        uint256 price = 60000 * 10 ** OracleDecimal;
        uint256 supplyAmount = 1000 * 10 ** FBTCDecimal;
        uint256 borrowAmount = ((1000 * 60000 * ltv) / denominator) *
            10 ** USDTDecimal;
        aggregatorMock.setLatestAnswer(int(price));

        vm.startPrank(emergencyContoller);
        poolManager.pause();
        vm.expectRevert(EnforcedPause.selector);
        poolManager.borrow(borrowAmount);
        poolManager.unpause();
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert("Pool not initialized");
        poolManager.borrow(borrowAmount);

        vm.prank(owner);
        poolManager.createPool(user);

        vm.startPrank(user);
        mockFBTC0.mint(user, supplyAmount);
        mockFBTC0.approve(address(poolManager), supplyAmount);
        poolManager.supply(supplyAmount);

        vm.expectRevert("Requested amount exceeds allowable loanToValue");
        poolManager.borrow(borrowAmount + 1);
    }

    function testBorrow_Success() public {
        uint256 price = 60000 * 10 ** OracleDecimal;
        uint256 supplyAmount = 1000 * 10 ** FBTCDecimal;
        uint256 borrowAmount = ((1000 * 60000 * ltv) / denominator) *
            10 ** USDTDecimal;
        aggregatorMock.setLatestAnswer(int(price));

        vm.prank(owner);
        poolManager.createPool(user);

        vm.startPrank(user);
        mockFBTC0.mint(user, supplyAmount);
        mockFBTC0.approve(address(poolManager), supplyAmount);
        poolManager.supply(supplyAmount);

        poolManager.borrow(borrowAmount);

        DataTypes.UserPoolReserveInformation memory reserveInfo = poolManager
            .getUserPoolReserveInformation(user);
        DataTypes.PoolManagerReserveInformation
            memory poolManagerReserve = poolManager
                .getPoolManagerReserveInformation();

        assertEq(reserveInfo.debt, borrowAmount);
        assertEq(reserveInfo.claimableUSDT, borrowAmount);
        assertEq(poolManagerReserve.debt, borrowAmount);
        assertEq(poolManagerReserve.claimableUSDT, borrowAmount);
    }

    function testClaimUSDT_Failed() public {
        uint256 price = 60000 * 10 ** OracleDecimal;
        uint256 supplyAmount = 1000 * 10 ** FBTCDecimal;
        uint256 borrowAmount = ((1000 * 60000 * ltv) / denominator) *
            10 ** USDTDecimal;
        aggregatorMock.setLatestAnswer(int(price));

        vm.startPrank(emergencyContoller);
        poolManager.pause();
        vm.expectRevert(EnforcedPause.selector);
        poolManager.claimUSDT(borrowAmount);
        poolManager.unpause();
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert("Pool not initialized");
        poolManager.claimUSDT(borrowAmount);

        vm.prank(owner);
        poolManager.createPool(user);

        vm.startPrank(user);
        mockFBTC0.mint(user, supplyAmount);
        mockFBTC0.approve(address(poolManager), supplyAmount);
        poolManager.supply(supplyAmount);
        poolManager.borrow(borrowAmount);

        uint256 excessBorrowAmount = borrowAmount + 1;
        vm.expectRevert("Insufficient claimableUSDT amount");
        poolManager.claimUSDT(excessBorrowAmount);
    }

    function testClaimUSDT_Success() public {
        uint256 price = 60000 * 10 ** OracleDecimal;
        uint256 supplyAmount = 1000 * 10 ** FBTCDecimal;
        uint256 borrowAmount = ((1000 * 60000 * ltv) / denominator) *
            10 ** USDTDecimal;
        aggregatorMock.setLatestAnswer(int(price));

        vm.startPrank(avalonUSDTVault);
        mockUSDT.mint(avalonUSDTVault, borrowAmount);
        mockUSDT.approve(address(poolManager), borrowAmount);
        vm.stopPrank();

        vm.prank(owner);
        poolManager.createPool(user);

        vm.startPrank(user);
        mockFBTC0.mint(user, supplyAmount);
        mockFBTC0.approve(address(poolManager), supplyAmount);
        poolManager.supply(supplyAmount);

        poolManager.borrow(borrowAmount);
        poolManager.claimUSDT(borrowAmount);

        DataTypes.UserPoolReserveInformation memory reserveInfo = poolManager
            .getUserPoolReserveInformation(user);
        DataTypes.PoolManagerReserveInformation
            memory poolManagerReserve = poolManager
                .getPoolManagerReserveInformation();

        assertEq(reserveInfo.claimableUSDT, 0);
        assertEq(poolManagerReserve.claimableUSDT, 0);
        assertEq(mockUSDT.balanceOf(address(user)), borrowAmount);
        assertEq(mockUSDT.balanceOf(address(avalonUSDTVault)), 0);
    }

    function testRepay_Failed() public {
        uint256 price = 60000 * 10 ** OracleDecimal;
        uint256 supplyAmount = 1000 * 10 ** FBTCDecimal;
        uint256 borrowAmount = ((1000 * 60000 * ltv) / denominator) *
            10 ** USDTDecimal;
        aggregatorMock.setLatestAnswer(int(price));

        vm.startPrank(emergencyContoller);
        poolManager.pause();
        vm.expectRevert(EnforcedPause.selector);
        poolManager.repay(1);
        poolManager.unpause();
        vm.stopPrank();

        vm.startPrank(avalonUSDTVault);
        mockUSDT.mint(avalonUSDTVault, borrowAmount);
        mockUSDT.approve(address(poolManager), borrowAmount);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert("Pool not initialized");
        poolManager.repay(1);
    }

    function testRepayAPart_Success() public {
        uint256 price = 60000 * 10 ** OracleDecimal;
        uint256 supplyAmount = 1000 * 10 ** FBTCDecimal;
        uint256 borrowAmount = ((1000 * 60000 * ltv) / denominator) *
            10 ** USDTDecimal;
        aggregatorMock.setLatestAnswer(int(price));

        vm.startPrank(avalonUSDTVault);
        mockUSDT.mint(avalonUSDTVault, borrowAmount);
        mockUSDT.approve(address(poolManager), borrowAmount);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert("Pool not initialized");
        poolManager.repay(1);

        vm.prank(owner);
        poolManager.createPool(user);

        vm.startPrank(user);
        mockFBTC0.mint(user, supplyAmount);
        mockFBTC0.approve(address(poolManager), supplyAmount);
        poolManager.supply(supplyAmount);
        poolManager.borrow(borrowAmount);
        poolManager.claimUSDT(borrowAmount);

        skip(365 days);

        DataTypes.UserPoolReserveInformation memory reserveInfo = poolManager
            .getUserPoolReserveInformation(user);
        DataTypes.PoolManagerReserveInformation
            memory poolManagerReserveBeforeRepay = poolManager
                .getPoolManagerReserveInformation();

        uint256 repayAmount = borrowAmount;
        mockUSDT.approve(address(poolManager), repayAmount);
        poolManager.repay(repayAmount);

        DataTypes.UserPoolReserveInformation
            memory reserveInfoAfterRepay = poolManager
                .getUserPoolReserveInformation(user);
        DataTypes.PoolManagerReserveInformation
            memory poolManagerReserveAfterRepay = poolManager
                .getPoolManagerReserveInformation();

        assertEq(reserveInfoAfterRepay.debt, reserveInfo.debt - repayAmount);

        assertEq(
            poolManagerReserveAfterRepay.debt,
            poolManagerReserveBeforeRepay.debt - repayAmount
        );
        assertEq(
            mockUSDT.balanceOf(antaphaUSDTVault),
            repayAmount -
                (repayAmount * reserveInfo.debtToProtocol) /
                reserveInfo.debt
        );
        assertEq(
            mockUSDT.balanceOf(address(poolManager)),
            (repayAmount * reserveInfo.debtToProtocol) / reserveInfo.debt
        );
    }

    function testRepayAll_Success() public {
        uint256 price = 60000 * 10 ** OracleDecimal;
        uint256 supplyAmount = 1000 * 10 ** FBTCDecimal;
        uint256 borrowAmount = ((1000 * 60000 * ltv) / denominator) *
            10 ** USDTDecimal;
        aggregatorMock.setLatestAnswer(int(price));

        vm.startPrank(avalonUSDTVault);
        mockUSDT.mint(avalonUSDTVault, borrowAmount);
        mockUSDT.approve(address(poolManager), borrowAmount);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert("Pool not initialized");
        poolManager.repay(1);

        vm.prank(owner);
        poolManager.createPool(user);

        vm.startPrank(user);
        mockFBTC0.mint(user, supplyAmount);
        mockFBTC0.approve(address(poolManager), supplyAmount);
        poolManager.supply(supplyAmount);
        poolManager.borrow(borrowAmount);
        poolManager.claimUSDT(borrowAmount);

        skip(365 days);

        DataTypes.UserPoolReserveInformation memory reserveInfo = poolManager
            .getUserPoolReserveInformation(user);
        DataTypes.PoolManagerReserveInformation
            memory poolManagerReserveBeforeRepay = poolManager
                .getPoolManagerReserveInformation();

        uint256 repayAmount = reserveInfo.debt;
        mockUSDT.mint(user, repayAmount - borrowAmount);
        mockUSDT.approve(address(poolManager), repayAmount);
        poolManager.repay(repayAmount);

        DataTypes.UserPoolReserveInformation
            memory reserveInfoAfterRepay = poolManager
                .getUserPoolReserveInformation(user);
        DataTypes.PoolManagerReserveInformation
            memory poolManagerReserveAfterRepay = poolManager
                .getPoolManagerReserveInformation();
        assertEq(reserveInfoAfterRepay.debt, 0);
        assertEq(poolManagerReserveAfterRepay.debt, 0);
        assertEq(
            mockUSDT.balanceOf(antaphaUSDTVault),
            repayAmount -
                (repayAmount * reserveInfo.debtToProtocol) /
                reserveInfo.debt
        );
        assertEq(
            mockUSDT.balanceOf(address(poolManager)),
            (repayAmount * reserveInfo.debtToProtocol) / reserveInfo.debt
        );
    }

    function testLiquidate_Failed() public {
        uint256 price = 60000 * 10 ** OracleDecimal;
        uint256 supplyAmount = 1000 * 10 ** FBTCDecimal;
        uint256 borrowAmount = ((1000 * 60000 * ltv) / denominator) *
            10 ** USDTDecimal;
        aggregatorMock.setLatestAnswer(int(price));

        vm.startPrank(emergencyContoller);
        poolManager.pause();
        vm.expectRevert(EnforcedPause.selector);
        poolManager.liquidate(user, supplyAmount, borrowAmount);
        poolManager.unpause();
        vm.stopPrank();

        vm.startPrank(avalonUSDTVault);
        mockUSDT.mint(avalonUSDTVault, borrowAmount);
        mockUSDT.approve(address(poolManager), borrowAmount);
        vm.stopPrank();

        vm.prank(owner);
        poolManager.createPool(user);

        vm.startPrank(user);
        mockFBTC0.mint(user, supplyAmount);
        mockFBTC0.approve(address(poolManager), supplyAmount);
        poolManager.supply(supplyAmount);
        poolManager.borrow(borrowAmount);
        poolManager.claimUSDT(borrowAmount);
        vm.expectRevert(
            abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user)
        );
        poolManager.liquidate(user, supplyAmount, borrowAmount);
        vm.stopPrank();
    }

    function testLiquidate_Success() public {
        uint256 price = 60000 * 10 ** OracleDecimal;
        uint256 supplyAmount = 1000 * 10 ** FBTCDecimal;
        uint256 borrowAmount = ((1000 * 60000 * ltv) / denominator) *
            10 ** USDTDecimal;
        aggregatorMock.setLatestAnswer(int(price));

        vm.startPrank(avalonUSDTVault);
        mockUSDT.mint(avalonUSDTVault, borrowAmount);
        mockUSDT.approve(address(poolManager), borrowAmount);
        vm.stopPrank();

        vm.prank(owner);
        poolManager.createPool(user);

        vm.startPrank(user);
        mockFBTC0.mint(user, supplyAmount);
        mockFBTC0.approve(address(poolManager), supplyAmount);
        poolManager.supply(supplyAmount);
        poolManager.borrow(borrowAmount);
        poolManager.claimUSDT(borrowAmount);
        vm.stopPrank();

        DataTypes.UserPoolReserveInformation
            memory reserveInfoBeforeOperate = poolManager
                .getUserPoolReserveInformation(user);
        DataTypes.PoolManagerReserveInformation
            memory poolManagerReserveBeforeOperate = poolManager
                .getPoolManagerReserveInformation();
        vm.prank(owner);
        poolManager.liquidate(user, supplyAmount, borrowAmount);

        DataTypes.UserPoolReserveInformation
            memory reserveInfoAfterOperate = poolManager
                .getUserPoolReserveInformation(user);
        DataTypes.PoolManagerReserveInformation
            memory poolManagerReserveAfterOperate = poolManager
                .getPoolManagerReserveInformation();

        assertEq(
            reserveInfoBeforeOperate.collateral -
                reserveInfoAfterOperate.collateral,
            supplyAmount
        );
        assertEq(
            reserveInfoBeforeOperate.debt - reserveInfoAfterOperate.debt,
            borrowAmount
        );

        assertEq(
            poolManagerReserveBeforeOperate.collateral -
                poolManagerReserveAfterOperate.collateral,
            supplyAmount
        );
        assertEq(
            poolManagerReserveBeforeOperate.debt -
                poolManagerReserveAfterOperate.debt,
            borrowAmount
        );
    }

    function testWithdraw_Failed() public {
        uint256 price = 60000 * 10 ** OracleDecimal;
        uint256 supplyAmount = 1000 * 10 ** FBTCDecimal;
        uint256 borrowAmount = ((1000 * 60000 * ltv) / denominator) *
            10 ** USDTDecimal;
        aggregatorMock.setLatestAnswer(int(price));

        vm.startPrank(emergencyContoller);
        poolManager.pause();
        vm.expectRevert(EnforcedPause.selector);
        poolManager.withdraw(supplyAmount);
        poolManager.unpause();
        vm.stopPrank();

        vm.startPrank(avalonUSDTVault);
        mockUSDT.mint(avalonUSDTVault, borrowAmount);
        mockUSDT.approve(address(poolManager), borrowAmount);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert("Pool not initialized");
        poolManager.withdraw(supplyAmount);

        vm.prank(owner);
        poolManager.createPool(user);

        vm.startPrank(user);
        mockFBTC0.mint(user, supplyAmount);
        mockFBTC0.approve(address(poolManager), supplyAmount);
        poolManager.supply(supplyAmount);
        poolManager.borrow(borrowAmount);
        poolManager.claimUSDT(borrowAmount);

        DataTypes.UserPoolReserveInformation memory reserveInfo = poolManager
            .getUserPoolReserveInformation(user);
        assertEq(reserveInfo.claimableUSDT, 0);

        reserveInfo = poolManager.getUserPoolReserveInformation(user);
        mockUSDT.approve(address(poolManager), borrowAmount);
        vm.expectRevert(
            "Requested amount exceeds allowable liquiditionThreshold"
        );
        poolManager.withdraw(((supplyAmount * lts) / denominator) + 1);
    }

    function testWithdraw_Success() public {
        uint256 price = 60000 * 10 ** OracleDecimal;
        uint256 supplyAmount = 1000 * 10 ** FBTCDecimal;
        uint256 borrowAmount = ((1000 * 60000 * ltv) / denominator) *
            10 ** USDTDecimal;
        aggregatorMock.setLatestAnswer(int(price));

        vm.startPrank(avalonUSDTVault);
        mockUSDT.mint(avalonUSDTVault, borrowAmount);
        mockUSDT.approve(address(poolManager), borrowAmount);
        vm.stopPrank();

        vm.prank(owner);
        poolManager.createPool(user);

        vm.startPrank(user);
        mockFBTC0.mint(user, supplyAmount);
        mockFBTC0.approve(address(poolManager), supplyAmount);
        poolManager.supply(supplyAmount);
        poolManager.borrow(borrowAmount);
        poolManager.claimUSDT(borrowAmount);

        DataTypes.UserPoolReserveInformation memory reserveInfo = poolManager
            .getUserPoolReserveInformation(user);
        assertEq(reserveInfo.claimableUSDT, 0);

        reserveInfo = poolManager.getUserPoolReserveInformation(user);
        mockUSDT.approve(address(poolManager), borrowAmount);

        DataTypes.UserPoolReserveInformation
            memory reserveInfoBeforeOperate = poolManager
                .getUserPoolReserveInformation(user);
        DataTypes.PoolManagerReserveInformation
            memory poolManagerReserveBeforeOperate = poolManager
                .getPoolManagerReserveInformation();

        uint256 withdrawAmount = poolManager.calculateMaxWithdrawAmount(
            lts,
            supplyAmount,
            borrowAmount,
            price,
            USDTDecimal,
            FBTCDecimal,
            OracleDecimal
        );
        poolManager.withdraw(withdrawAmount);

        DataTypes.UserPoolReserveInformation
            memory reserveInfoAfterOperate = poolManager
                .getUserPoolReserveInformation(user);
        DataTypes.PoolManagerReserveInformation
            memory poolManagerReserveAfterOperate = poolManager
                .getPoolManagerReserveInformation();

        assertEq(
            reserveInfoBeforeOperate.collateral -
                reserveInfoAfterOperate.collateral,
            withdrawAmount
        );
        assertEq(
            reserveInfoAfterOperate.claimableBTC -
                reserveInfoBeforeOperate.claimableBTC,
            withdrawAmount
        );

        assertEq(
            poolManagerReserveBeforeOperate.collateral -
                poolManagerReserveAfterOperate.collateral,
            withdrawAmount
        );
        assertEq(
            poolManagerReserveAfterOperate.claimableBTC -
                poolManagerReserveBeforeOperate.claimableBTC,
            withdrawAmount
        );
    }

    function testWithdrawAll_Success() public {
        uint256 price = 60000 * 10 ** OracleDecimal;
        uint256 supplyAmount = 1000 * 10 ** FBTCDecimal;
        uint256 borrowAmount = ((1000 * 60000 * ltv) / denominator) *
            10 ** USDTDecimal;
        aggregatorMock.setLatestAnswer(int(price));

        vm.startPrank(avalonUSDTVault);
        mockUSDT.mint(avalonUSDTVault, borrowAmount);
        mockUSDT.approve(address(poolManager), borrowAmount);
        vm.stopPrank();

        vm.prank(owner);
        poolManager.createPool(user);

        vm.startPrank(user);
        mockFBTC0.mint(user, supplyAmount);
        mockFBTC0.approve(address(poolManager), supplyAmount);
        poolManager.supply(supplyAmount);

        skip(365 days);

        DataTypes.UserPoolReserveInformation memory reserveInfo = poolManager
            .getUserPoolReserveInformation(user);

        DataTypes.UserPoolReserveInformation
            memory reserveInfoBeforeOperate = poolManager
                .getUserPoolReserveInformation(user);
        DataTypes.PoolManagerReserveInformation
            memory poolManagerReserveBeforeOperate = poolManager
                .getPoolManagerReserveInformation();

        uint256 withdrawAmount = poolManager.calculateMaxWithdrawAmount(
            lts,
            reserveInfoBeforeOperate.collateral,
            reserveInfoBeforeOperate.debt,
            price,
            USDTDecimal,
            FBTCDecimal,
            OracleDecimal
        );

        poolManager.withdraw(withdrawAmount);

        DataTypes.UserPoolReserveInformation
            memory reserveInfoAfterOperate = poolManager
                .getUserPoolReserveInformation(user);
        DataTypes.PoolManagerReserveInformation
            memory poolManagerReserveAfterOperate = poolManager
                .getPoolManagerReserveInformation();

        assertEq(withdrawAmount, supplyAmount);

        assertEq(
            reserveInfoBeforeOperate.collateral -
                reserveInfoAfterOperate.collateral,
            withdrawAmount
        );
        assertEq(
            reserveInfoAfterOperate.claimableBTC -
                reserveInfoBeforeOperate.claimableBTC,
            withdrawAmount
        );

        assertEq(
            poolManagerReserveBeforeOperate.collateral -
                poolManagerReserveAfterOperate.collateral,
            withdrawAmount
        );
        assertEq(
            poolManagerReserveAfterOperate.claimableBTC -
                poolManagerReserveBeforeOperate.claimableBTC,
            withdrawAmount
        );
    }

    function testClaimBTC_Faled() public {
        uint256 price = 60000 * 10 ** OracleDecimal;
        uint256 supplyAmount = 1000 * 10 ** FBTCDecimal;
        uint256 borrowAmount = ((1000 * 60000 * ltv) / denominator) *
            10 ** USDTDecimal;
        aggregatorMock.setLatestAnswer(int(price));

        vm.startPrank(emergencyContoller);
        poolManager.pause();
        vm.expectRevert(EnforcedPause.selector);
        poolManager.claimBTC(supplyAmount / 4);
        poolManager.unpause();
        vm.stopPrank();

        vm.startPrank(avalonUSDTVault);
        mockUSDT.mint(avalonUSDTVault, borrowAmount);
        mockUSDT.approve(address(poolManager), borrowAmount);
        vm.stopPrank();

        vm.expectRevert("Pool not initialized");
        poolManager.claimBTC(supplyAmount / 4);

        vm.prank(owner);
        poolManager.createPool(user);

        vm.startPrank(user);
        mockFBTC0.mint(user, supplyAmount);
        mockFBTC0.approve(address(poolManager), supplyAmount);

        poolManager.supply(supplyAmount);
        aggregatorMock.setLatestAnswer(int(60000 * 10 ** OracleDecimal));

        poolManager.borrow(borrowAmount);

        poolManager.claimUSDT(borrowAmount);

        DataTypes.UserPoolReserveInformation memory reserveInfo = poolManager
            .getUserPoolReserveInformation(user);

        assertEq(reserveInfo.claimableUSDT, 0);
        skip(365 days);

        reserveInfo = poolManager.getUserPoolReserveInformation(user);

        uint256 withdrawAmount = poolManager.calculateMaxWithdrawAmount(
            lts,
            supplyAmount,
            reserveInfo.debt,
            price,
            USDTDecimal,
            FBTCDecimal,
            OracleDecimal
        );
        poolManager.withdraw(withdrawAmount);

        vm.expectRevert("Exceed claimBTC limit");
        poolManager.claimBTC(withdrawAmount + 1);
    }

    function testClaimBTC_Success() public {
        uint256 price = 60000 * 10 ** OracleDecimal;
        uint256 supplyAmount = 1000 * 10 ** FBTCDecimal;
        uint256 borrowAmount = ((1000 * 60000 * ltv) / denominator) *
            10 ** USDTDecimal;
        aggregatorMock.setLatestAnswer(int(price));

        vm.startPrank(avalonUSDTVault);
        mockUSDT.mint(avalonUSDTVault, borrowAmount);
        mockUSDT.approve(address(poolManager), borrowAmount);
        vm.stopPrank();

        vm.prank(owner);
        poolManager.createPool(user);

        vm.startPrank(user);
        mockFBTC0.mint(user, supplyAmount);
        mockFBTC0.approve(address(poolManager), supplyAmount);
        poolManager.supply(supplyAmount);
        poolManager.borrow(borrowAmount);
        poolManager.claimUSDT(borrowAmount);

        skip(365 days);

        DataTypes.UserPoolReserveInformation memory reserveInfo = poolManager
            .getUserPoolReserveInformation(user);
        uint256 withdrawAmount = poolManager.calculateMaxWithdrawAmount(
            lts,
            supplyAmount,
            reserveInfo.debt,
            price,
            USDTDecimal,
            FBTCDecimal,
            OracleDecimal
        );
        poolManager.withdraw(withdrawAmount);
        poolManager.claimBTC(withdrawAmount);

        reserveInfo = poolManager.getUserPoolReserveInformation(user);
        DataTypes.PoolManagerReserveInformation
            memory poolManagerReserve = poolManager
                .getPoolManagerReserveInformation();

        assertEq(reserveInfo.claimableBTC, 0);
        assertEq(poolManagerReserve.claimableBTC, 0);
        assertEq(mockFBTC0.balanceOf(address(user)), withdrawAmount);
        assertEq(
            mockFBTC1.balanceOf(address(poolManager)),
            supplyAmount - withdrawAmount
        );
    }

    function testClaimProtocolEarnings() public {
        vm.startPrank(owner);
        DataTypes.PoolManagerConfig memory config = DataTypes
            .PoolManagerConfig({
                DEFAULT_LIQUIDATION_THRESHOLD: 5000,
                DEFAULT_POOL_INTEREST_RATE: 500,
                DEFAULT_LTV: 500,
                DEFAULT_PROTOCOLL_INTEREST_RATE: 100,
                USDT: mockUSDT,
                FBTC0: mockFBTC0,
                FBTC1: mockFBTC1,
                FBTCOracle: fbtcOracle,
                AvalonUSDTVault: address(0x789),
                AntaphaUSDTVault: address(0xABC)
            });
        poolManager.setPoolManagerConfig(config);

        uint256 initialAdminBalance = mockUSDT.balanceOf(owner);
        uint256 protocolProfit = 1000 ether;
        vm.store(
            address(poolManager),
            bytes32(uint256(1)),
            bytes32(protocolProfit)
        );

        mockUSDT.mint(address(poolManager), protocolProfit);
        poolManager.claimProtocolEarnings();

        uint256 newAdminBalance = mockUSDT.balanceOf(owner);
        assertEq(newAdminBalance, initialAdminBalance + protocolProfit);
        assertEq(poolManager.getProtocolProfitUnclaimed(), 0);
        vm.stopPrank();

        vm.startPrank(emergencyContoller);
        poolManager.pause();
        vm.expectRevert(EnforcedPause.selector);
        poolManager.claimProtocolEarnings();
        poolManager.unpause();
        vm.stopPrank();
    }

    function testSetUserPoolConfig_Failed() public {
        address nonAdmin = address(0x123);
        vm.startPrank(emergencyContoller);
        poolManager.pause();
        vm.expectRevert(EnforcedPause.selector);
        poolManager.setUserPoolConfig(user, 500, 500, 8000, 9500);
        poolManager.unpause();
        vm.stopPrank();

        vm.prank(nonAdmin);
        vm.expectRevert(
            abi.encodeWithSignature(
                "OwnableUnauthorizedAccount(address)",
                nonAdmin
            )
        );
        poolManager.setUserPoolConfig(user, 500, 500, 8000, 9500);

        vm.prank(address(owner));
        vm.expectRevert("Pool not initialized");
        poolManager.setUserPoolConfig(user, 500, 500, 8000, 9500);
    }

    function testSetUserPoolConfig_Success() public {
        uint256 price = 60000 * 10 ** OracleDecimal;
        uint256 supplyAmount = 1000 * 10 ** FBTCDecimal;
        uint256 borrowAmount = ((1000 * 60000 * ltv) / denominator) *
            10 ** USDTDecimal;
        aggregatorMock.setLatestAnswer(int(price));

        vm.prank(owner);
        poolManager.createPool(user);

        vm.startPrank(user);
        mockFBTC0.mint(user, supplyAmount);
        mockFBTC0.approve(address(poolManager), supplyAmount);
        poolManager.supply(supplyAmount);
        poolManager.borrow(borrowAmount);
        vm.stopPrank();

        vm.prank(owner);
        poolManager.setUserPoolConfig(user, 500, 500, 8000, 9500);

        DataTypes.UserPoolConfig memory userPoolConfig = poolManager
            .getUserPoolConfig(user);

        assertEq(userPoolConfig.poolInterestRate, 500);
        assertEq(userPoolConfig.liquidationThreshold, 9500);
        assertEq(userPoolConfig.protocolInterestRate, 500);
        assertEq(userPoolConfig.loanToValue, 8000);
    }

    function testUpdateState() public {
        uint256 price = 60000 * 10 ** OracleDecimal;
        uint256 supplyAmount = 1000 * 10 ** FBTCDecimal;
        uint256 borrowAmount = ((1000 * 60000 * ltv) / denominator) *
            10 ** USDTDecimal;
        aggregatorMock.setLatestAnswer(int(price));

        vm.startPrank(avalonUSDTVault);
        mockUSDT.mint(avalonUSDTVault, borrowAmount);
        mockUSDT.approve(address(poolManager), borrowAmount);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert("Pool not initialized");
        poolManager.repay(1);

        vm.prank(owner);
        poolManager.createPool(user);

        vm.startPrank(user);
        mockFBTC0.mint(user, supplyAmount);
        mockFBTC0.approve(address(poolManager), supplyAmount);
        poolManager.supply(supplyAmount);
        poolManager.borrow(borrowAmount);
        poolManager.claimUSDT(borrowAmount);

        skip(365 days);

        DataTypes.UserPoolReserveInformation
            memory reserveInfoBeforeUpdateState = poolManager
                .getUserPoolReserveInformationWithoutAddDebt(user);

        DataTypes.PoolManagerReserveInformation
            memory poolManagerReserveBeforUpdateState = poolManager
                .getPoolManagerReserveInformationWithoutAddDebt();

        DataTypes.UserPoolConfig memory userPoolConfig = poolManager
            .getUserPoolConfig(user);

        uint256 protocolUnclaimedBeforeUpdateState = poolManager
            .getProtocolProfitUnclaimed();

        uint256 protocolAccumulateBeforeUpdateState = poolManager
            .getProtocolProfitAccumulate();

        poolManager.updateState(user);

        (uint256 feeForPool, uint256 feeForProtocol) = poolManager
            .calculateAccumulatedDebt(
                reserveInfoBeforeUpdateState.debt,
                userPoolConfig.poolInterestRate,
                userPoolConfig.protocolInterestRate,
                reserveInfoBeforeUpdateState.timeStampIndex
            );

        DataTypes.UserPoolReserveInformation
            memory reserveInfoAfterUpdateState = poolManager
                .getUserPoolReserveInformationWithoutAddDebt(user);

        DataTypes.PoolManagerReserveInformation
            memory poolManagerReserveAfterUpdateState = poolManager
                .getPoolManagerReserveInformationWithoutAddDebt();

        uint256 protocolUnclaimedAfterUpdateState = poolManager
            .getProtocolProfitUnclaimed();

        uint256 protocolAccumulateAfterUpdateState = poolManager
            .getProtocolProfitAccumulate();

        assertEq(
            reserveInfoAfterUpdateState.debt -
                reserveInfoBeforeUpdateState.debt,
            feeForPool + feeForProtocol
        );
        assertEq(
            reserveInfoAfterUpdateState.debtToProtocol -
                reserveInfoBeforeUpdateState.debtToProtocol,
            feeForProtocol
        );
        assertEq(
            protocolUnclaimedAfterUpdateState -
                protocolUnclaimedBeforeUpdateState,
            feeForProtocol
        );
        assertEq(
            protocolAccumulateAfterUpdateState -
                protocolAccumulateBeforeUpdateState,
            feeForProtocol
        );
        assertEq(
            poolManagerReserveAfterUpdateState.debt -
                poolManagerReserveBeforUpdateState.debt,
            feeForPool + feeForProtocol
        );
        assertEq(reserveInfoAfterUpdateState.timeStampIndex, block.timestamp);
    }

    function testCalculateAccumulatedDebt() public {
        uint40 timeStampIndex = uint40(block.timestamp);
        uint256 debt = 100 * 10 ** (4 + USDTDecimal);
        uint256 interestRate = 100; // 1%
        uint256 accurateFee = 10050167100;
        skip(365 days);

        (uint256 feeForPool, uint256 feeForProtocol) = poolManager
            .calculateAccumulatedDebt(
                debt,
                interestRate,
                interestRate,
                timeStampIndex
            );

        assertTrue((accurateFee - feeForPool) * 10000 <= accurateFee);
    }

    function testCalculateMaxBorrowAmount() public {
        uint256 maxBorrowAmount;

        maxBorrowAmount = poolManager.calculateMaxBorrowAmount(
            ltv,
            200 * 10 ** FBTCDecimal,
            0,
            60000 * 10 ** OracleDecimal,
            USDTDecimal,
            FBTCDecimal,
            OracleDecimal
        );

        assertEq(
            maxBorrowAmount,
            ((60000 * 200 * ltv) / denominator) * 10 ** USDTDecimal
        );

        maxBorrowAmount = poolManager.calculateMaxBorrowAmount(
            ltv,
            200 * 10 ** FBTCDecimal,
            6000000 * 10 ** USDTDecimal,
            60000 * 10 ** OracleDecimal,
            USDTDecimal,
            FBTCDecimal,
            OracleDecimal
        );

        assertEq(maxBorrowAmount, 0);

        maxBorrowAmount = poolManager.calculateMaxBorrowAmount(
            ltv,
            200 * 10 ** FBTCDecimal,
            3000000 * 10 ** USDTDecimal,
            60000 * 10 ** OracleDecimal,
            USDTDecimal,
            FBTCDecimal,
            OracleDecimal
        );

        assertEq(maxBorrowAmount, 3000000 * 10 ** USDTDecimal);
    }

    function testCalculateMaxWithdrawAmount() public {
        uint256 maxWithdrawAmount;

        maxWithdrawAmount = poolManager.calculateMaxWithdrawAmount(
            lts,
            100 * 10 ** FBTCDecimal,
            0,
            60000 * 10 ** OracleDecimal,
            USDTDecimal,
            FBTCDecimal,
            OracleDecimal
        );

        assertEq(maxWithdrawAmount, 100 * 10 ** FBTCDecimal);

        maxWithdrawAmount = poolManager.calculateMaxWithdrawAmount(
            lts,
            1000 * 10 ** FBTCDecimal,
            30000000 * 10 ** USDTDecimal,
            60000 * 10 ** OracleDecimal,
            USDTDecimal,
            FBTCDecimal,
            OracleDecimal
        );

        assertEq(maxWithdrawAmount, 375 * 10 ** FBTCDecimal);
    }

    function testGetPoolManagerReserveInformation() public {
        uint256 price = 60000 * 10 ** OracleDecimal;
        uint256 supplyAmount = 1000 * 10 ** FBTCDecimal;
        uint256 borrowAmount = ((1000 * 60000 * ltv) / denominator) *
            10 ** USDTDecimal;
        aggregatorMock.setLatestAnswer(int(price));

        address[10] memory userList = [
            address(0x011),
            address(0x012),
            address(0x013),
            address(0x014),
            address(0x015),
            address(0x016),
            address(0x017),
            address(0x018),
            address(0x019),
            address(0x020)
        ];
        for (uint256 index = 0; index < userList.length; index++) {
            vm.prank(owner);
            poolManager.createPool(userList[index]);

            vm.startPrank(userList[index]);
            mockFBTC0.mint(userList[index], supplyAmount);
            mockFBTC0.approve(address(poolManager), supplyAmount);
            poolManager.supply(supplyAmount);
            poolManager.borrow(borrowAmount);
            uint256 withdrawAmount = poolManager.calculateMaxWithdrawAmount(
                lts,
                supplyAmount,
                borrowAmount,
                price,
                USDTDecimal,
                FBTCDecimal,
                OracleDecimal
            );
            poolManager.withdraw(withdrawAmount);
            vm.stopPrank();
        }

        skip(365 days);
        uint256 expectTotalDebt;
        for (uint256 index = 0; index < userList.length; index++) {
            expectTotalDebt += poolManager
                .getUserPoolReserveInformation(userList[index])
                .debt;
        }

        DataTypes.PoolManagerReserveInformation
            memory poolManagerReserve = poolManager
                .getPoolManagerReserveInformation();
        DataTypes.PoolManagerReserveInformation
            memory poolManagerReserveAfterUpdateState = poolManager
                .getPoolManagerReserveInformationWithoutAddDebt();

        assertEq(poolManagerReserve.userAmount, 10);
        assertEq(poolManagerReserve.debt, expectTotalDebt);
        assertEq(
            poolManagerReserve.collateral,
            poolManagerReserveAfterUpdateState.collateral
        );
        assertEq(
            poolManagerReserve.claimableBTC,
            poolManagerReserveAfterUpdateState.claimableBTC
        );
        assertEq(
            poolManagerReserve.claimableUSDT,
            poolManagerReserveAfterUpdateState.claimableUSDT
        );
    }
}
