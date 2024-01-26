// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {NFGho} from "../src/NFGho.sol";

contract NFGhoTest is Test {
    NFGho public nfgho;

    function setUp() public {
        nfgho = new NFGho();
    }
}
