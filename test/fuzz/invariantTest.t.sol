// SPDX-License-Identifier: MIT

// Have your invariant aka properties should always hold.
// What are our invariant?
// 1. The total supply of DSC should be less than the total value of collateral
// 2. Getter view functions should never revert.
// 3. maybe more to come but we will focus on these 2 for now.

pragma solidity 0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/Helper.config.s.sol";

contract contractInvariantsTest is StdInvariant {
    
    
    function setUp() public {
        // varibles for the test
        DeployDSC deployer;
        DSCEngine dsce;
        DecentralizedStableCoin dsc;
        HelperConfig config;
        // deploy contracts and set values
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
    }
}