// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {GhoToken} from "gho-core/src/contracts/gho/GhoToken.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract NFGho is ERC721Holder {
    error UnsupportedCollateral();

    event CollateralDeposited(address indexed user, address indexed collateral, uint256 indexed _tokenId);
    event GhoMinted(address indexed user, uint256 amount);

    struct Collateral {
        mapping(uint256 tokenId => bool hasDeposited) hasDepositedTokenId;
        uint256 tokensCount; // each tokenId of a collection is considered fungible for now, since we're using floor price to calculate value
    }

    // Liquidation threshold is 80%
    // If loan value raises above 80% of collateral value, the loan can be liquidated
    uint256 public constant LIQUIDATION_THRESHOLD = 80;
    uint256 public constant LIQUIDATION_PRECISION = 100;

    GhoToken public ghoToken;
    address[] public supportedCollaterals;
    mapping(address collateral => bool isSupported) public isCollateralSupported;
    mapping(address collateral => address priceFeed) public priceFeeds;
    address public ethUsdPriceFeed; // TODO: can be stored in priceFeeds mapping

    mapping(address user => mapping(address collateralNFT => Collateral collateral)) internal collateralNFTs;
    mapping(address user => uint256 ghoMinted) internal ghoMinted;

    modifier onlySupportedCollateral(address _collateral) {
        if (!isCollateralSupported[_collateral]) {
            revert UnsupportedCollateral();
        }
        _;
    }

    constructor(
        GhoToken _ghoToken,
        address[] memory _supportedCollaterals,
        address[] memory _priceFeeds,
        address _ethUsdPriceFeed
    ) {
        ghoToken = _ghoToken;
        supportedCollaterals = _supportedCollaterals;
        ethUsdPriceFeed = _ethUsdPriceFeed;

        for (uint256 i = 0; i < _supportedCollaterals.length; i++) {
            isCollateralSupported[_supportedCollaterals[i]] = true;
            priceFeeds[_supportedCollaterals[i]] = _priceFeeds[i];
        }
    }

    function depositCollateral(address _collateral, uint256 _tokenId) external onlySupportedCollateral(_collateral) {
        collateralNFTs[msg.sender][_collateral].hasDepositedTokenId[_tokenId] = true;
        collateralNFTs[msg.sender][_collateral].tokensCount++;
        IERC721(_collateral).safeTransferFrom(msg.sender, address(this), _tokenId);
        emit CollateralDeposited(msg.sender, _collateral, _tokenId);
    }

    function mintGho(uint256 _amount) external {
        ghoMinted[msg.sender] += _amount;
        ghoToken.mint(msg.sender, _amount);
        emit GhoMinted(msg.sender, _amount);
    }

    function healthFactor(address user) public view returns (uint256) {
        uint256 _totalCollateralValueInUSD = totalCollateralValueInUSD(user);
        uint256 totalGhoMinted = ghoMintedOf(user);
        // health factor = (total collateral value in USD * liquidation threshold) / (total Gho value in USD)
        // adding 1e18 to keep precision after division with 1e18
        return (((_totalCollateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION) * 1e18) / totalGhoMinted;
    }

    function totalCollateralValueInUSD(address user) public view returns (uint256) {
        uint256 _totalCollateralValueInUSD;
        for (uint256 i = 0; i < supportedCollaterals.length; i++) {
            address collateral = supportedCollaterals[i];
            uint256 collateralTokensCount = collateralDepositedCount(user, collateral);
            uint256 collateralValueInUSD = nftFloorValueInUsd(collateral) * collateralTokensCount;
            _totalCollateralValueInUSD += collateralValueInUSD;
        }
        return _totalCollateralValueInUSD;
    }

    function nftFloorValueInUsd(address _nftAddress) public view returns (uint256) {
        uint256 nftFloorPriceInEth = nftFloorPrice(_nftAddress);
        uint256 ethUsdPrice = ethUsd();
        // USD price feed has 8 decimals
        // We scale it to 18 decimals: 1e8 * 1e10 / 1e18 = 1e18
        // nft value in usd = ethUsdPrice * nftFloorPriceInEth
        // TODO: generalize precision
        return ((ethUsdPrice * 1e10) * nftFloorPriceInEth) / 1e18;
    }

    function nftFloorPrice(address _nftAddress) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeeds[_nftAddress]);
        // * All Chainlink NFT Floor Price feed is in ETH with 18 decimals
        // TODO: use decimals() instead of assuming 18
        (, int256 _nftFloorPrice,,,) = priceFeed.latestRoundData();
        return uint256(_nftFloorPrice);
    }

    function ethUsd() public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(ethUsdPriceFeed);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // * Chainlink ETH/USD feed is in USD with 8 decimals
        return uint256(price);
    }

    function collateralDepositedCount(address _user, address _collateral) public view returns (uint256) {
        return collateralNFTs[_user][_collateral].tokensCount;
    }

    function hasDepositedCollateralToken(address _user, address _collateral, uint256 _tokenId)
        public
        view
        returns (bool)
    {
        return collateralNFTs[_user][_collateral].hasDepositedTokenId[_tokenId];
    }

    function ghoMintedOf(address _user) public view returns (uint256) {
        return ghoMinted[_user];
    }
}
