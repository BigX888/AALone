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

    uint256 internal _protocolProfitUnclaimed;

    uint256 internal _protocolProfitAccumulate;

    address[] internal _userList;

    DataTypes.PoolManagerConfig internal _poolManagerConfig;

    DataTypes.PoolManagerReserveInformation
        internal _poolManagerReserveInformation;

    mapping(address => DataTypes.UserPoolConfig) internal _userPoolConfig;

    mapping(address => DataTypes.UserPoolReserveInformation)
        internal _userPoolReserveInformation;
}
