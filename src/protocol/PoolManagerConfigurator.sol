// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./PoolManagerStorage.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

/**
 * @title PoolManagerConfigurator
 * @dev Contract for configuring and managing pool settings and user-specific configurations.
 * @notice This contract inherits from PoolManagerStorage, OwnableUpgradeable, and PausableUpgradeable.
 */
contract PoolManagerConfigurator is
    PoolManagerStorage,
    OwnableUpgradeable,
    PausableUpgradeable
{
    /**
     * @dev Modifier to check if the user's pool is initialized.
     */
    modifier onlyInitializedPool() {
        require(_userPoolConfig[msg.sender].init, "Pool not initialized");
        _;
    }

    /**
     * @dev Modifier to restrict access to the emergency controller.
     */
    modifier onlyEmergencyController() {
        require(
            msg.sender == _emergencyController,
            "caller is not emergencyController"
        );
        _;
    }

    /**
     * @dev Initializes the contract with the specified owner.
     * @param owner The address of the contract owner.
     */
    function initialize(address owner) public initializer {
        __Ownable_init(owner);
        __Pausable_init();
    }

    /**
     * @dev Pauses the contract. Can only be called by the emergency controller.
     */
    function pause() external onlyEmergencyController {
        _pause();
    }

    /**
     * @dev Unpauses the contract. Can only be called by the emergency controller.
     */
    function unpause() external onlyEmergencyController {
        _unpause();
    }

    /**
     * @dev Sets the pool manager configuration. Can only be called by the owner.
     * @param configInput The new configuration to set.
     */
    function setPoolManagerConfig(
        DataTypes.PoolManagerConfig calldata configInput
    ) external onlyOwner {
        _poolManagerConfig = configInput;
    }

    /**
     * @dev Sets the emergency controller address. Can only be called by the owner.
     * @param emergencyController The address of the new emergency controller.
     */
    function setEmergencyController(
        address emergencyController
    ) external onlyOwner {
        _emergencyController = emergencyController;
    }

    /**
     * @dev Returns the pool manager configuration.
     * @return The pool manager configuration as a `DataTypes.PoolManagerConfig` struct.
     */
    function getPoolManagerConfig()
        external
        view
        returns (DataTypes.PoolManagerConfig memory)
    {
        return _poolManagerConfig;
    }

    /**
     * @dev Returns the unclaimed protocol profit.
     * @return The amount of unclaimed protocol profit as a uint256.
     */
    function getProtocolProfitUnclaimed() external view returns (uint256) {
        return _protocolProfitUnclaimed;
    }

    /**
     * @dev Returns the address of the emergency controller.
     * @return The address of the emergency controller.
     */
    function getEmergencyController() external view returns (address) {
        return _emergencyController;
    }

    /**
     * @dev Returns the accumulated protocol profit.
     * @return The total accumulated protocol profit as a uint256.
     */
    function getProtocolProfitAccumulate() external view returns (uint256) {
        return _protocolProfitAccumulate;
    }

    /**
     * @dev Returns the configuration of a user's pool.
     * @param user The address of the user.
     * @return The user's pool configuration as a `DataTypes.UserPoolConfig` struct.
     */
    function getUserPoolConfig(
        address user
    ) external view returns (DataTypes.UserPoolConfig memory) {
        return _userPoolConfig[user];
    }
}
