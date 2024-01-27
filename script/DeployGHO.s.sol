// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {GhoToken} from "gho-core/src/contracts/gho/GhoToken.sol";
import {Gsm} from "gho-core/src/contracts/facilitators/gsm/Gsm.sol";
import {AdminUpgradeabilityProxy} from
    "@aave/core-v3/contracts/dependencies/openzeppelin/upgradeability/AdminUpgradeabilityProxy.sol";
import {TestnetERC20} from "@aave/periphery-v3/contracts/mocks/testnet-helpers/TestnetERC20.sol";
import {FixedPriceStrategy} from "gho-core/src/contracts/facilitators/gsm/priceStrategy/FixedPriceStrategy.sol";
import {Constants} from "gho-core/src/test/helpers/Constants.sol";
import {PoolMock, ATokenMock} from "../test/mocks/PoolMock.sol";
import {IPool} from "@aave/core-v3/contracts/protocol/pool/Pool.sol";

contract DeployGHO is Script, Constants {
    GhoToken GHO_TOKEN;
    Gsm GHO_GSM;

    address alice = makeAddr("alice");

    function run() external returns (GhoToken, Gsm, TestnetERC20, IPool, ATokenMock) {
        // Deploy GhoToken
        GHO_TOKEN = new GhoToken(alice);
        vm.startPrank(alice);
        GHO_TOKEN.grantRole(GHO_TOKEN.FACILITATOR_MANAGER_ROLE(), alice);
        vm.stopPrank();

        // Deploy Gsm
        TestnetERC20 USDC_TOKEN = new TestnetERC20("USD Coin", "USDC", 6, FAUCET);
        FixedPriceStrategy GHO_GSM_FIXED_PRICE_STRATEGY =
            new FixedPriceStrategy(DEFAULT_FIXED_PRICE, address(USDC_TOKEN), 6);
        Gsm gsm = new Gsm(address(GHO_TOKEN), address(USDC_TOKEN), address(GHO_GSM_FIXED_PRICE_STRATEGY));
        AdminUpgradeabilityProxy gsmProxy = new AdminUpgradeabilityProxy(address(gsm), SHORT_EXECUTOR, "");
        GHO_GSM = Gsm(address(gsmProxy));
        GHO_GSM.initialize(address(this), TREASURY, DEFAULT_GSM_USDC_EXPOSURE);
        // zero fee
        GHO_GSM.updateFeeStrategy(address(0));

        // Add Gsm as a facilitator
        vm.prank(alice);
        GHO_TOKEN.addFacilitator(address(GHO_GSM), "Gsm", 100_000 ether);

        // Deploy Aave PoolMock, USDC's ATokenMock
        IPool pool = IPool(address(new PoolMock()));
        ATokenMock usdcAToken = new ATokenMock(pool);
        PoolMock(address(pool)).setAToken(usdcAToken);

        return (GHO_TOKEN, GHO_GSM, USDC_TOKEN, pool, usdcAToken);
    }
}
