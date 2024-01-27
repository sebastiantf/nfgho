// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {GhoToken} from "gho-core/src/contracts/gho/GhoToken.sol";
import {Gsm} from "gho-core/src/contracts/facilitators/gsm/Gsm.sol";
import {IGhoFacilitator} from "gho-core/src/contracts/gho/interfaces/IGhoFacilitator.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract NFGho is IGhoFacilitator, Ownable, ERC721Holder {
    /// @notice Thrown when unsupported collateral is used
    error UnsupportedCollateral();

    /// @notice Thrown when user updates their position but has insufficient health factor
    error InsufficientHealthFactor();

    /// @notice Thrown when liquidator tries to liquidate healthy position
    error SufficientHealthFactor();

    /// @notice Thrown when user tries to redeem collateral that they don't own
    error InvalidOwner();

    /// @notice Thrown when collaterals and price feeds list don't match
    error InvalidCollateralsAndPriceFeeds();

    /// @notice Emitted when a user deposits collateral
    /// @param user Address of the user
    /// @param collateral Address of the collateral
    /// @param tokenId Token ID of the collateral
    event CollateralDeposited(address indexed user, address indexed collateral, uint256 indexed tokenId);

    /// @notice Emitted when a user redeems collateral
    /// @param user Address of the user
    /// @param collateral Address of the collateral
    /// @param tokenId Token ID of the collateral
    event CollateralRedeemed(address indexed user, address indexed collateral, uint256 indexed tokenId);

    /// @notice Emitted gho debt is minted/taken
    /// @param user Address of the user
    /// @param amount Amount of gho minted
    event GhoMinted(address indexed user, uint256 amount);

    /// @notice Emitted gho debt is burned/repaid
    /// @param user Address of the user
    /// @param amount Amount of gho burned
    event GhoBurned(address indexed user, uint256 amount);

    /// @notice Emitted when a user's collateral is liquidated
    /// @param user Address of the user
    /// @param collateral Address of the collateral
    /// @param tokenId Token ID of the collateral
    /// @param ghoBurned Amount of gho burned
    event Liquidated(address indexed user, address indexed collateral, uint256 indexed tokenId, uint256 ghoBurned);

    /// @notice Collateral struct stores information about the collateral deposited by the user
    /// @param hasDepositedTokenId Whether the user has deposited the token ID
    /// @param tokensCount Number of tokens of a collection deposited by the user.
    ///                    Each tokenId of a collection is considered fungible for now,
    //                     since we're using floor price to calculate value.
    struct Collateral {
        mapping(uint256 => bool) hasDepositedTokenId;
        uint256 tokensCount;
    }

    /// @notice Liquidation threshold. If loan value raises above 80% of collateral value, the loan can be liquidated
    /// @dev 80% = 8000 bps = 0.8e4
    uint256 public constant LIQUIDATION_THRESHOLD = 0.8e4;

    /// @notice Fee charged by treasury on repaid Gho debt
    /// @dev 0.01% = 1 bps = 0.0001e4
    uint256 public fee = 0.0001e4;

    /// @notice Percentage factor used in calculations using bps
    /// @dev 100% = 10000 bps = 1e4
    uint256 public constant PERCENTAGE_FACTOR = 1e4;

    /// @notice Gho token
    GhoToken public ghoToken;

    /// @notice Gsm
    Gsm public gsm;

    /// @notice Address of the treasury
    address public ghoTreasury;

    /// @notice List of supported collaterals
    address[] public supportedCollaterals;

    /// @notice Mapping of supported collaterals for easy lookup
    mapping(address => bool) public isCollateralSupported;

    /// @notice Mapping of price feeds for supported collaterals
    mapping(address => address) public priceFeeds;

    /// @notice Address of ETH/USD price feed
    address public ethUsdPriceFeed; // TODO: can be stored in priceFeeds mapping

    /// @notice Mapping of user's collateral NFTs
    mapping(address => mapping(address => Collateral)) internal collateralNFTs;

    /// @notice Mapping of user's minted Gho / debt
    mapping(address => uint256) internal ghoMinted;

    /// @notice Reverts if used collateral is not supported
    modifier onlySupportedCollateral(address _collateral) {
        if (!isCollateralSupported[_collateral]) {
            assembly {
                mstore(0x00, 0x621a1355) // revert UnsupportedCollateral();
                revert(0x1c, 0x04)
            }
        }
        _;
    }

    /// @notice Reverts if user doesn't own the collateral token
    modifier onlyDepositedCollateralToken(address _collateral, uint256 _tokenId) {
        if (!collateralNFTs[msg.sender][_collateral].hasDepositedTokenId[_tokenId]) {
            assembly {
                mstore(0x00, 0x49e27cff) // revert InvalidOwner();
                revert(0x1c, 0x04)
            }
        }
        _;
    }

    /// @notice Initializes the contract
    /// @param _ghoToken Address of the Gho token
    /// @param _ghoTreasury Address of the treasury
    /// @param _supportedCollaterals List of supported collaterals
    /// @param _priceFeeds List of price feeds for supported collaterals
    /// @dev _supportedCollaterals and _priceFeeds should be in same order & length
    /// @param _ethUsdPriceFeed Address of ETH/USD price feed
    constructor(
        GhoToken _ghoToken,
        Gsm _gsm,
        address _ghoTreasury,
        address[] memory _supportedCollaterals,
        address[] memory _priceFeeds,
        address _ethUsdPriceFeed
    ) {
        assembly {
            /// @dev memposition of arrays will have length of array
            if iszero(eq(mload(_supportedCollaterals), mload(_priceFeeds))) {
                mstore(0x00, 0x2f2bb148) // revert InvalidCollateralsAndPriceFeeds();
                revert(0x1c, 0x04)
            }

            /// @dev these slots are not packed
            /// @dev clean upper bits of address
            sstore(ghoToken.slot, shr(96, shl(96, _ghoToken)))
            sstore(gsm.slot, shr(96, shl(96, _gsm)))
            sstore(ghoTreasury.slot, shr(96, shl(96, _ghoTreasury)))
            sstore(ethUsdPriceFeed.slot, shr(96, shl(96, _ethUsdPriceFeed)))
        }

        supportedCollaterals = _supportedCollaterals;
        for (uint256 i = 0; i < _supportedCollaterals.length; i++) {
            isCollateralSupported[_supportedCollaterals[i]] = true;
            priceFeeds[_supportedCollaterals[i]] = _priceFeeds[i];
        }
    }

    /// @notice Deposit collateral NFT token
    /// @dev Updates user's collateral NFT balances
    /// @param _collateral Address of the collateral
    /// @param _tokenId Token ID of the collateral
    function depositCollateral(address _collateral, uint256 _tokenId) external onlySupportedCollateral(_collateral) {
        collateralNFTs[msg.sender][_collateral].hasDepositedTokenId[_tokenId] = true;
        collateralNFTs[msg.sender][_collateral].tokensCount++;
        IERC721(_collateral).safeTransferFrom(msg.sender, address(this), _tokenId);
        assembly {
            log4(
                0x00,
                0x00, // no data
                0xf1c0dd7e9b98bbff859029005ef89b127af049cd18df1a8d79f0b7e019911e56, // CollateralDeposited(address,address,uint256)
                caller(), // user
                shr(96, shl(96, _collateral)), // collateral
                _tokenId // tokenId
            )
        }
    }

    /// @notice Mint Gho debt
    /// @dev Updates user's Gho debt. Reverts if user's health factor falls below 1 when taking new debt
    /// @param _amount Amount of Gho to mint
    function mintGho(uint256 _amount) external {
        ghoMinted[msg.sender] += _amount;
        if (healthFactor(msg.sender) < 1e18) {
            assembly {
                mstore(0x00, 0x034c7e5e) // revert InsufficientHealthFactor();
                revert(0x1c, 0x04)
            }
        }
        ghoToken.mint(msg.sender, _amount);
        assembly {
            // store _amount at free memory pointer
            let memPtr := mload(64)
            mstore(memPtr, _amount)
            log2(
                memPtr,
                32, // amount
                0x3e5bed99a1f2a825c552ad1f9e09f576e8621b9cf02e69a5f4bb88b7d457c4f3, // GhoMinted(address,uint256)
                caller() // user
            )
        }
    }

    /// @notice Redeem collateral NFT token
    /// @dev Updates user's collateral NFT balances. Reverts if user's health factor falls below 1 after redeem
    /// @param _collateral Address of the collateral
    /// @param _tokenId Token ID of the collateral
    function redeemCollateral(address _collateral, uint256 _tokenId)
        external
        onlySupportedCollateral(_collateral)
        onlyDepositedCollateralToken(_collateral, _tokenId)
    {
        collateralNFTs[msg.sender][_collateral].hasDepositedTokenId[_tokenId] = false;
        collateralNFTs[msg.sender][_collateral].tokensCount--;
        if (healthFactor(msg.sender) < 1e18) {
            assembly {
                mstore(0x00, 0x034c7e5e) // revert InsufficientHealthFactor();
                revert(0x1c, 0x04)
            }
        }
        IERC721(_collateral).safeTransferFrom(address(this), msg.sender, _tokenId);
        assembly {
            log4(
                0x00,
                0x00, // no data
                0xa5f9505801b85736b93411e5083d5a6003f3add45d82754efd49b4cca6b8e007, // CollateralRedeemed(address,address,uint256)
                caller(), // user
                shr(96, shl(96, _collateral)), // collateral
                _tokenId // tokenId
            )
        }
    }

    /// @notice Burn / repay Gho debt
    /// @dev Updates user's Gho debt. Collects fee from user
    /// @param _amount Amount of Gho to burn
    function burnGho(uint256 _amount) external {
        ghoMinted[msg.sender] -= _amount;
        uint256 _fee = (_amount * fee) / PERCENTAGE_FACTOR;
        ghoToken.transferFrom(msg.sender, address(this), _amount + _fee);
        ghoToken.burn(_amount);
        assembly {
            // store _amount at free memory pointer
            let memPtr := mload(64)
            mstore(memPtr, _amount)
            log2(
                memPtr,
                32,
                0x801d8e83524829eede7d24210e8d78d27c896377e5f3106fe65521e8e0278a29, // GhoBurned(address,uint256)
                caller() // user
            )
        }
    }

    function liquidate(address _user, address _collateral, uint256 _tokenId, uint256 _ghoAmount) external {
        uint256 currentHealthFactor = healthFactor(_user);
        if (currentHealthFactor >= 1e18) {
            assembly {
                mstore(0x00, 0x0d7b1848) // revert SufficientHealthFactor();
                revert(0x1c, 0x04)
            }
        }

        // TODO: refactor redeemCollateral() & burnGho() to avoid code duplication
        // redeem collateral from user
        collateralNFTs[_user][_collateral].hasDepositedTokenId[_tokenId] = false;
        collateralNFTs[_user][_collateral].tokensCount--;
        // transfer NFT to liquidator
        IERC721(_collateral).safeTransferFrom(address(this), msg.sender, _tokenId);

        // burn Gho equivalent to nft floor value from liquidator
        ghoMinted[_user] -= _ghoAmount; // reduce debt from user
        uint256 _fee = (_ghoAmount * fee) / PERCENTAGE_FACTOR;
        // burn Gho from liquidator
        ghoToken.transferFrom(msg.sender, address(this), _ghoAmount + _fee);
        ghoToken.burn(_ghoAmount);

        // check health factor improved
        uint256 newHealthFactor = healthFactor(_user);
        if (newHealthFactor <= currentHealthFactor) {
            assembly {
                mstore(0x00, 0x034c7e5e) // revert InsufficientHealthFactor();
                revert(0x1c, 0x04)
            }
        }

        assembly {
            // store _ghoAmount at free memory pointer
            let memPtr := mload(64)
            mstore(memPtr, _ghoAmount)
            log4(
                memPtr,
                32,
                0x1f0c6615429d1cdae0dfa233abf91d3b31cdbdd82c8081389832a61e1072f1ea, // Liquidated(address,address,uint256,uint256)
                shr(96, shl(96, _user)), // user
                shr(96, shl(96, _collateral)), // collateral
                _tokenId // tokenId
            )
        }
    }

    /// @inheritdoc IGhoFacilitator
    function distributeFeesToTreasury() external override {
        uint256 balance = ghoToken.balanceOf(address(this));
        ghoToken.transfer(ghoTreasury, balance);
        emit FeesDistributedToTreasury(ghoTreasury, address(ghoToken), balance);
    }

    /// @inheritdoc IGhoFacilitator
    function updateGhoTreasury(address newGhoTreasury) external override onlyOwner {
        address oldGhoTreasury = ghoTreasury;
        ghoTreasury = newGhoTreasury;
        emit GhoTreasuryUpdated(oldGhoTreasury, newGhoTreasury);
    }

    /// @inheritdoc IGhoFacilitator
    function getGhoTreasury() external view override returns (address) {
        return ghoTreasury;
    }

    /// @notice Calculates user's health factor
    /// @dev Health factor is the ratio of total collateral value scaled to liquidation threshold to total Gho value
    ///      health factor = (total collateral value in USD * liquidation threshold) / (total Gho value in USD)
    ///      Health Factor determines how close a position is to liquidation
    ///      All of user's collaterals and their floor prices are considered when calculating health factor
    /// @param user Address of the user
    function healthFactor(address user) public view returns (uint256) {
        uint256 totalGhoMinted = ghoMintedOf(user);
        if (totalGhoMinted == 0) return type(uint256).max;

        uint256 _totalCollateralValueInUSD = totalCollateralValueInUSD(user);
        // adding 1e18 to maintain precision after division with 1e18
        return (((_totalCollateralValueInUSD * LIQUIDATION_THRESHOLD) / PERCENTAGE_FACTOR) * 1e18) / totalGhoMinted;
    }

    /// @notice Calculates total collateral value in USD
    /// @dev All of user's collaterals and their floor prices are considered when calculating total collateral value
    /// @param user Address of the user
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

    /// @notice Calculates NFT floor value in USD
    /// @dev NFT floor price in ETH is retrieved from Chainlink price feed
    ///      ETH/USD price is retrieved from Chainlink price feed. It uses 8 decimals
    ///      We scale it to 18 decimals: 1e8 * 1e10 / 1e18 = 1e18
    ///      NFT floor value in USD = NFT floor price in ETH * ETH/USD price
    /// @param _nftAddress Address of the NFT
    function nftFloorValueInUsd(address _nftAddress) public view returns (uint256) {
        uint256 nftFloorPriceInEth = nftFloorPrice(_nftAddress);
        uint256 ethUsdPrice = ethUsd();
        // TODO: generalize precision
        return ((ethUsdPrice * 1e10) * nftFloorPriceInEth) / 1e18;
    }

    /// @notice Fetches NFT floor price from Chainlink price feed
    /// @dev NFT floor price is in ETH with 18 decimals
    /// @param _nftAddress Address of the NFT
    function nftFloorPrice(address _nftAddress) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeeds[_nftAddress]);
        // TODO: use decimals() instead of assuming 18
        (, int256 _nftFloorPrice,,,) = priceFeed.latestRoundData();
        return uint256(_nftFloorPrice);
    }

    /// @notice Fetches ETH/USD price from Chainlink price feed
    /// @dev ETH/USD price is in USD with 8 decimals
    function ethUsd() public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(ethUsdPriceFeed);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return uint256(price);
    }

    /// @notice Fetches number of tokens of a collection deposited by the user
    /// @param _user Address of the user
    /// @param _collateral Address of the collateral
    function collateralDepositedCount(address _user, address _collateral) public view returns (uint256) {
        return collateralNFTs[_user][_collateral].tokensCount;
    }

    /// @notice Checks if user has deposited the token ID of a collection
    /// @param _user Address of the user
    /// @param _collateral Address of the collateral
    /// @param _tokenId Token ID of the collateral
    function hasDepositedCollateralToken(address _user, address _collateral, uint256 _tokenId)
        public
        view
        returns (bool)
    {
        return collateralNFTs[_user][_collateral].hasDepositedTokenId[_tokenId];
    }

    /// @notice Fetches Gho minted / debt of a user
    /// @param _user Address of the user
    function ghoMintedOf(address _user) public view returns (uint256) {
        return ghoMinted[_user];
    }
}
