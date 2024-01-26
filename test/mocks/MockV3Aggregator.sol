// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract MockV3Aggregator {
    int256 public price;

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (0, price, 0, 0, 0);
    }

    function setPrice(int256 _price) external {
        price = _price;
    }
}
