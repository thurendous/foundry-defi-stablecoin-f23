// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/Helper.config.s.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;

    // uint256 amountCollateral = 10 ether;
    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant TEST_AMOUNT_1_ETHER = 1 ether;
    uint256 public constant TEST_AMOUNT_MINIMUM_ETHER = 1 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (weth, wbtc, ethUsdPriceFeed, btcUsdPriceFeed,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_USER_BALANCE);
    }

    ///////////////////////////
    //// constructor Feed /////
    ///////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        console.log(tokenAddresses.length, priceFeedAddresses.length);
        console.logBytes4(DSCEngine.DSCEngine__TokenAddressAndPriceFeedAddressesMustBeSameLength.selector);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses,address(dsc));
    }

    //////////////////////////
    //// Test Price Feed /////
    //////////////////////////
    function testGetUsdValue() public {
        uint256 ethAmount = 15 ether;
        uint256 expectedUsd = 30000e18;
        uint256 value = dsce.getUsdValue(weth, ethAmount);
        assertEq(value, expectedUsd);
    }

    function testGetUsdValuePattern2() public {
        uint256 ethAmount = 105 ether;
        uint256 expectedUsd = 210000e18;
        uint256 value = dsce.getUsdValue(weth, ethAmount);
        assertEq(value, expectedUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        // console.log(usdAmount, expectedWeth);
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualWeth, expectedWeth);
    }

    function testGetTokenAmountFromUsdPattern2() public {
        uint256 usdAmount = 11000 ether;
        uint256 expectedWeth = 5.5 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualWeth, expectedWeth);
    }
    //////////////////////////////////
    //// Deposit collateral Test /////
    //////////////////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositedCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectedDepositedAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, 0);
        assertEq(expectedDepositedAmount, AMOUNT_COLLATERAL);
    }

    // function testCanDepositCollateralAndGetAccountInfo() public depositedCollater {}
    function testCanDepositCollater() public depositedCollateral {
        vm.startPrank(USER);
        ERC20Mock(weth).mint(USER, AMOUNT_COLLATERAL);
        ERC20Mock(weth).approve(address(dsce), TEST_AMOUNT_1_ETHER);
        dsce.depositCollateral(weth, TEST_AMOUNT_1_ETHER);
        vm.stopPrank();
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, 0);
        assertEq(collateralValueInUsd, dsce.getUsdValue(weth, AMOUNT_COLLATERAL + TEST_AMOUNT_1_ETHER));
    }

    function testCannotMintWithoutDepositingCollateral() public {
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorIsBroken.selector, 0)); // 0 is the health factor as argument
        dsce.mintDsc(1 ether);
        vm.stopPrank();
    }

    function testCanMintWithDepositingCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.mintDsc(1 ether);
        vm.stopPrank();
        assertEq(dsc.balanceOf(USER), 1 ether);
    }

    function testCanMintWithDepositingCollateralPattern2() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.mintDsc(10000 ether);
        vm.stopPrank();
        assertEq(dsc.balanceOf(USER), 10000 ether);
    }
}
