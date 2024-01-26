// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {NFGho} from "../src/NFGho.sol";
import {ERC721Mock} from "./mocks/ERC721Mock.sol";
import {DeployGHO} from "../script/DeployGHO.s.sol";
import {GhoToken} from "gho-core/src/contracts/gho/GhoToken.sol";
import {IGhoToken} from "gho-core/src/contracts/gho/interfaces/IGhoToken.sol";

contract NFGhoTest is Test {
    event CollateralDeposited(address indexed user, address indexed collateral, uint256 indexed _tokenId);
    event GhoMinted(address indexed user, uint256 amount);

    NFGho public nfgho;
    ERC721Mock public bayc = new ERC721Mock();
    GhoToken public ghoToken;

    address alice = makeAddr("alice");
    address mockV3Aggregator = makeAddr("mockV3Aggregator");

    function setUp() public {
        DeployGHO deployer = new DeployGHO();
        (ghoToken) = deployer.run();

        address[] memory _supportedCollaterals = new address[](1);
        address[] memory _priceFeeds = new address[](1);
        _supportedCollaterals[0] = address(bayc);
        _priceFeeds[0] = mockV3Aggregator;

        nfgho = new NFGho(ghoToken, _supportedCollaterals, _priceFeeds);

        vm.startPrank(alice);
        IGhoToken.Facilitator memory nfghoFacilitator = IGhoToken.Facilitator(2 ether, 0, "NFGho");
        ghoToken.addFacilitator(address(nfgho), nfghoFacilitator);
        vm.stopPrank();

        bayc.mint(alice);
    }

    function test_initialState() public {
        assertEq(address(nfgho.ghoToken()), address(ghoToken));
        assertEq(nfgho.supportedCollaterals(0), address(bayc));
        assertTrue(nfgho.isCollateralSupported(address(bayc)));
        assertEq(nfgho.priceFeeds(address(bayc)), mockV3Aggregator);
    }

    /* depositCollateral() */
    function test_depositCollateral() public {
        vm.startPrank(alice);

        // initial balances
        assertEq(nfgho.collateralTokenIdOf(alice, address(bayc)), 0);
        assertEq(bayc.balanceOf(alice), 1);
        assertEq(bayc.balanceOf(address(nfgho)), 0);

        // deposit collateral
        uint256 collateralTokenId = 1;
        bayc.approve(address(nfgho), collateralTokenId);
        vm.expectEmit(true, true, true, true);
        emit CollateralDeposited(alice, address(bayc), collateralTokenId);
        nfgho.depositCollateral(address(bayc), collateralTokenId);

        // final balances
        assertEq(nfgho.collateralTokenIdOf(alice, address(bayc)), collateralTokenId);
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
}
