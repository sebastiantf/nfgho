// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@aave/core-v3/contracts/protocol/pool/Pool.sol";
import "@aave/core-v3/contracts/protocol/tokenization/AToken.sol";

/// @title ATokenMock
/// @notice Mock contract for Aave's aToken contract
contract ATokenMock is AToken {
    using WadRayMath for uint256;

    constructor(IPool pool) AToken(pool) {}

    function mint(address, address onBehalfOf, uint256 amount, uint256)
        external
        virtual
        override
        onlyPool
        returns (bool)
    {
        // mint
        _userState[onBehalfOf].balance += uint128(amount.rayDiv(1));
        return true;
    }
}
