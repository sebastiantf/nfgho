// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {NFGho} from "../src/NFGho.sol";
import {ERC721Mock} from "./mocks/ERC721Mock.sol";
import {DeployGHO} from "../script/DeployGHO.s.sol";
import {GhoToken} from "gho-core/src/contracts/gho/GhoToken.sol";
import {Gsm} from "gho-core/src/contracts/facilitators/gsm/Gsm.sol";
import {TestnetERC20} from "@aave/periphery-v3/contracts/mocks/testnet-helpers/TestnetERC20.sol";
import {IGhoToken} from "gho-core/src/contracts/gho/interfaces/IGhoToken.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";
import {Constants} from "gho-core/src/test/helpers/Constants.sol";
import {ATokenMock} from "./mocks/ATokenMock.sol";
import {IPool} from "@aave/core-v3/contracts/protocol/pool/Pool.sol";

contract NFGhoTest is Test, Constants {
    event CollateralDeposited(address indexed user, address indexed collateral, uint256 indexed _tokenId);
    event CollateralRedeemed(address indexed user, address indexed collateral, uint256 indexed _tokenId);
    event GhoMinted(address indexed user, uint256 amount);
    event GhoMintedSwappedToUsdc(address indexed user, uint256 ghoAmount, uint256 usdcAmount);
    event GhoMintedSwappedToUsdcSupplied(address indexed user, uint256 ghoAmount, uint256 usdcAmount);
    event GhoBurned(address indexed user, uint256 amount);
    event Liquidated(address indexed user, address indexed collateral, uint256 indexed tokenId, uint256 ghoBurned);

    NFGho public nfgho;
    ERC721Mock public bayc = new ERC721Mock();
    GhoToken public ghoToken;
    Gsm public gsm;
    TestnetERC20 public usdc;
    MockV3Aggregator public mockV3AggregatorBayc = new MockV3Aggregator();
    MockV3Aggregator public mockV3AggregatorEthUsd = new MockV3Aggregator();
    IPool public poolMock;
    ATokenMock public usdcATokenMock;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address liquidator = makeAddr("liquidator");
    address ghoGod = makeAddr("ghoGod"); // GHO facilitator to mint GHO for testing
    address ghoTreasury = makeAddr("ghoTreasury");

    function setUp() public {
        DeployGHO deployer = new DeployGHO();
        (ghoToken, gsm, usdc, poolMock, usdcATokenMock) = deployer.run();

        address[] memory _supportedCollaterals = new address[](1);
        address[] memory _priceFeeds = new address[](1);
        _supportedCollaterals[0] = address(bayc);
        _priceFeeds[0] = address(mockV3AggregatorBayc);
        mockV3AggregatorBayc.setPrice(25 ether); // set floor price of 25 ETH
        mockV3AggregatorEthUsd.setPrice(2000e8); // set ETH/USD price of 2000 USD in 8 decimals

        nfgho = new NFGho(
            ghoToken, gsm, poolMock, ghoTreasury, _supportedCollaterals, _priceFeeds, address(mockV3AggregatorEthUsd)
        );

        vm.startPrank(alice);
        ghoToken.addFacilitator(address(nfgho), "NFGho", 100_000 ether);
        ghoToken.addFacilitator(ghoGod, "ghoGod", 100_000 ether);
        vm.stopPrank();

        bayc.mint(alice);
    }

    function test_initialState() public {
        assertEq(address(nfgho.ghoToken()), address(ghoToken));
        assertEq(address(nfgho.gsmUsdc()), address(gsm));
        assertEq(address(nfgho.aavePool()), address(poolMock));
        assertEq(nfgho.supportedCollaterals(0), address(bayc));
        assertTrue(nfgho.isCollateralSupported(address(bayc)));
        assertEq(nfgho.priceFeeds(address(bayc)), address(mockV3AggregatorBayc));
        assertEq(nfgho.ethUsdPriceFeed(), address(mockV3AggregatorEthUsd));
        assertEq(nfgho.LIQUIDATION_THRESHOLD(), 0.8e4);
        assertEq(nfgho.PERCENTAGE_FACTOR(), 1e4);
        assertEq(nfgho.ghoTreasury(), ghoTreasury);
        assertEq(nfgho.owner(), address(this));
        assertEq(nfgho.fee(), 0.0001e4);

        (, int256 nftFloorPrice,,,) = mockV3AggregatorBayc.latestRoundData();
        assertEq(nftFloorPrice, 25 ether);
        (, int256 price,,,) = mockV3AggregatorEthUsd.latestRoundData();
        assertEq(price, 2000e8);
    }

    function test_constructorRevertsIfCollateralAndPriceFeedLengthMismatch() public {
        address[] memory _supportedCollaterals = new address[](2);
        address[] memory _priceFeeds = new address[](1);
        _supportedCollaterals[0] = address(bayc);
        _supportedCollaterals[1] = address(bayc);
        _priceFeeds[0] = address(mockV3AggregatorBayc);
        vm.expectRevert(NFGho.InvalidCollateralsAndPriceFeeds.selector);
        new NFGho(
            ghoToken, gsm, poolMock, ghoTreasury, _supportedCollaterals, _priceFeeds, address(mockV3AggregatorEthUsd)
        );
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

    /* mintGhoSwapUsdc */
    function test_mintGhoSwapUsdc() public {
        vm.startPrank(alice);

        // initial balances
        assertEq(nfgho.ghoMintedOf(alice), 0);
        assertEq(ghoToken.balanceOf(alice), 0);

        // deposit collateral
        uint256 collateralTokenId = 1;
        bayc.approve(address(nfgho), collateralTokenId);
        nfgho.depositCollateral(address(bayc), collateralTokenId);

        vm.stopPrank();

        // Supply assets to the GSM first
        vm.prank(FAUCET);
        usdc.mint(bob, 200e6);
        vm.startPrank(bob);
        usdc.approve(address(gsm), 200e6);
        gsm.sellAsset(200e6, bob);
        vm.stopPrank();

        // mint gho and get USDC
        vm.startPrank(alice);
        uint256 ghoAmount = 100e18;
        vm.expectEmit(true, true, true, true);
        emit GhoMintedSwappedToUsdc(alice, ghoAmount, 100e6);
        nfgho.mintGhoSwapUsdc(ghoAmount);

        // final balances
        assertEq(nfgho.ghoMintedOf(alice), ghoAmount);
        assertEq(ghoToken.balanceOf(alice), 0);
        assertEq(ghoToken.balanceOf(address(nfgho)), 0);
        assertEq(usdc.balanceOf(alice), 100e6);
        assertEq(usdc.balanceOf(address(nfgho)), 0);

        vm.stopPrank();
    }

    /* mintGhoSwapUsdcSupply() */
    function test_mintGhoSwapUsdcSupply() public {
        vm.startPrank(alice);

        // initial balances
        assertEq(nfgho.ghoMintedOf(alice), 0);
        assertEq(ghoToken.balanceOf(alice), 0);

        // deposit collateral
        uint256 collateralTokenId = 1;
        bayc.approve(address(nfgho), collateralTokenId);
        nfgho.depositCollateral(address(bayc), collateralTokenId);

        vm.stopPrank();

        // Supply assets to the GSM first
        vm.prank(FAUCET);
        usdc.mint(bob, 200e6);
        vm.startPrank(bob);
        usdc.approve(address(gsm), 200e6);
        gsm.sellAsset(200e6, bob);
        vm.stopPrank();

        // mint gho, get USDC, supply to Aave
        vm.startPrank(alice);
        uint256 ghoAmount = 100e18;
        vm.expectEmit(true, true, true, true);
        emit GhoMintedSwappedToUsdcSupplied(alice, ghoAmount, 100e6);
        nfgho.mintGhoSwapUsdcSupply(ghoAmount);

        // final balances
        assertEq(nfgho.ghoMintedOf(alice), ghoAmount);
        assertEq(ghoToken.balanceOf(alice), 0);
        assertEq(ghoToken.balanceOf(address(nfgho)), 0);
        assertEq(usdc.balanceOf(alice), 0);
        assertEq(usdc.balanceOf(address(nfgho)), 0);
        assertEq(usdcATokenMock.balanceOf(address(alice)), 100e6);

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
        uint256 _fee = (ghoAmount * nfgho.fee()) / nfgho.PERCENTAGE_FACTOR(); // 20,000 * 0.01% = 2
        assertEq(_fee, 2e18);
        uint256 burnAmountWithFee = ghoAmount + _fee; // 20,000 + 2 = 20,002
        assertEq(burnAmountWithFee, 20_002e18);
        ghoToken.approve(address(nfgho), burnAmountWithFee);
        vm.expectEmit(true, true, true, true);
        emit GhoBurned(alice, ghoAmount);
        nfgho.burnGho(ghoAmount);

        // final balances
        assertEq(nfgho.ghoMintedOf(alice), 20_000e18);
        assertEq(ghoToken.balanceOf(alice), 20_000e18 - _fee);
        assertEq(ghoToken.balanceOf(address(nfgho)), 2e18);

        // distribute fee to treasury
        assertEq(ghoToken.balanceOf(ghoTreasury), 0);
        nfgho.distributeFeesToTreasury();
        assertEq(ghoToken.balanceOf(ghoTreasury), 2e18);
        assertEq(ghoToken.balanceOf(address(nfgho)), 0);

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
        uint256 _fee = (liquidateAmount * nfgho.fee()) / nfgho.PERCENTAGE_FACTOR(); // 40,000 * 0.01% = 4
        assertEq(_fee, 4e18);
        uint256 burnAmountWithFee = liquidateAmount + _fee; // 40,000 + 4 = 40,004
        assertEq(burnAmountWithFee, 40_004e18);
        // mint 40_000 + fee GHO for liquidator
        vm.prank(ghoGod);
        ghoToken.mint(liquidator, burnAmountWithFee);
        vm.stopPrank();
        vm.startPrank(liquidator);
        ghoToken.approve(address(nfgho), burnAmountWithFee);
        vm.expectEmit(true, true, true, true);
        emit Liquidated(alice, address(bayc), collateralTokenId, liquidateAmount);
        nfgho.liquidate(alice, address(bayc), collateralTokenId, liquidateAmount);
        vm.stopPrank();

        // alice: 50000 USD collateral, 40000 USD debt, 40000 GHO balance -> 0 collateral, 0 debt, 40000 GHO balance
        // loss: 45000 - 40000 = 5000 USD
        // liquidator: 0 USD collateral, 0 USD debt, 40004 GHO balance -> 45000 collateral, 0 debt, 0 GHO balance
        // profit: 45000 - 40004 = 4,996 USD

        // final balances
        newHealthFactor = nfgho.healthFactor(alice);
        assertEq(newHealthFactor, type(uint256).max);
        assertEq(nfgho.ghoMintedOf(alice), 0);
        assertEq(ghoToken.balanceOf(alice), 40_000e18);
        assertEq(ghoToken.balanceOf(address(nfgho)), 4e18);
        assertEq(nfgho.hasDepositedCollateralToken(alice, address(bayc), 1), false);
        assertEq(nfgho.collateralDepositedCount(alice, address(bayc)), 0);
        assertEq(bayc.balanceOf(alice), 0);
        assertEq(bayc.balanceOf(address(nfgho)), 0);

        // distribute fee to treasury
        assertEq(ghoToken.balanceOf(ghoTreasury), 0);
        nfgho.distributeFeesToTreasury();
        assertEq(ghoToken.balanceOf(ghoTreasury), 4e18);
        assertEq(ghoToken.balanceOf(address(nfgho)), 0);
    }

    function test_liquidateRevertsIfSufficientHealthFactor() public {
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

        vm.prank(ghoGod);
        ghoToken.mint(liquidator, 1 ether);
        vm.stopPrank();
        vm.startPrank(liquidator);
        ghoToken.approve(address(nfgho), 1 ether);
        vm.expectRevert(NFGho.SufficientHealthFactor.selector);
        nfgho.liquidate(alice, address(bayc), collateralTokenId, 1 ether);
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
        uint256 _fee = (liquidateAmount * nfgho.fee()) / nfgho.PERCENTAGE_FACTOR(); // 39,000 * 0.01% = 3.9
        assertEq(_fee, 3.9e18);
        uint256 burnAmountWithFee = liquidateAmount + _fee; // 39,000 + 3.9 = 39,003.9
        assertEq(burnAmountWithFee, 39_003.9e18);
        // mint 39_000 GHO for liquidator
        vm.prank(ghoGod);
        ghoToken.mint(liquidator, burnAmountWithFee);
        vm.stopPrank();
        vm.startPrank(liquidator);
        ghoToken.approve(address(nfgho), burnAmountWithFee);
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
        // mint 80% of collateral value in GHO: 100,000 USD * 80% = 80,000 USD - 40,000 = 40,000
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
        uint256 _fee = (liquidateAmount * nfgho.fee()) / nfgho.PERCENTAGE_FACTOR(); // 44,000 * 0.01% = 4.4
        assertEq(_fee, 4.4e18);
        uint256 burnAmountWithFee = liquidateAmount + _fee; // 44,000 + 4.4 = 44,004.4
        assertEq(burnAmountWithFee, 44_004.4e18);
        // mint 44_000 GHO for liquidator
        vm.prank(ghoGod);
        ghoToken.mint(liquidator, burnAmountWithFee);
        vm.stopPrank();
        vm.startPrank(liquidator);
        ghoToken.approve(address(nfgho), burnAmountWithFee);
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
        // repay 36_000, take 40_000 collateral
        // debt = 0, collateral = 0; hf = max
        liquidateAmount = 36_000e18;
        _fee = (liquidateAmount * nfgho.fee()) / nfgho.PERCENTAGE_FACTOR(); // 46,000 * 0.01% = 3.6
        assertEq(_fee, 3.6e18);
        burnAmountWithFee = liquidateAmount + _fee; // 36,000 + 3.6 = 36,003.6
        assertEq(burnAmountWithFee, 36_003.6e18);
        // mint 36_000 GHO for liquidator
        vm.prank(ghoGod);
        ghoToken.mint(liquidator, burnAmountWithFee);
        vm.stopPrank();
        vm.startPrank(liquidator);
        ghoToken.approve(address(nfgho), burnAmountWithFee);
        nfgho.liquidate(alice, address(bayc), 2, liquidateAmount);
        vm.stopPrank();

        // alice: 100,000 USD collateral, 40000 USD debt, 40000 GHO balance -> 0 collateral, 0 debt, 40000 GHO balance
        // loss: (40000 + 45000) - 80000 = 5,000 USD
        // liquidator: 0 USD collateral, 0 USD debt, 44,004.4 + 36,003.6 = 80,008 GHO balance -> 45000+40000 = 85,000 collateral, 0 debt, 0 GHO balance
        // profit: 85,000 - 80,008 = 4,992 USD

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
