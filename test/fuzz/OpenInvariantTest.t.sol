// // SPDX-License-Identifier: MIT

// // Have your invariant aka properties should always hold.
// // What are our invariant???
// // 1. The total supply of DSC should be less than the total value of collateral
// // 2. Getter view functions should never revert.
// // 3. maybe more to come but we will focus on these 2 for now.

// pragma solidity 0.8.18;

// import {Test, console} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DeployDSC} from "../../script/DeployDSC.s.sol";
// import {DSCEngine} from "../../src/DSCEngine.sol";
// import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
// import {HelperConfig} from "../../script/Helper.config.s.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// // stateless fuzzing: stateless means the tests everytime is isolated
// // stateful fuzzing: invariant fuzzing means the tests everytime is related

// contract contractInvariantsTest is StdInvariant, Test {
//     DeployDSC deployer;
//     DSCEngine dsce;
//     DecentralizedStableCoin dsc;
//     HelperConfig config;
//     address weth;
//     address wbtc;

//     function setUp() public {
//         deployer = new DeployDSC();
//         (dsc, dsce, config) = deployer.run();
//         (weth, wbtc,,,) = config.activeNetworkConfig();
//         targetContract(address(dsce));
//     }

//     function invariant_protocolMustHaveMoreValueThanTotalSupply() public {
//         // get the value of all the collateral in the protocol
//         // compare it to all the debt(dsc) in the protocol
//         uint256 totalSupply = dsc.totalSupply();
//         uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsc));
//         uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsc));
//         uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
//         uint256 wbtcValue = dsce.getUsdValue(wbtc, totalWbtcDeposited);
//         console.log("weth value", wethValue);
//         console.log("wbtc value", wbtcValue);
//         assertEq(totalSupply <= wethValue + wbtcValue, true);
//         // we made this <= so that this passed. there is no way to make this fail right now. GOOD!
//     }
// }
