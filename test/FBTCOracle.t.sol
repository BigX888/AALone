// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/protocol/FBTCOracle.sol";
import "./mock/MockAggregator.sol";

contract FBTCOracleTest is Test {
    FBTCOracle public fbtcOracle;
    AggregatorMock public aggregatorMock;
    address public owner;
    address public otherAccount;

    function setUp() public {
        owner = address(this);
        otherAccount = address(0x123);
        aggregatorMock = new AggregatorMock();
        fbtcOracle = new FBTCOracle(aggregatorMock, owner, 3600);
    }

    function testInitialDeployment() public {
        assertEq(fbtcOracle.owner(), owner);
        assertEq(fbtcOracle.getAssetPrice(), 0);
    }

    function testSetAssetSource() public {
        AggregatorMock newAggregatorMock = new AggregatorMock();
        fbtcOracle.setAssetSource(newAggregatorMock);
        assertEq(fbtcOracle.getAssetPrice(), 0);
    }

    function testSetExpiredTime() public {
        assertEq(fbtcOracle.getExpiredTime(), 3600);
        fbtcOracle.setExpiredTime(100);
        assertEq(fbtcOracle.getExpiredTime(), 100);
    }

    function testGetAssetPrice_Failed() public {
        int256 newPrice = 20000 * 10 ** 8;
        aggregatorMock.setLatestAnswer(newPrice);
        assertEq(fbtcOracle.getAssetPrice(), uint256(newPrice));
        skip(365 days);
        vm.expectRevert("price expired");
        fbtcOracle.getAssetPrice();
    }

    function testGetAssetPrice() public {
        int256 newPrice = 20000 * 10 ** 8;
        aggregatorMock.setLatestAnswer(newPrice);
        assertEq(fbtcOracle.getAssetPrice(), uint256(newPrice));
    }
}
