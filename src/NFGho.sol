// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

contract NFGho is ERC721Holder {
    // TODO: allow/disallow multiple tokenIds of same collection
    mapping(address user => mapping(address collateralNFT => uint256 tokenId)) internal collaterals;

    function depositCollateral(address _collateral, uint256 _tokenId) external {
        collaterals[msg.sender][_collateral] = _tokenId;
        IERC721(_collateral).safeTransferFrom(msg.sender, address(this), _tokenId);
    }

    function collateralTokenIdOf(address _user, address _collateral) public view returns (uint256) {
        return collaterals[_user][_collateral];
    }
}
