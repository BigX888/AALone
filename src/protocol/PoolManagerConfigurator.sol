// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./PoolManagerStorage.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

/**
 * @title PoolManagerConfigurator
 * @dev Contract for configuring and managing pool settings and user-specific configurations.
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

    function pause() external onlyEmergencyController {
        _pause();
    }

    function unpause() external onlyEmergencyController {
        _unpause();
    }

    function setPoolManagerConfig(
        DataTypes.PoolManagerConfig calldata configInput
    ) external onlyOwner {
        _poolManagerConfig = configInput;
    }

    function setEmergencyController(
        address emergencyController
    ) external onlyOwner {
        _emergencyController = emergencyController;
    }

    /**
     * @dev Sets the configuration for a user's pool.
     * @param user The address of the user.
     * @param configInput The configuration data for the user's pool.
     * Requirements:
     * - The caller must be the owner of the contract.
     */
    function setUserPoolConfig(
        address user,
        DataTypes.UserPoolConfig calldata configInput
    ) external virtual onlyOwner {
        _userPoolConfig[user] = configInput;
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
     * @dev Returns the pool manager reserve information.
     * @return The pool manager reserve information as a `DataTypes.PoolManagerReserveInformation` struct.
     */
    function getPoolManagerReserveInformation()
        external
        view
        returns (DataTypes.PoolManagerReserveInformation memory)
    {
        return _poolManagerReserveInformation;
    }

    /**
     * @dev Returns the unclaimed protocol profit.
     * @return The amount of unclaimed protocol profit as a uint256.
     */
    function getProtocolProfitUnclaimed() external view returns (uint256) {
        return _protocolProfitUnclaimed;
    }

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

    /**
     * @dev Returns the reserve information of a user's pool.
     * @param user The address of the user.
     * @return The user's pool reserve information as a `DataTypes.UserPoolReserveInformation` struct.
     */
    function getUserPoolReserveInformation(
        address user
    )
        external
        view
        virtual
        returns (DataTypes.UserPoolReserveInformation memory)
    {
        return _userPoolReserveInformation[user];
    }
}
