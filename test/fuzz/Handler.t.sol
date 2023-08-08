// SPDX-License-Identifier: MIT
// This should narrow down the tests we are going to run as fuzzing tests.

pragma solidity 0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    address weth;
    address wbtc;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dsce = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = collateralTokens[0];
        wbtc = collateralTokens[1];
    }

    // redeem collateral

    // pick a random collateral to deposit and random amount to deposit
    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateralToken = _getCollateralFromSeed(collateralSeed);
        uint256 amount = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);
        collateralToken.mint(msg.sender, amount);
        collateralToken.approve(address(dsce), amount);
        dsce.depositCollateral(address(collateralToken), amount);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateralToken = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dsce.getCollateralBalanceOfUser(address(collateralToken), msg.sender);
        uint256 amount = bound(amountCollateral, 0, maxCollateralToRedeem);
        vm.startPrank(msg.sender);
        if (amount == 0) {
            return;
        }
        dsce.redeemCollateral(address(collateralToken), amount);
        vm.stopPrank();
    }

    // Helper function to select token
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return ERC20Mock(wbtc);
        } else {
            return ERC20Mock(weth);
        }
    }
}
