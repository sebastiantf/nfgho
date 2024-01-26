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

    NFGho public nfgho;
    ERC721Mock public bayc = new ERC721Mock();
    GhoToken public ghoToken;

    address alice = makeAddr("alice");

    function setUp() public {
        DeployGHO deployer = new DeployGHO();
        (ghoToken) = deployer.run();
        nfgho = new NFGho(ghoToken);

        vm.startPrank(alice);
        IGhoToken.Facilitator memory nfghoFacilitator = IGhoToken.Facilitator(2 ether, 0, "NFGho");
        ghoToken.addFacilitator(address(nfgho), nfghoFacilitator);
        vm.stopPrank();

        bayc.mint(alice);
    }

    function test_initialState() public {
        assertEq(address(nfgho.ghoToken()), address(ghoToken));
    }

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
}
