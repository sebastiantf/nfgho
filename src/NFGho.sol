// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {GhoToken} from "gho-core/src/contracts/gho/GhoToken.sol";

contract NFGho is ERC721Holder {
    event CollateralDeposited(address indexed user, address indexed collateral, uint256 indexed _tokenId);

    // TODO: allow/disallow multiple tokenIds of same collection
    GhoToken public ghoToken;
    mapping(address user => mapping(address collateralNFT => uint256 tokenId)) internal collaterals;

    constructor(GhoToken _ghoToken) {
        ghoToken = _ghoToken;
    }

    function depositCollateral(address _collateral, uint256 _tokenId) external {
        collaterals[msg.sender][_collateral] = _tokenId;
        IERC721(_collateral).safeTransferFrom(msg.sender, address(this), _tokenId);
        emit CollateralDeposited(msg.sender, _collateral, _tokenId);
    }

    function collateralTokenIdOf(address _user, address _collateral) public view returns (uint256) {
        return collaterals[_user][_collateral];
    }
}
