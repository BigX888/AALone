// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "../protocol/library/type/DataTypes.sol";

/**
 * @title IPoolManager
 * @dev Interface for the PoolManager contract, defining events and function signatures.
 */
interface IPoolManager {
    /**
     * @dev Emitted when a new pool is created for a user.
     * @param user The address of the user for whom the pool was created.
     * @param userPoolConfig The configuration of the newly created user pool.
     */
    event PoolCreated(
        address indexed user,
        DataTypes.UserPoolConfig userPoolConfig
    );

    /**
     * @dev Emitted when a user supplies assets to their pool.
     * @param user The address of the user who supplied assets.
     * @param amount The amount of assets supplied.
     * @param userPoolReserveInformation The updated reserve information after the supply.
     */
    event Supply(
        address indexed user,
        uint256 amount,
        DataTypes.UserPoolReserveInformation userPoolReserveInformation
    );

    /**
     * @dev Emitted when a user borrows assets from their pool.
     * @param user The address of the user who borrowed assets.
     * @param amount The amount of assets borrowed.
     * @param userPoolReserveInformation The updated reserve information after the borrow.
     */
    event Borrow(
        address indexed user,
        uint256 amount,
        DataTypes.UserPoolReserveInformation userPoolReserveInformation
    );

    /**
     * @dev Emitted when a user claims USDT from their pool.
     * @param user The address of the user who claimed USDT.
     * @param amount The amount of USDT claimed.
     * @param userPoolReserveInformation The updated reserve information after the claim.
     */
    event ClaimUSDT(
        address indexed user,
        uint256 amount,
        DataTypes.UserPoolReserveInformation userPoolReserveInformation
    );

    /**
     * @dev Emitted when a user repays their debt.
     * @param user The address of the user who repaid.
     * @param amount The amount repaid.
     * @param userPoolReserveInformation The updated reserve information after the repayment.
     */
    event Repay(
        address indexed user,
        uint256 amount,
        DataTypes.UserPoolReserveInformation userPoolReserveInformation
    );

    /**
     * @dev Emitted when a user's position is liquidated.
     * @param user The address of the user whose position was liquidated.
     * @param collateral The amount of collateral liquidated.
     * @param debt The amount of debt covered by the liquidation.
     */
    event Liquidation(address indexed user, uint256 collateral, uint256 debt);

    /**
     * @dev Emitted when a user withdraws assets from their pool.
     * @param user The address of the user who withdrew assets.
     * @param amount The amount of assets withdrawn.
     * @param userPoolReserveInformation The updated reserve information after the withdrawal.
     */
    event Withdraw(
        address indexed user,
        uint256 amount,
        DataTypes.UserPoolReserveInformation userPoolReserveInformation
    );

    /**
     * @dev Emitted when a request to mint FBTC0 is made.
     * @param amount The amount of FBTC0 requested to be minted.
     * @param depositTxid The transaction ID of the deposit.
     * @param outputIndex The output index in the transaction.
     */
    event RequestMintFBTC0(
        uint256 amount,
        bytes32 depositTxid,
        uint256 outputIndex
    );

    /**
     * @dev Emitted when a user claims BTC from their pool.
     * @param user The address of the user who claimed BTC.
     * @param amount The amount of BTC claimed.
     * @param userPoolReserveInformation The updated reserve information after the claim.
     */
    event ClaimBTC(
        address indexed user,
        uint256 amount,
        DataTypes.UserPoolReserveInformation userPoolReserveInformation
    );

    /**
     * @dev Emitted when a user's pool state is updated.
     * @param user The address of the user whose pool state was updated.
     * @param feeForPool The fee allocated to the pool.
     * @param feeForProtocol The fee allocated to the protocol.
     */
    event UpdateState(
        address indexed user,
        uint256 feeForPool,
        uint256 feeForProtocol
    );

    /**
     * @dev Emitted when a user's pool configuration is updated.
     * @param user The address of the user whose pool configuration was updated.
     * @param poolInterestRate The new pool interest rate.
     * @param protocolInterestRate The new protocol interest rate.
     * @param loanToValue The new loan-to-value ratio.
     * @param liquidationThreshold The new liquidation threshold.
     */
    event UserPoolConfigUpdated(
        address indexed user,
        uint256 poolInterestRate,
        uint256 protocolInterestRate,
        uint256 loanToValue,
        uint256 liquidationThreshold
    );

    /**
     * @dev Emitted when protocol earnings are claimed.
     * @param claimant The address of the account that claimed the earnings.
     * @param amount The amount of earnings claimed.
     */
    event ProtocolEarningsClaimed(address indexed claimant, uint256 amount);

    function createPool(address user) external;

    function supply(uint256 amount) external;

    function borrow(uint256 amount) external;

    function repay(uint256 amount) external payable;

    function withdraw(uint256 amount) external;

    function liquidate(
        address user,
        uint256 collateralDecrease,
        uint256 debtDecrease
    ) external;

    function claimUSDT(uint256 amount) external;

    function claimBTC(uint256 amount) external;

    function claimProtocolEarnings() external;

    function requestMintFBTC0(
        uint256 amount,
        bytes32 depositTxid,
        uint256 outputIndex
    ) external;

    function setUserPoolConfig(
        address user,
        uint256 poolInterestRate,
        uint256 protocolInterestRate,
        uint256 loanToValue,
        uint256 liquidationThreshold
    ) external;

    function getUserPoolReserveInformation(
        address user
    )
        external
        view
        returns (
            DataTypes.UserPoolReserveInformation memory reserveAfterUpdateDebt
        );

    function getPoolManagerReserveInformation()
        external
        view
        returns (
            DataTypes.PoolManagerReserveInformation
                memory poolManagerReserveInfor
        );

    function calculateAccumulatedDebt(
        uint256 debt,
        uint256 poolInterestRate,
        uint256 protocolInterestRate,
        uint40 timeStampIndex
    ) external view returns (uint256 feeForPool, uint256 feeForProtocol);

    function calculateMaxBorrowAmount(
        uint256 loanToValue,
        uint256 collateral,
        uint256 debt,
        uint256 FBTC0Price,
        uint256 USDTDecimal,
        uint256 FBTC0Decimal,
        uint256 oracleDecimal
    ) external view returns (uint256);

    function calculateMaxWithdrawAmount(
        uint256 liquidationThreshold,
        uint256 collateral,
        uint256 debt,
        uint256 FBTC0Price,
        uint256 USDTDecimal,
        uint256 FBTC0Decimal,
        uint256 oracleDecimal
    ) external view returns (uint256);
}
