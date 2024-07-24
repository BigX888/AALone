// SPDX-License-Identifier: MIT
// Chainlink Contracts v0.8
pragma solidity ^0.8.0;

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function version() external view returns (uint256);

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

/**
 * @title IFBTCOracle
 * @notice Interface for the FBTC Oracle contract
 */
interface IFBTCOracle {
    // Define an event that is emitted when the asset source is set
    event AssetSourceSet(address indexed assetSource);

    // Define an event that is emitted when the expired time is set
    event ExpiredTimeSet(uint256 expiredTime);

    /**
     * @notice Sets the asset's price source
     * @dev This function should be callable only by the contract owner
     * @param source The address of the source of the asset
     */
    function setAssetSource(AggregatorV3Interface source) external;

    /**
     * @notice Gets the price of the asset
     * @dev This is a view function that does not alter the blockchain state
     * @return The price of the asset
     */
    function getAssetPrice() external view returns (uint256);

    /**
     * @notice Gets the number of decimals used by the price source
     * @dev This is a view function that does not alter the blockchain state
     * @return The number of decimals
     */
    function decimals() external view returns (uint8);
}
