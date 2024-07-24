// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IOracle.sol";

/**
 * @title FBTCOracle
 * @dev Oracle contract for fetching the price of an asset.
 * This contract allows the owner to set the price source and expiration time,
 * and provides functions to retrieve the latest price and decimals of the asset.
 */
contract FBTCOracle is IFBTCOracle, Ownable {
    // Private variable to store the price source
    AggregatorV3Interface private _assetSource;
    // Private variable to store the expiration time
    uint256 private _expiredTime;

    /**
     * @dev Constructor that sets the initial asset source, owner, and expiration time.
     * @param assetSource The initial address of the asset's price source.
     * @param initialOwner The initial owner of the contract.
     * @param expiredTime The initial expiration time for the price data.
     */
    constructor(
        AggregatorV3Interface assetSource,
        address initialOwner,
        uint256 expiredTime
    ) Ownable(initialOwner) {
        _assetSource = assetSource;
        _expiredTime = expiredTime;
    }

    /**
     * @notice Sets the asset's price source.
     * @dev This function can only be called by the owner.
     * @param assetSource The address of the new asset price source.
     */
    function setAssetSource(
        AggregatorV3Interface assetSource
    ) external onlyOwner {
        _assetSource = assetSource;
        emit AssetSourceSet(address(assetSource));
    }

    /**
     * @notice Sets the expiration time for the price data.
     * @dev This function can only be called by the owner.
     * @param expiredTime The new expiration time for the price data.
     */
    function setExpiredTime(uint256 expiredTime) external onlyOwner {
        _expiredTime = expiredTime;
        emit ExpiredTimeSet(expiredTime);
    }

    /**
     * @dev Gets the latest price of the asset.
     * @return The latest price of the asset as a uint256.
     * @notice Reverts if the price data is expired.
     */
    function getAssetPrice() public view returns (uint256) {
        (, int answer, , uint256 timeStamp, ) = _assetSource.latestRoundData();

        if ((block.timestamp - timeStamp) <= _expiredTime) {
            return uint256(answer);
        } else {
            revert("price expired");
        }
    }

    /**
     * @dev Gets the expiration time for the price data.
     * @return The expiration time as a uint256.
     */
    function getExpiredTime() public view returns (uint256) {
        return _expiredTime;
    }

    /**
     * @dev Gets the number of decimals used by the price aggregator.
     * @return The number of decimals as a uint8.
     */
    function decimals() public view returns (uint8) {
        return _assetSource.decimals();
    }
}
