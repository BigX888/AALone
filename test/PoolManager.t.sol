// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./mock/MockERC20.sol";
import "./mock/MockAggregator.sol";
import "./mock/MockFBTC1.sol";
import "../src/protocol/FBTCOracle.sol";
import "../src/protocol/PoolManager.sol";
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
    PoolManager public poolManager;

    address public poolAdmin = address(0x001);
    address public oracleOwner = address(0x002);
    address public avalonUSDTVault = address(0x003);
    address public antaphaUSDTVault = address(0x004);
    address public user = address(0x010);

    function setUp() public {
        vm.startPrank(poolAdmin);
        aggregatorMock = new AggregatorMock();
        fbtcOracle = new FBTCOracle(aggregatorMock, oracleOwner);
        DataTypes.PoolManagerConfig memory config = DataTypes
            .PoolManagerConfig({
                DEFAULT_LIQUIDATION_THRESHOLD: lts,
                DEFAULT_POOL_INTEREST_RATE: poolInterest,
                DEFAULT_LTV: ltv,
                PROTOCOL_FEE_INTEREST_RATE: protocolInterest,
                USDT: mockUSDT,
                FBTC0: mockFBTC0,
                FBTC1: mockFBTC1,
                FBTCOracle: fbtcOracle,
                AvalonUSDTVault: avalonUSDTVault,
                AntaphaUSDTVault: antaphaUSDTVault
            });
        poolManager = new PoolManager();
        poolManager.initialize(poolAdmin);
        poolManager.setPoolManagerConfig(config);
        vm.stopPrank();
    }

    function testCreatePool_Failed() public {
        // Ensure non-admin cannot create a pool
        address nonAdmin = address(0x123);
        vm.prank(nonAdmin);
        vm.expectRevert();
        poolManager.createPool(user);

        vm.prank(address(poolAdmin));
        poolManager.createPool(user);

        vm.prank(address(poolAdmin));
        vm.expectRevert("Pool already initialized");
        poolManager.createPool(user);
    }

    function testCreatePool_Success() public {
        // Ensure the pool is not initialized initially
        DataTypes.UserPoolConfig memory initialConfig = poolManager
            .getUserPoolConfig(poolAdmin);
        assertFalse(initialConfig.init);

        // Set the role for the pool admin (mocking the role assignment)
        vm.prank(address(poolAdmin));
        // Create the pool
        poolManager.createPool(user);

        // Verify the pool is initialized with correct parameters
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
            storedConfig.PROTOCOL_FEE_INTEREST_RATE
        );
        assertEq(userPoolConfig.loanToValue, storedConfig.DEFAULT_LTV);
        assertEq(poolManagerReserve.userAmount, 1);
    }

    function testSupply_Failed() public {
        uint256 amount = 1000 * 10 ** FBTCDecimal;
        // Mint tokens to the user
        mockFBTC0.mint(poolAdmin, amount);
        assertEq(mockFBTC0.balanceOf(poolAdmin), amount);

        // Approve the PoolManager to spend the tokens
        mockFBTC0.approve(address(poolManager), amount);

        // Attempt to supply tokens to the pool without initialization
        vm.expectRevert("Pool not initialized");
        poolManager.supply(amount);
    }

    function testSupply_Success() public {
        uint256 amount = 1000 * 10 ** FBTCDecimal;

        // Ensure the pool is initialized
        vm.prank(poolAdmin);
        poolManager.createPool(user);
        vm.stopPrank();

        // Mint tokens to the user
        mockFBTC0.mint(user, amount);
        assertEq(mockFBTC0.balanceOf(user), amount);

        vm.startPrank(user);
        // Approve the PoolManager to spend the tokens
        mockFBTC0.approve(address(poolManager), amount);

        // Supply tokens to the pool
        poolManager.supply(amount);

        // Verify the user's pool reserve information
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

        vm.prank(user);
        vm.expectRevert("Pool not initialized");
        poolManager.borrow(borrowAmount);

        vm.prank(poolAdmin);
        poolManager.createPool(user);

        vm.startPrank(user);
        // Mint and supply tokens to the pool
        mockFBTC0.mint(user, supplyAmount);
        mockFBTC0.approve(address(poolManager), supplyAmount);
        poolManager.supply(supplyAmount);

        // Attempt to claimUSDT an amount that exceeds the allowable LTV
        vm.expectRevert("Requested amount exceeds allowable loanToValue");
        poolManager.borrow(borrowAmount + 1);
    }

    function testBorrow_Success() public {
        uint256 price = 60000 * 10 ** OracleDecimal;
        uint256 supplyAmount = 1000 * 10 ** FBTCDecimal;
        uint256 borrowAmount = ((1000 * 60000 * ltv) / denominator) *
            10 ** USDTDecimal;
        aggregatorMock.setLatestAnswer(int(price));

        vm.prank(poolAdmin);
        poolManager.createPool(user);

        vm.startPrank(user);
        mockFBTC0.mint(user, supplyAmount);
        mockFBTC0.approve(address(poolManager), supplyAmount);
        poolManager.supply(supplyAmount);

        // claimUSDT an amount within the allowable LTV
        poolManager.borrow(borrowAmount);

        // Verify the borrowing amount is updated correctly
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

        vm.prank(user);
        vm.expectRevert("Pool not initialized");
        poolManager.claimUSDT(borrowAmount);

        vm.prank(poolAdmin);
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

        vm.prank(poolAdmin);
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

        vm.prank(poolAdmin);
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

        uint256 repayAmount = borrowAmount;
        mockUSDT.approve(address(poolManager), repayAmount);
        poolManager.repay(repayAmount);
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

        vm.prank(poolAdmin);
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
    }

    function testLiquidate_Failed() public {
        uint256 price = 60000 * 10 ** OracleDecimal;
        uint256 supplyAmount = 1000 * 10 ** FBTCDecimal;
        uint256 borrowAmount = ((1000 * 60000 * ltv) / denominator) *
            10 ** USDTDecimal;
        aggregatorMock.setLatestAnswer(int(price));

        vm.startPrank(avalonUSDTVault);
        mockUSDT.mint(avalonUSDTVault, borrowAmount);
        mockUSDT.approve(address(poolManager), borrowAmount);
        vm.stopPrank();

        vm.prank(poolAdmin);
        poolManager.createPool(user);

        vm.startPrank(user);
        mockFBTC0.mint(user, supplyAmount);
        mockFBTC0.approve(address(poolManager), supplyAmount);
        poolManager.supply(supplyAmount);
        poolManager.borrow(borrowAmount);
        poolManager.claimUSDT(borrowAmount);
        vm.expectRevert();
        poolManager.liquidate(user, supplyAmount, borrowAmount);
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

        vm.prank(poolAdmin);
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
        vm.prank(poolAdmin);
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

        vm.startPrank(avalonUSDTVault);
        mockUSDT.mint(avalonUSDTVault, borrowAmount);
        mockUSDT.approve(address(poolManager), borrowAmount);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert("Pool not initialized");
        poolManager.withdraw(supplyAmount);

        vm.prank(poolAdmin);
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

        vm.prank(poolAdmin);
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

        vm.prank(poolAdmin);
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

        vm.startPrank(avalonUSDTVault);
        mockUSDT.mint(avalonUSDTVault, borrowAmount);
        mockUSDT.approve(address(poolManager), borrowAmount);
        vm.stopPrank();

        vm.expectRevert("Pool not initialized");
        poolManager.claimBTC(supplyAmount / 4);
        // Initialize the pool
        vm.prank(poolAdmin);
        poolManager.createPool(user);

        vm.startPrank(user);
        // Mint and supply tokens to the pool
        mockFBTC0.mint(user, supplyAmount);
        mockFBTC0.approve(address(poolManager), supplyAmount);

        poolManager.supply(supplyAmount);
        // Mock the FBTC oracle price
        aggregatorMock.setLatestAnswer(int(60000 * 10 ** OracleDecimal)); // 1 USDT per FBTC // 1 USDT per FBTC

        // claimUSDT an amount
        poolManager.borrow(borrowAmount);

        poolManager.claimUSDT(borrowAmount);

        // Verify the borrowing amount and total borrowed amount are updated correctly
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

        vm.prank(poolAdmin);
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
        vm.startPrank(poolAdmin);
        DataTypes.PoolManagerConfig memory config = DataTypes
            .PoolManagerConfig({
                DEFAULT_LIQUIDATION_THRESHOLD: 5000,
                DEFAULT_POOL_INTEREST_RATE: 500,
                DEFAULT_LTV: 500,
                PROTOCOL_FEE_INTEREST_RATE: 100,
                USDT: mockUSDT,
                FBTC0: mockFBTC0,
                FBTC1: mockFBTC1,
                FBTCOracle: fbtcOracle,
                AvalonUSDTVault: address(0x789),
                AntaphaUSDTVault: address(0xABC)
            });
        poolManager.setPoolManagerConfig(config);

        uint256 initialAdminBalance = mockUSDT.balanceOf(poolAdmin);
        uint256 protocolProfit = 1000 ether;
        vm.store(
            address(poolManager),
            bytes32(uint256(0)),
            bytes32(protocolProfit)
        );

        mockUSDT.mint(address(poolManager), protocolProfit);
        poolManager.claimProtocolEarnings();

        uint256 newAdminBalance = mockUSDT.balanceOf(poolAdmin);
        assertEq(newAdminBalance, initialAdminBalance + protocolProfit);
        assertEq(poolManager.getProtocolProfitUnclaimed(), 0);
        vm.stopPrank();
    }
}
