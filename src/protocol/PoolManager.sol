// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "./PoolManagerConfigurator.sol";
import "./library/math/MathUtils.sol";
import "./library/math/WadRayMath.sol";
import "../interfaces/IPoolManager.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title PoolManager
 * @dev Manages liquidity pools and related operations.
 */
contract PoolManager is PoolManagerConfigurator, IPoolManager {
    using WadRayMath for uint256;
    using MathUtils for uint256;
    using SafeERC20 for IERC20;

    /**
     * @dev Creates a new liquidity pool.
     * Requirements:
     * - The caller must have the POOL_ADMIN_ROLE.
     * - The pool must not have been initialized.
     */
    function createPool(address user) external onlyOwner {
        DataTypes.PoolManagerConfig
            memory poolManagerConfig = _poolManagerConfig;
        DataTypes.UserPoolConfig storage userPoolConfig = _userPoolConfig[user];
        require(!userPoolConfig.init, "Pool already initialized");
        userPoolConfig.init = true;
        userPoolConfig.poolInterestRate = poolManagerConfig
            .DEFAULT_POOL_INTEREST_RATE;
        userPoolConfig.protocolInterestRate = poolManagerConfig
            .PROTOCOL_FEE_INTEREST_RATE;
        userPoolConfig.liquidationThreshold = poolManagerConfig
            .DEFAULT_LIQUIDATION_THRESHOLD;
        userPoolConfig.loanToValue = poolManagerConfig.DEFAULT_LTV;
        _poolManagerReserveInformation.userAmount += 1;
        emit PoolCreated(user, userPoolConfig);
    }

    /**
     * @dev Supplies tokens to the pool.
     * @param amount The amount of tokens to supply.
     * Requirements:
     * - The pool must have been initialized.
     */
    function supply(uint256 amount) external onlyInitializedPool {
        DataTypes.PoolManagerConfig
            memory poolManagerConfig = _poolManagerConfig;
        DataTypes.UserPoolReserveInformation
            storage userPoolReserveInformation = _userPoolReserveInformation[
                msg.sender
            ];

        poolManagerConfig.FBTC0.safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        poolManagerConfig.FBTC0.approve(
            address(poolManagerConfig.FBTC1),
            amount
        );
        poolManagerConfig.FBTC1.mintLockedFbtcRequest(amount);
        userPoolReserveInformation.collateral += amount;
        _poolManagerReserveInformation.collateral += amount;
        emit Supply(msg.sender, amount, userPoolReserveInformation);
    }

    /**
     * @dev Requests a loan from the pool.
     * @param amount The amount of the loan requested.
     * Requirements:
     * - The pool must have been initialized.
     * - The requested amount must not exceed the allowable loan-to-value ratio.
     */
    function borrow(uint256 amount) external onlyInitializedPool {
        updateState(msg.sender);

        DataTypes.PoolManagerConfig
            memory poolManagerConfig = _poolManagerConfig;
        DataTypes.UserPoolConfig storage userPoolConfig = _userPoolConfig[
            msg.sender
        ];
        DataTypes.UserPoolReserveInformation
            storage userPoolReserveInformation = _userPoolReserveInformation[
                msg.sender
            ];
        require(
            calculateMaxBorrowAmount(
                userPoolConfig.loanToValue,
                userPoolReserveInformation.collateral,
                userPoolReserveInformation.debt,
                poolManagerConfig.FBTCOracle.getAssetPrice(),
                IERC20Metadata(address(poolManagerConfig.USDT)).decimals(),
                IERC20Metadata(address(poolManagerConfig.FBTC0)).decimals(),
                poolManagerConfig.FBTCOracle.decimals()
            ) >= amount,
            "Requested amount exceeds allowable loanToValue"
        );

        userPoolReserveInformation.debt += amount;
        userPoolReserveInformation.claimableUSDT += amount;

        _poolManagerReserveInformation.debt += amount;
        _poolManagerReserveInformation.claimableUSDT += amount;

        emit Borrow(msg.sender, amount, userPoolReserveInformation);
    }

    /**
     * @dev Repays borrowed tokens.
     * @param amount The amount of tokens to repay.
     * Requirements:
     * - The pool must have been initialized.
     */
    function repay(uint256 amount) external payable onlyInitializedPool {
        updateState(msg.sender);

        DataTypes.PoolManagerConfig
            memory poolManagerConfig = _poolManagerConfig;
        DataTypes.UserPoolReserveInformation
            storage userPoolReserveInformation = _userPoolReserveInformation[
                msg.sender
            ];
        DataTypes.PoolManagerReserveInformation
            storage poolManagerReserveInformation = _poolManagerReserveInformation;

        amount = amount > userPoolReserveInformation.debt
            ? userPoolReserveInformation.debt
            : amount;

        poolManagerConfig.USDT.safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        uint256 repayAmountToProtocol = (amount *
            userPoolReserveInformation.debtToProtocol) /
            userPoolReserveInformation.debt;

        uint256 repayAmountToPool = amount - repayAmountToProtocol;

        poolManagerConfig.USDT.safeTransfer(
            poolManagerConfig.AntaphaUSDTVault,
            repayAmountToPool
        );

        userPoolReserveInformation.debt -= amount;
        userPoolReserveInformation.debtToProtocol -= repayAmountToProtocol;
        poolManagerReserveInformation.debt -= amount;

        emit Repay(msg.sender, amount, userPoolReserveInformation);
    }

    /**
     * @dev Requests a withdrawal from the pool.
     * @param amount The amount to claimBTC.
     * Requirements:
     * - The pool must have been initialized.
     * - The requested amount must not exceed the maximum allowable claimBTC amount.
     */
    function withdraw(uint256 amount) external onlyInitializedPool {
        updateState(msg.sender);

        DataTypes.PoolManagerConfig
            memory poolManagerConfig = _poolManagerConfig;
        DataTypes.UserPoolConfig memory userPoolConfig = _userPoolConfig[
            msg.sender
        ];
        DataTypes.UserPoolReserveInformation
            storage userPoolReserveInformation = _userPoolReserveInformation[
                msg.sender
            ];
        DataTypes.PoolManagerReserveInformation
            storage poolManagerReserveInformation = _poolManagerReserveInformation;

        require(
            calculateMaxWithdrawAmount(
                userPoolConfig.liquidationThreshold,
                userPoolReserveInformation.collateral,
                userPoolReserveInformation.debt,
                poolManagerConfig.FBTCOracle.getAssetPrice(),
                IERC20Metadata(address(poolManagerConfig.USDT)).decimals(),
                IERC20Metadata(address(poolManagerConfig.FBTC0)).decimals(),
                poolManagerConfig.FBTCOracle.decimals()
            ) >= amount,
            "Requested amount exceeds allowable liquiditionThreshold"
        );

        userPoolReserveInformation.collateral -= amount;
        userPoolReserveInformation.claimableBTC += amount;

        poolManagerReserveInformation.collateral -= amount;
        poolManagerReserveInformation.claimableBTC += amount;
        emit Withdraw(msg.sender, amount, userPoolReserveInformation);
    }

    /**
     * @dev Liquidates a portion of the user's collateral and debt.
     * @param user The address of the user being liquidated.
     * @param collateralDecrease The amount of collateral to decrease.
     * @param debtDecrease The amount of debt to decrease.
     * Requirements:
     * - The pool must have been initialized.
     * - Only the owner can call this function.
     */
    function liquidate(
        address user,
        uint256 collateralDecrease,
        uint256 debtDecrease
    ) external onlyOwner {
        updateState(user);

        DataTypes.PoolManagerConfig
            memory poolManagerConfig = _poolManagerConfig;
        DataTypes.UserPoolReserveInformation
            storage userPoolReserveInformation = _userPoolReserveInformation[
                user
            ];
        DataTypes.PoolManagerReserveInformation
            storage poolManagerReserveInformation = _poolManagerReserveInformation;

        userPoolReserveInformation.collateral -= collateralDecrease;
        userPoolReserveInformation.debt -= debtDecrease;

        poolManagerReserveInformation.collateral -= collateralDecrease;
        poolManagerReserveInformation.debt -= debtDecrease;

        poolManagerConfig.FBTC1.burn(collateralDecrease);
        emit Liquidation(user, collateralDecrease, debtDecrease);
    }

    /**
     * @dev Claims USDT from the pool.
     * @param amount The amount of tokens to claimUSDT.
     * Requirements:
     * - The pool must have been initialized.
     * - The amount to claimUSDT must not exceed the claimableUSDT amount.
     */
    function claimUSDT(uint256 amount) external onlyInitializedPool {
        DataTypes.PoolManagerConfig
            memory poolManagerConfig = _poolManagerConfig;
        DataTypes.UserPoolReserveInformation
            storage userPoolReserveInformation = _userPoolReserveInformation[
                msg.sender
            ];
        DataTypes.PoolManagerReserveInformation
            storage poolManagerReserveInformation = _poolManagerReserveInformation;

        require(
            userPoolReserveInformation.claimableUSDT >= amount,
            "Insufficient claimableUSDT amount"
        );
        userPoolReserveInformation.claimableUSDT -= amount;
        poolManagerReserveInformation.claimableUSDT -= amount;
        poolManagerConfig.USDT.safeTransferFrom(
            poolManagerConfig.AvalonUSDTVault,
            msg.sender,
            amount
        );
        emit ClaimUSDT(msg.sender, amount, userPoolReserveInformation);
    }

    /**
     * @dev Claim FBTC0 from the pool.
     * @param amount The amount of tokens to claimBTC.
     * Requirements:
     * - The pool must have been initialized.
     */
    function claimBTC(uint256 amount) external onlyInitializedPool {
        DataTypes.PoolManagerConfig
            memory poolManagerConfig = _poolManagerConfig;
        DataTypes.UserPoolReserveInformation
            storage userPoolReserveInformation = _userPoolReserveInformation[
                msg.sender
            ];
        DataTypes.PoolManagerReserveInformation
            storage poolManagerReserveInformation = _poolManagerReserveInformation;

        require(
            userPoolReserveInformation.claimableBTC >= amount,
            "Exceed claimBTC limit"
        );

        userPoolReserveInformation.claimableBTC -= amount;
        poolManagerReserveInformation.claimableBTC -= amount;
        poolManagerConfig.FBTC1.confirmRedeemFbtc(amount);
        poolManagerConfig.FBTC0.safeTransfer(msg.sender, amount);
        emit ClaimBTC(msg.sender, amount, userPoolReserveInformation);
    }

    /**
     * @dev Claims the accumulated protocol earnings.
     * Requirements:
     * - The caller must have the POOL_ADMIN_ROLE.
     */
    function claimProtocolEarnings() external onlyOwner {
        DataTypes.PoolManagerConfig
            memory poolManagerConfig = _poolManagerConfig;
        uint256 claimAmount = poolManagerConfig.USDT.balanceOf(address(this));
        poolManagerConfig.USDT.safeTransfer(msg.sender, claimAmount);
        _protocolProfitUnclaimed -= claimAmount;
    }

    /**
     * @dev Requests the minting of FBTC0 tokens.
     * @param amount The amount of FBTC0 tokens.
     * @param depositTxid The transaction ID of the deposit.
     * @param outputIndex The output index of the deposit transaction.
     */
    function requestMintFBTC0(
        uint256 amount,
        bytes32 depositTxid,
        uint256 outputIndex
    ) external {
        DataTypes.PoolManagerConfig
            memory poolManagerConfig = _poolManagerConfig;

        poolManagerConfig.FBTC1.redeemFbtcRequest(
            amount,
            depositTxid,
            outputIndex
        );

        emit RequestMintFBTC0(amount, depositTxid, outputIndex);
    }

    /**
     * @dev Sets the user's pool configuration.
     * @param user The address of the user.
     * @param configInput The user's pool configuration settings.
     * Requirements:
     * - Only the owner can call this function.
     */
    function setUserPoolConfig(
        address user,
        DataTypes.UserPoolConfig calldata configInput
    ) external override onlyOwner {
        updateState(user);
        _userPoolConfig[user] = configInput;
    }

    /**
     * @dev Updates the user's debt.
     * @param user The address of the user.
     */
    function updateState(address user) internal {
        // Load the user's pool configuration into memory
        DataTypes.UserPoolConfig memory userPoolConfig = _userPoolConfig[user];
        // Load the user's pool reserve information into storage
        DataTypes.UserPoolReserveInformation
            storage userPoolReserveInformation = _userPoolReserveInformation[
                user
            ];
        DataTypes.PoolManagerReserveInformation
            storage poolManagerReserveInformation = _poolManagerReserveInformation;

        (uint256 feeForPool, uint256 feeForProtocol) = calculateAccumulatedDebt(
            userPoolReserveInformation.debt,
            userPoolConfig.poolInterestRate,
            userPoolConfig.protocolInterestRate,
            userPoolReserveInformation.timeStampIndex
        );

        userPoolReserveInformation.timeStampIndex = uint40(block.timestamp);
        userPoolReserveInformation.debt += feeForPool + feeForProtocol;
        userPoolReserveInformation.debtToProtocol += feeForProtocol;
        poolManagerReserveInformation.debt += feeForPool + feeForProtocol;

        _protocolProfitUnclaimed += feeForProtocol;
        _protocolProfitAccumulate += feeForProtocol;
    }

    //------------------------view functions--------------------------
    /**
     * @dev Gets the user's pool reserve information.
     * @param user The address of the user.
     * @return reserveAfterUpdateDebt The user's pool reserve information after updating the debt.
     */
    function getUserPoolReserveInformation(
        address user
    )
        external
        view
        override
        returns (
            DataTypes.UserPoolReserveInformation memory reserveAfterUpdateDebt
        )
    {
        DataTypes.UserPoolConfig memory userPoolConfig = _userPoolConfig[user];
        DataTypes.UserPoolReserveInformation
            memory userPoolReserveInformation = _userPoolReserveInformation[
                user
            ];
        (uint256 feeForPool, uint256 feeForProtocol) = calculateAccumulatedDebt(
            userPoolReserveInformation.debt,
            userPoolConfig.poolInterestRate,
            userPoolConfig.protocolInterestRate,
            userPoolReserveInformation.timeStampIndex
        );

        reserveAfterUpdateDebt.timeStampIndex = userPoolReserveInformation
            .timeStampIndex;
        reserveAfterUpdateDebt.collateral = userPoolReserveInformation
            .collateral;
        reserveAfterUpdateDebt.claimableUSDT = userPoolReserveInformation
            .claimableUSDT;
        reserveAfterUpdateDebt.claimableBTC = userPoolReserveInformation
            .claimableBTC;
        reserveAfterUpdateDebt.debt =
            userPoolReserveInformation.debt +
            feeForPool +
            feeForProtocol;
        reserveAfterUpdateDebt.debtToProtocol =
            userPoolReserveInformation.debtToProtocol +
            feeForProtocol;
    }

    /**
     * @dev Calculates the increasing interest for both the pool and the protocol.
     * @param debt The total amount borrowed.
     * @param poolInterestRate The interest rate for the pool.
     * @param protocolInterestRate The interest rate for the protocol.
     * @param timeStampIndex The timestamp when the borrowing occurred.
     * @return feeForPool The calculated interest fee for the pool.
     * @return feeForProtocol The calculated interest fee for the protocol.
     */
    function calculateAccumulatedDebt(
        uint256 debt,
        uint256 poolInterestRate,
        uint256 protocolInterestRate,
        uint40 timeStampIndex
    ) public view returns (uint256 feeForPool, uint256 feeForProtocol) {
        feeForPool =
            debt.rayMul(
                MathUtils.calculateCompoundedInterest(
                    (poolInterestRate * WadRayMath.RAY) / DENOMINATOR,
                    timeStampIndex
                )
            ) -
            debt;

        // Calculate the fee for the protocol based on the protocol fee interest rate and borrowed timestamp
        feeForProtocol =
            debt.rayMul(
                MathUtils.calculateCompoundedInterest(
                    (protocolInterestRate * WadRayMath.RAY) / DENOMINATOR,
                    timeStampIndex
                )
            ) -
            debt;
    }

    /**
     * @dev Calculates the maximum borrowable amount.
     * @param loanToValue The loan-to-value ratio.
     * @param collateral The total supply in the pool.
     * @param FBTC0Price The price of the FBTC0 token.
     * @return The maximum amount that can be borrowed.
     */
    function calculateMaxBorrowAmount(
        uint256 loanToValue,
        uint256 collateral,
        uint256 debt,
        uint256 FBTC0Price,
        uint256 USDTDecimal,
        uint256 FBTC0Decimal,
        uint256 oracleDecimal
    ) public view returns (uint256) {
        return
            (((collateral * FBTC0Price * 10 ** USDTDecimal) /
                (10 ** FBTC0Decimal * 10 ** oracleDecimal)) * loanToValue) /
            DENOMINATOR -
            debt;
    }

    /**
     * @dev Calculates the maximum withdrawable amount.
     * @param collateral The total supply in the pool.
     * @param FBTC0Price The price of the FBTC0 token.
     * @return The maximum amount that can be withdrawn.
     */
    function calculateMaxWithdrawAmount(
        uint256 liquidationThreshold,
        uint256 collateral,
        uint256 debt,
        uint256 FBTC0Price,
        uint256 USDTDecimal,
        uint256 FBTC0Decimal,
        uint256 oracleDecimal
    ) public view returns (uint256) {
        if (debt == 0) {
            return collateral;
        } else {
            return
                collateral -
                (debt *
                    10 ** (oracleDecimal + FBTC0Decimal - USDTDecimal) *
                    DENOMINATOR) /
                (FBTC0Price * liquidationThreshold);
        }
    }
}
