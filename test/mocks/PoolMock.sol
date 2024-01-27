// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ATokenMock} from "./ATokenMock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title PoolMock
/// @notice Mock contract for Aave's Pool contract
contract PoolMock {
    ATokenMock public aToken;

    function supply(address asset, uint256 amount, address onBehalfOf, uint16) external virtual {
        require(IERC20(asset).transferFrom(msg.sender, address(aToken), amount));
        aToken.mint(msg.sender, onBehalfOf, amount, 1);
    }

    function setAToken(ATokenMock _aToken) external {
        aToken = _aToken;
    }

    // Compatibility with Aave's Pool contract:
    function ADDRESSES_PROVIDER() public pure returns (address) {
        return address(0);
    }

    function finalizeTransfer(address, address, address, uint256, uint256, uint256) external pure {
        return;
    }

    function getReserveNormalizedIncome(address) external pure returns (uint256) {
        return 1;
    }
}
