// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {NFGho} from "../src/NFGho.sol";
import {ERC721Mock} from "./mocks/ERC721Mock.sol";
import {DeployGHO} from "../script/DeployGHO.s.sol";
import {GhoToken} from "gho-core/src/contracts/gho/GhoToken.sol";
import {IGhoToken} from "gho-core/src/contracts/gho/interfaces/IGhoToken.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";

contract NFGhoTest is Test {
    event CollateralDeposited(address indexed user, address indexed collateral, uint256 indexed _tokenId);
    event CollateralRedeemed(address indexed user, address indexed collateral, uint256 indexed _tokenId);
    event GhoMinted(address indexed user, uint256 amount);
    event GhoBurned(address indexed user, uint256 amount);

    NFGho public nfgho;
    ERC721Mock public bayc = new ERC721Mock();
    GhoToken public ghoToken;
    MockV3Aggregator public mockV3AggregatorBayc = new MockV3Aggregator();
    MockV3Aggregator public mockV3AggregatorEthUsd = new MockV3Aggregator();

    address alice = makeAddr("alice");
    address liquidator = makeAddr("liquidator");
    address ghoGod = makeAddr("ghoGod"); // GHO facilitator to mint GHO for testing

    function setUp() public {
        DeployGHO deployer = new DeployGHO();
        (ghoToken) = deployer.run();

        address[] memory _supportedCollaterals = new address[](1);
        address[] memory _priceFeeds = new address[](1);
        _supportedCollaterals[0] = address(bayc);
        _priceFeeds[0] = address(mockV3AggregatorBayc);
        mockV3AggregatorBayc.setPrice(25 ether); // set floor price of 25 ETH
        mockV3AggregatorEthUsd.setPrice(2000e8); // set ETH/USD price of 2000 USD in 8 decimals

        nfgho = new NFGho(ghoToken, _supportedCollaterals, _priceFeeds, address(mockV3AggregatorEthUsd));

        vm.startPrank(alice);
        IGhoToken.Facilitator memory nfghoFacilitator = IGhoToken.Facilitator(100_000 ether, 0, "NFGho");
        IGhoToken.Facilitator memory ghoGodFacilitator = IGhoToken.Facilitator(100_000 ether, 0, "ghoGod");
        ghoToken.addFacilitator(address(nfgho), nfghoFacilitator);
        ghoToken.addFacilitator(ghoGod, ghoGodFacilitator);
        vm.stopPrank();

        bayc.mint(alice);
    }

    function test_initialState() public {
        assertEq(address(nfgho.ghoToken()), address(ghoToken));
        assertEq(nfgho.supportedCollaterals(0), address(bayc));
        assertTrue(nfgho.isCollateralSupported(address(bayc)));
        assertEq(nfgho.priceFeeds(address(bayc)), address(mockV3AggregatorBayc));
        assertEq(nfgho.ethUsdPriceFeed(), address(mockV3AggregatorEthUsd));
        assertEq(nfgho.LIQUIDATION_THRESHOLD(), 80);
        assertEq(nfgho.LIQUIDATION_PRECISION(), 100);

        (, int256 nftFloorPrice,,,) = mockV3AggregatorBayc.latestRoundData();
        assertEq(nftFloorPrice, 25 ether);
        (, int256 price,,,) = mockV3AggregatorEthUsd.latestRoundData();
        assertEq(price, 2000e8);
    }

    /* depositCollateral() */
    function test_depositCollateral() public {
        vm.startPrank(alice);

        // initial balances
        assertEq(nfgho.hasDepositedCollateralToken(alice, address(bayc), 1), false);
        assertEq(nfgho.collateralDepositedCount(alice, address(bayc)), 0);
        assertEq(bayc.balanceOf(alice), 1);
        assertEq(bayc.balanceOf(address(nfgho)), 0);

        // deposit collateral
        uint256 collateralTokenId = 1;
        bayc.approve(address(nfgho), collateralTokenId);
        vm.expectEmit(true, true, true, true);
        emit CollateralDeposited(alice, address(bayc), collateralTokenId);
        nfgho.depositCollateral(address(bayc), collateralTokenId);

        // final balances
        assertEq(nfgho.hasDepositedCollateralToken(alice, address(bayc), 1), true);
        assertEq(nfgho.collateralDepositedCount(alice, address(bayc)), 1);
        assertEq(bayc.balanceOf(alice), 0);
        assertEq(bayc.balanceOf(address(nfgho)), 1);

        vm.stopPrank();
    }

    function test_depositCollateralRevertsIfUnsupported() public {
        ERC721Mock unsupported = new ERC721Mock();
        uint256 collateralTokenId = 1;
        vm.expectRevert(NFGho.UnsupportedCollateral.selector);
        nfgho.depositCollateral(address(unsupported), collateralTokenId);
    }

    /* mintGho() */
    function test_mintGho() public {
        vm.startPrank(alice);

        // initial balances
        assertEq(nfgho.ghoMintedOf(alice), 0);
        assertEq(ghoToken.balanceOf(alice), 0);

        // deposit collateral
        uint256 collateralTokenId = 1;
        bayc.approve(address(nfgho), collateralTokenId);
        nfgho.depositCollateral(address(bayc), collateralTokenId);

        // mint gho
        uint256 ghoAmount = 1 ether;
        vm.expectEmit(true, true, true, true);
        emit GhoMinted(alice, ghoAmount);
        nfgho.mintGho(ghoAmount);

        // final balances
        assertEq(nfgho.ghoMintedOf(alice), ghoAmount);
        assertEq(ghoToken.balanceOf(alice), ghoAmount);

        vm.stopPrank();
    }

    function test_mintGhoRevertsIfInsufficientHealthFactor() public {
        vm.startPrank(alice);

        // deposit collateral
        uint256 collateralTokenId = 1;
        bayc.approve(address(nfgho), collateralTokenId);
        nfgho.depositCollateral(address(bayc), collateralTokenId);
        // mint 80% of collateral value in GHO: 50,000 USD * 80% = 40,000 USD
        nfgho.mintGho(40_000e18);
        assertEq(nfgho.healthFactor(alice), 1e18);

        // mint 1 GHO
        uint256 ghoAmount = 1 ether;
        vm.expectRevert(NFGho.InsufficientHealthFactor.selector);
        nfgho.mintGho(ghoAmount);

        vm.stopPrank();
    }

    /* nftFloorPrice() */
    function test_nftFloorPrice() public {
        assertEq(nfgho.nftFloorPrice(address(bayc)), 25 ether);

        // update floor price
        mockV3AggregatorBayc.setPrice(30 ether);
        assertEq(nfgho.nftFloorPrice(address(bayc)), 30 ether);
    }

    /* ethUsd() */
    function test_ethUsd() public {
        assertEq(nfgho.ethUsd(), 2000e8);

        // update ETH/USD price
        mockV3AggregatorEthUsd.setPrice(3000e8);
        assertEq(nfgho.ethUsd(), 3000e8);
    }

    /* nftFloorValueInUsd() */
    function test_nftFloorValueInUsd() public {
        assertEq(nfgho.nftFloorValueInUsd(address(bayc)), 50_000e18); // 25 ETH * 2000 USD / ETH = 50,000 USD

        // update floor price
        mockV3AggregatorBayc.setPrice(30 ether);
        assertEq(nfgho.nftFloorValueInUsd(address(bayc)), 60_000e18); // 30 ETH * 2000 USD / ETH = 60,000 USD

        // update ETH/USD price
        mockV3AggregatorEthUsd.setPrice(3000e8);
        assertEq(nfgho.nftFloorValueInUsd(address(bayc)), 90_000e18); // 30 ETH * 3000 USD / ETH = 90,000 USD
    }

    /* totalCollateralValueInUSD() */
    function test_totalCollateralValueInUSD() public {
        vm.startPrank(alice);

        // initial balances
        assertEq(nfgho.totalCollateralValueInUSD(alice), 0);

        // deposit collateral
        uint256 collateralTokenId = 1;
        bayc.approve(address(nfgho), collateralTokenId);
        nfgho.depositCollateral(address(bayc), collateralTokenId);

        // final balances
        assertEq(nfgho.totalCollateralValueInUSD(alice), 50_000e18); // 25 ETH * 2000 USD / ETH = 50,000 USD

        // mint and deposit one bayc token
        bayc.mint(alice);
        collateralTokenId = 2;
        bayc.approve(address(nfgho), collateralTokenId);
        nfgho.depositCollateral(address(bayc), collateralTokenId);

        assertEq(nfgho.totalCollateralValueInUSD(alice), 100_000e18); // 50,000 USD + 50,000 USD

        vm.stopPrank();
    }

    /* healthFactor() */
    function test_healthFactor() public {
        vm.startPrank(alice);

        // deposit collateral
        uint256 collateralTokenId = 1;
        bayc.approve(address(nfgho), collateralTokenId);
        nfgho.depositCollateral(address(bayc), collateralTokenId);
        // mint 80% of collateral value in GHO: 50,000 USD * 80% = 40,000 USD
        nfgho.mintGho(40_000e18);

        // (((totalCollateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION) * 1e18) / totalGhoMinted;
        // (((50_000 * 80) / 100) * 1e18) / 40_000 = 1e18
        assertEq(nfgho.healthFactor(alice), 1e18);

        // deposit one more bayc
        bayc.mint(alice);
        collateralTokenId = 2;
        bayc.approve(address(nfgho), collateralTokenId);
        nfgho.depositCollateral(address(bayc), collateralTokenId);
        // mint 20_000 USD worth of GHO
        nfgho.mintGho(20_000e18);

        // (((totalCollateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION) * 1e18) / totalGhoMinted;
        // (((100_000 * 80) / 100) * 1e18) / 60_000 = 1.333333333333333333e18
        assertEq(nfgho.healthFactor(alice), 1.333333333333333333e18);

        vm.stopPrank();
    }

    /* redeemCollateral() */
    function test_redeemCollateral() public {
        vm.startPrank(alice);

        // deposit collateral
        uint256 collateralTokenId = 1;
        bayc.approve(address(nfgho), collateralTokenId);
        nfgho.depositCollateral(address(bayc), collateralTokenId);

        // redeem collateral
        vm.expectEmit(true, true, true, true);
        emit CollateralRedeemed(alice, address(bayc), collateralTokenId);
        nfgho.redeemCollateral(address(bayc), collateralTokenId);

        // final balances
        assertEq(nfgho.hasDepositedCollateralToken(alice, address(bayc), 1), false);
        assertEq(nfgho.collateralDepositedCount(alice, address(bayc)), 0);
        assertEq(bayc.balanceOf(alice), 1);
        assertEq(bayc.balanceOf(address(nfgho)), 0);

        vm.stopPrank();
    }

    function test_redeemCollateralRevertsIfUnsupported() public {
        ERC721Mock unsupported = new ERC721Mock();
        uint256 collateralTokenId = 1;
        vm.expectRevert(NFGho.UnsupportedCollateral.selector);
        nfgho.redeemCollateral(address(unsupported), collateralTokenId);
    }

    function test_redeemCollateralRevertsIfNotDeposited() public {
        uint256 collateralTokenId = 1;
        vm.expectRevert(NFGho.InvalidOwner.selector);
        nfgho.redeemCollateral(address(bayc), collateralTokenId);
    }

    function test_redeemCollateralRevertsIfInsufficientHealthFactor() public {
        vm.startPrank(alice);

        // deposit collateral
        uint256 collateralTokenId = 1;
        bayc.approve(address(nfgho), collateralTokenId);
        nfgho.depositCollateral(address(bayc), collateralTokenId);
        // mint 80% of collateral value in GHO: 50,000 USD * 80% = 40,000 USD
        nfgho.mintGho(40_000e18);
        assertEq(nfgho.healthFactor(alice), 1e18);

        // redeem collateral
        vm.expectRevert(NFGho.InsufficientHealthFactor.selector);
        nfgho.redeemCollateral(address(bayc), collateralTokenId);

        vm.stopPrank();
    }

    /* burnGho() */
    function test_burnGho() public {
        vm.startPrank(alice);

        // deposit collateral
        uint256 collateralTokenId = 1;
        bayc.approve(address(nfgho), collateralTokenId);
        nfgho.depositCollateral(address(bayc), collateralTokenId);
        // mint 80% of collateral value in GHO: 50,000 USD * 80% = 40,000 USD
        nfgho.mintGho(40_000e18);

        // burn GHO
        uint256 ghoAmount = 20_000 ether;
        ghoToken.approve(address(nfgho), ghoAmount);
        vm.expectEmit(true, true, true, true);
        emit GhoBurned(alice, ghoAmount);
        nfgho.burnGho(ghoAmount);

        // final balances
        assertEq(nfgho.ghoMintedOf(alice), 20_000e18);
        assertEq(ghoToken.balanceOf(alice), 20_000e18);

        // health factor
        // (((totalCollateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION) * 1e18) / totalGhoMinted;
        // (((50_000 * 80) / 100) * 1e18) / 20_000 = 2e18
        assertEq(nfgho.healthFactor(alice), 2e18);

        vm.stopPrank();
    }

    /* liquidate() */
    function test_liquidate() public {
        vm.startPrank(alice);

        // deposit collateral
        uint256 collateralTokenId = 1;
        bayc.approve(address(nfgho), collateralTokenId);
        nfgho.depositCollateral(address(bayc), collateralTokenId);
        assertEq(nfgho.collateralDepositedCount(alice, address(bayc)), 1);
        // mint 80% of collateral value in GHO: 50,000 USD * 80% = 40,000 USD
        nfgho.mintGho(40_000e18);
        vm.stopPrank();

        // health factor = 50_000 * 80% / 40_000 = 1
        assertEq(nfgho.healthFactor(alice), 1e18);

        // decrease BAYC floor price to 22.5 ETH = 45,000 USD
        mockV3AggregatorBayc.setPrice(22.5 ether);

        // health factor = 45_000 * 80% / 40_000 = 0.9e18
        uint256 newHealthFactor = nfgho.healthFactor(alice);
        assertEq(newHealthFactor, 0.9e18);

        // liquidate
        // repay 40_000, take 45_000 collateral
        // debt = 0, collateral = 0; hf = max
        uint256 liquidateAmount = 40_000e18;
        // mint 40_000 GHO for liquidator
        vm.prank(ghoGod);
        ghoToken.mint(liquidator, liquidateAmount);
        vm.stopPrank();
        vm.startPrank(liquidator);
        ghoToken.approve(address(nfgho), liquidateAmount);
        nfgho.liquidate(alice, address(bayc), collateralTokenId, liquidateAmount);
        vm.stopPrank();

        // final balances
        newHealthFactor = nfgho.healthFactor(alice);
        assertEq(newHealthFactor, type(uint256).max);
        assertEq(nfgho.ghoMintedOf(alice), 0);
        assertEq(ghoToken.balanceOf(alice), 40_000e18);
        assertEq(nfgho.hasDepositedCollateralToken(alice, address(bayc), 1), false);
        assertEq(nfgho.collateralDepositedCount(alice, address(bayc)), 0);
        assertEq(bayc.balanceOf(alice), 0);
        assertEq(bayc.balanceOf(address(nfgho)), 0);
    }

    function test_liquidateRevertsIfInsufficientHealthFactor() public {
        vm.startPrank(alice);

        // deposit collateral
        uint256 collateralTokenId = 1;
        bayc.approve(address(nfgho), collateralTokenId);
        nfgho.depositCollateral(address(bayc), collateralTokenId);
        assertEq(nfgho.collateralDepositedCount(alice, address(bayc)), 1);
        // mint 80% of collateral value in GHO: 50,000 USD * 80% = 40,000 USD
        nfgho.mintGho(40_000e18);
        vm.stopPrank();

        // health factor = 50_000 * 80% / 40_000 = 1
        assertEq(nfgho.healthFactor(alice), 1e18);

        // decrease BAYC floor price to 22.5 ETH = 45,000 USD
        mockV3AggregatorBayc.setPrice(22.5 ether);

        // health factor = 45_000 * 80% / 40_000 = 0.9e18
        uint256 newHealthFactor = nfgho.healthFactor(alice);
        assertEq(newHealthFactor, 0.9e18);

        // liquidate
        // repay 39_000, take 45_000 collateral
        // debt = 40_000 - 39_000 = 1000, collateral = 0; hf = 0
        uint256 liquidateAmount = 39_000e18;
        // mint 39_000 GHO for liquidator
        vm.prank(ghoGod);
        ghoToken.mint(liquidator, liquidateAmount);
        vm.stopPrank();
        vm.startPrank(liquidator);
        ghoToken.approve(address(nfgho), liquidateAmount);
        vm.expectRevert(NFGho.InsufficientHealthFactor.selector);
        nfgho.liquidate(alice, address(bayc), collateralTokenId, liquidateAmount);
        vm.stopPrank();
    }

    function test_liquidateRevertsIfInsufficientHealthFactor_multipleCollaterals() public {
        vm.startPrank(alice);

        // deposit collateral 1
        uint256 collateralTokenId = 1;
        bayc.approve(address(nfgho), collateralTokenId);
        nfgho.depositCollateral(address(bayc), collateralTokenId);
        assertEq(nfgho.collateralDepositedCount(alice, address(bayc)), 1);
        // mint 80% of collateral value in GHO: 50,000 USD * 80% = 40,000 USD
        nfgho.mintGho(40_000e18);

        // deposit collateral 2
        bayc.mint(alice);
        collateralTokenId = 2;
        bayc.approve(address(nfgho), collateralTokenId);
        nfgho.depositCollateral(address(bayc), collateralTokenId);
        assertEq(nfgho.collateralDepositedCount(alice, address(bayc)), 2);
        // mint 80% of collateral value in GHO: 100,000 USD * 80% = 80,000 USD
        nfgho.mintGho(40_000e18);
        vm.stopPrank();

        // health factor = 100_000 * 80% / 80_000 = 1
        assertEq(nfgho.healthFactor(alice), 1e18);

        // decrease BAYC floor price to 22.5 ETH = 45,000 USD
        mockV3AggregatorBayc.setPrice(22.5 ether);

        // health factor = 90,000 * 80% / 80_000 = 0.9e18
        uint256 newHealthFactor = nfgho.healthFactor(alice);
        assertEq(newHealthFactor, 0.9e18);

        // liquidate
        // repay 44_000, take 45_000 collateral
        // debt = 80_000 - 44_000 = 36_000, collateral = 90_000 - 45_000 = 45_000; hf = 45_000 * 80% / 36_000 = 1
        uint256 liquidateAmount = 44_000e18;
        // mint 44_000 GHO for liquidator
        vm.prank(ghoGod);
        ghoToken.mint(liquidator, liquidateAmount);
        vm.stopPrank();
        vm.startPrank(liquidator);
        ghoToken.approve(address(nfgho), liquidateAmount);
        nfgho.liquidate(alice, address(bayc), 1, liquidateAmount);
        vm.stopPrank();

        newHealthFactor = nfgho.healthFactor(alice);
        assertEq(newHealthFactor, 1e18);
        assertEq(nfgho.ghoMintedOf(alice), 36_000e18);
        assertEq(ghoToken.balanceOf(alice), 80_000e18);
        assertEq(nfgho.hasDepositedCollateralToken(alice, address(bayc), 1), false);
        assertEq(nfgho.hasDepositedCollateralToken(alice, address(bayc), 2), true);
        assertEq(nfgho.collateralDepositedCount(alice, address(bayc)), 1);
        assertEq(bayc.balanceOf(alice), 0);
        assertEq(bayc.balanceOf(address(nfgho)), 1);

        // decrease BAYC floor price to 20 ETH = 40,000 USD
        mockV3AggregatorBayc.setPrice(20 ether);

        // health factor = 40,000 * 80% / 36_000 = 0.888888888888888888e18
        newHealthFactor = nfgho.healthFactor(alice);
        assertEq(newHealthFactor, 0.888888888888888888e18);

        // liquidate next token
        // repay 36_000, take 45_000 collateral
        // debt = 0, collateral = 0; hf = max
        liquidateAmount = 36_000e18;
        // mint 36_000 GHO for liquidator
        vm.prank(ghoGod);
        ghoToken.mint(liquidator, liquidateAmount);
        vm.stopPrank();
        vm.startPrank(liquidator);
        ghoToken.approve(address(nfgho), liquidateAmount);
        nfgho.liquidate(alice, address(bayc), 2, liquidateAmount);
        vm.stopPrank();

        newHealthFactor = nfgho.healthFactor(alice);
        assertEq(newHealthFactor, type(uint256).max);
        assertEq(nfgho.ghoMintedOf(alice), 0);
        assertEq(ghoToken.balanceOf(alice), 80_000e18);
        assertEq(nfgho.hasDepositedCollateralToken(alice, address(bayc), 1), false);
        assertEq(nfgho.hasDepositedCollateralToken(alice, address(bayc), 2), false);
        assertEq(nfgho.collateralDepositedCount(alice, address(bayc)), 0);
        assertEq(bayc.balanceOf(alice), 0);
        assertEq(bayc.balanceOf(address(nfgho)), 0);
    }
}
