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
    event GhoMinted(address indexed user, uint256 amount);

    NFGho public nfgho;
    ERC721Mock public bayc = new ERC721Mock();
    GhoToken public ghoToken;
    MockV3Aggregator public mockV3AggregatorBayc = new MockV3Aggregator();
    MockV3Aggregator public mockV3AggregatorEthUsd = new MockV3Aggregator();

    address alice = makeAddr("alice");

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
        ghoToken.addFacilitator(address(nfgho), nfghoFacilitator);
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
}
