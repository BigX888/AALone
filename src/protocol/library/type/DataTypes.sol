// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "../../../interfaces/IFBTC1.sol";
import "../../../interfaces/IOracle.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DataTypes
 * @dev Library containing various data structures used in the pool management system.
 */
library DataTypes {
    /**
     * @dev Structure to hold the configuration of the Pool Manager.
     * @param DEFAULT_LIQUIDATION_THRESHOLD Default maximum withdrawal rate (e.g., 50%).
     * @param DEFAULT_POOL_INTEREST_RATE Default interest rate (e.g., 5%).
     * @param DEFAULT_LTV Default loan-to-value ratio (e.g., 5%).
     * @param DEFAULT_PROTOCOL_INTEREST_RATE Protocol fee ratio.
     * @param USDT ERC20 USDT contract.
     * @param FBTC0 ERC20 FBTC0 contract.
     * @param FBTC1 Interface for the FBTC1 contract.
     * @param FBTCOracle Interface for the FBTC Oracle contract.
     * @param AvalonUSDTVault Address of the Avalon USDT vault.
     * @param AntaphaUSDTVault Address of the Antapha USDT vault.
     */
    struct PoolManagerConfig {
        uint256 DEFAULT_LTV;
        uint256 DEFAULT_LIQUIDATION_THRESHOLD;
        uint256 DEFAULT_POOL_INTEREST_RATE;
        uint256 DEFAULT_PROTOCOL_INTEREST_RATE;
        IERC20 USDT;
        IERC20 FBTC0;
        IFBTC1 FBTC1;
        IFBTCOracle FBTCOracle;
        address AvalonUSDTVault;
        address AntaphaUSDTVault;
    }

    /**
     * @dev Structure to hold the reserve information of the Pool Manager.
     * @param userAmount Total amount deposited by the user.
     * @param collateral Total collateral provided by the user.
     * @param debt Total debt owed by the user.
     * @param claimableUSDT Amount of USDT that can be claimed by the user.
     * @param claimableBTC Amount of BTC that can be claimed by the user.
     */
    struct PoolManagerReserveInformation {
        uint256 userAmount;
        uint256 collateral;
        uint256 debt;
        uint256 claimableUSDT;
        uint256 claimableBTC;
    }

    /**
     * @dev Structure to hold the configuration of a user's pool.
     * @param init Indicates whether the user's pool is initialized.
     * @param poolInterestRate Interest rate for the user's pool.
     * @param protocolInterestRate Protocol interest rate for the user's pool.
     * @param loanToValue Loan-to-value ratio for the user's pool.
     * @param liquidationThreshold Maximum withdrawal rate for the user's pool.
     */
    struct UserPoolConfig {
        bool init;
        uint256 poolInterestRate;
        uint256 protocolInterestRate;
        uint256 loanToValue;
        uint256 liquidationThreshold;
    }

    /**
     * @dev Structure to hold the reserve information of a user's pool.
     * @param timeStampIndex Timestamp when the user last borrowed.
     * @param collateral Total supply in the user's pool.
     * @param debt Total amount borrowed from the user's pool.
     * @param debtToProtocol Debt owed to the protocol.
     * @param claimableUSDT Amount currently available for borrowing.
     * @param claimableBTC Amount currently available for withdrawal.
     */
    struct UserPoolReserveInformation {
        uint40 timeStampIndex;
        uint256 collateral;
        uint256 debt;
        uint256 debtToProtocol;
        uint256 claimableUSDT;
        uint256 claimableBTC;
    }
}
