// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {GhoToken} from "gho-core/src/contracts/gho/GhoToken.sol";

contract NFGho is ERC721Holder {
    error UnsupportedCollateral();

    event CollateralDeposited(address indexed user, address indexed collateral, uint256 indexed _tokenId);
    event GhoMinted(address indexed user, uint256 amount);

    // TODO: allow/disallow multiple tokenIds of same collection
    GhoToken public ghoToken;
    address[] public supportedCollaterals;
    mapping(address collateral => bool isSupported) public isCollateralSupported;
    mapping(address user => mapping(address collateralNFT => uint256 tokenId)) internal collaterals;
    mapping(address user => uint256 ghoMinted) internal ghoMinted;

    modifier onlySupportedCollateral(address _collateral) {
        if (!isCollateralSupported[_collateral]) {
            revert UnsupportedCollateral();
        }
        _;
    }

    constructor(GhoToken _ghoToken, address[] memory _supportedCollaterals) {
        ghoToken = _ghoToken;
        supportedCollaterals = _supportedCollaterals;
        for (uint256 i = 0; i < _supportedCollaterals.length; i++) {
            isCollateralSupported[_supportedCollaterals[i]] = true;
        }
    }

    function depositCollateral(address _collateral, uint256 _tokenId) external onlySupportedCollateral(_collateral) {
        collaterals[msg.sender][_collateral] = _tokenId;
        IERC721(_collateral).safeTransferFrom(msg.sender, address(this), _tokenId);
        emit CollateralDeposited(msg.sender, _collateral, _tokenId);
    }

    function mintGho(uint256 _amount) external {
        ghoMinted[msg.sender] += _amount;
        ghoToken.mint(msg.sender, _amount);
        emit GhoMinted(msg.sender, _amount);
    }

    function collateralTokenIdOf(address _user, address _collateral) public view returns (uint256) {
        return collaterals[_user][_collateral];
    }

    function ghoMintedOf(address _user) public view returns (uint256) {
        return ghoMinted[_user];
    }
}
