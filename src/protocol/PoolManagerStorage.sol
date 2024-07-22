// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./library/type/DataTypes.sol";

/**
 * @title PoolManagerStorage
 * @dev Storage contract for managing pool-related data and access control.
 */
contract PoolManagerStorage {
    uint256 public constant DENOMINATOR = 10000;

    address internal _emergencyController;
    // Unclaimed protocol profit
    uint256 internal _protocolProfitUnclaimed;

    // Accumulated protocol profit
    uint256 internal _protocolProfitAccumulate;

    // Configuration data for the pool manager
    DataTypes.PoolManagerConfig internal _poolManagerConfig;

    // Mapping of user addresses to their pool reserve information
    mapping(address => DataTypes.UserPoolReserveInformation)
        internal _userPoolReserveInformation;

    // Mapping of user addresses to their pool configuration
    mapping(address => DataTypes.UserPoolConfig) internal _userPoolConfig;

    // Reserve information for the entire pool manager
    DataTypes.PoolManagerReserveInformation
        internal _poolManagerReserveInformation;
}
