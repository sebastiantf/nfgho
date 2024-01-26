// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {GhoToken} from "gho-core/src/contracts/gho/GhoToken.sol";

contract DeployGHO is Script {
    GhoToken GHO_TOKEN;

    function run() external returns (GhoToken) {
        GHO_TOKEN = new GhoToken();
        return GHO_TOKEN;
    }
}
