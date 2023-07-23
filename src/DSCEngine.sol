// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {console} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Patrick Collins
 * The system is designed to be as minimal as possible, and have the tokens maintian a 1 token == $1 peg.
 * This stablecoin has the properties:
 * - Exogenous Collateral
 * - Dollar pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI has no governance, no fees, and was only backed by WETH and WBTC.
 * Invariant: Our system should keep always over-collateralized. At no point,should the value of all collateral <= the $ backed value of all the DSC.
 * @notice This contract is the core of the DSC System. It handles all the logic for mining and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS(DAI) system.
 */
// Remember that your code is going to be write once but read hundreds of thousands of times. We should be as verbose as possible.

contract DSCEngine is ReentrancyGuard {
    ///////////////
    // Errors    //
    ///////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenIsNotAllowed();
    error DSCEngine__TokenAddressAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorIsBroken(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorIsNotBroken(uint256 healthFactor);
    error DSCEngine__HealthFactorNotImproved(uint256 healthFactor);

    ////////////////////////
    // State Variables    //
    ////////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeeds; // tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited; // userToTokenToAmount
    mapping(address user => uint256 amountDscminted) private s_dscMinted;
    address[] private s_collateralTokens;
    DecentralizedStableCoin private immutable i_dsc;

    ///////////////
    // Events /////
    ///////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    ///////////////
    // Modifiers //
    ///////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenIsNotAllowed();
        }
        _;
    }

    ///////////////
    // Functions //
    ///////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i; i < tokenAddresses.length;) {
            // if the token has a pricefeed, then it is allowed.
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
            unchecked {
                ++i;
            }
        }
        // i_dsc = DecentralizedStableCoin(address(new DecentralizedStableCoin()));
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////////////////
    // External Functions //
    ////////////////////////
    /*
    * @param tokenCollateralAddress The address of the token to deposit as collateral
    * @param amountCollateral the amount of collateral to deposit
    * @param amountDscToMint the amount of Decentralized Stablecoin to mint
    * @notice this function will allow depositing your collateral and mint DSC in 1 tx
    */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice follows CEI
     * @param tokenCollateralAddress The address of the token to be deposited as collateral.
     * @param amountCollateral The amount of collateral to be deposited.
     *
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant // this is a reentrancy guard which we add to make sure it will be safe
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /* 
    * @param tokenCollateralAddress The address of the token to be redeemed.
    * @param amountCollateral The amount of collateral to be redeemed.
    * @param amountDscToBurn The amount of DSC to be burned.
    * @notice this function will allow redeeming your collateral and burn DSC in 1 tx
    */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeemCollateral already
    }

    // in order to redeem collateral:
    // 1. health factor must be over 1 AFTER collateral pulled
    // 2. they must have enough DSC to redeem
    // DRY: do not repeat yourself
    // Follow CEI
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
    }

    // 1. check if the collateral value > threshold DSC value
    /**
     * @notice follows CEI
     * @param amountDscToMint The amount of DSC to mint.
     * @notice they must have more collateral than the minimum threshled value of the DSC they are minting.
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountDscToMint;
        // if they minted too mych($150 DSC, $100 ETH)
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    // burn the token so that it reduces the user's debt
    function burnDsc(uint256 amount) public {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // I don't think this would ever hit...
    }

    // Threshhold: 150%
    // let's say $100 ETH collateral -> $74
    // %50 DSC
    // UNDERCOLLATERALIZED!!!!
    // Hey if someone pays back your minted DSC, they can have all your collateral for a discount now. -> liquidate()
    // someone comes and pay back the $50 loan and get the 74 dollars worth of ETH. The
    // Consequence: liquidator gets rewards and the person who was undercollateralized gets punished for letting the loan get to the status of being undercollateralized.
    // This is the key thing to hold the whole system together
    // if someone is undercollateralized, we will pay you to liquidate them.
    /*
    * @param collateral The erc20 collateral address to liquidate from the user
    * @param user The user to liquidate who has broken the health factor
    * @param debtToCover The amount of debt to cover
    * @notice You can partially liquidate a user
    * @notice You will get a liquidation bonus for liquidating a user 
    * @notice This function working assumes the protocol will be roughly 200% collateralized at all times
    * @notice A known bug would be if the protocol were 100% or less collateralized, then we wouldn't be able to incentivize liquidators.
    * For example, if the price of the collateral plummeted beofre anyone could be liquidated.
    * 
    * follows CEI
    */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        // need to check the health factor of the user
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsNotBroken(startingUserHealthFactor);
        }
        // we want to burn his DSC debt and take his collateral
        // Bad user: $140 ETH, $100 DSC
        // Debt cover: $100
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        // And give them a 10% bonus
        // So we are giving the liquidator $110 of WETH for 100 DSC
        // We should implement a feature to liquidate in the event the protocol is insolvent
        uint256 bonusCollateral = tokenAmountFromDebtCovered * LIQUIDATION_BONUS / LIQUIDATION_PRECISION;
        uint256 totalCollateralToTake = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(collateral, totalCollateralToTake, user, msg.sender);
        // we need to burn the dsc now
        _burnDsc(debtToCover, user, msg.sender);

        // chekc afterwards
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved(endingUserHealthFactor);
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        // price of ETH
        // $/ETH ETH ??
        // $2000 / ETH. $ 1000 = 0.5 ETH
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // ($10e18 * 1e18) / ($2000e8 * 1e10) = 5e18
        return usdAmountInWei * PRECISION / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getHealthFactor() external view {}

    function getCollateralizationRatio() external view {}

    ///////////////////////////////////////
    // Private & Internal View Functions //
    ///////////////////////////////////////

    //
    // @dev Low-level internal function, do not call unless the function calling it is checking for health factors being broken
    //
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_dscMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        // this conditional is hypothically unreachable
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        // pull out collateral and it relies on the solidiity to emit error if underflow
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        // _calculateHealthFactorAfter()
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        _revertIfHealthFactorIsBroken(from);
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_dscMinted[user];
        collateralValueInUsd = getAccountCollaterValue(user);
    }

    /**
     * Returns how close to liquidation a user is
     * If a user goes below 1, then they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        // total SDC minted
        // total collateral VALUE
        (uint256 totalDscMinted, uint256 totalCollateralValue) = _getAccountInformation(user);

        // $500  with $1000 ETH: $500  / 100
        uint256 collateralAdjustedForThreshold = totalCollateralValue * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION; // this is for precision of 100% base calculation
        return collateralAdjustedForThreshold * PRECISION / totalDscMinted;
    }

    // 1. check health factor (do they have enough collateral?)
    // 2. Revert if they don't
    function _revertIfHealthFactorIsBroken(address user) private view {
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsBroken(healthFactor);
        }
    }

    //////////////////////////////////////
    // Public & External View Functions //
    //////////////////////////////////////
    function getAccountCollaterValue(address user) public view returns (uint256) {
        // loop through each collateral token, get the amount they have deposited, and get the price feed for that token.
        address[] memory tokens = s_collateralTokens;
        uint256 totalColalteralValueInUsd;
        for (uint256 i; i < tokens.length;) {
            address token = tokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalColalteralValueInUsd += getUsdValue(token, amount);
            unchecked {
                ++i;
            }
        }
        return totalColalteralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // 1ETH = $1000
        // decimals = 8
        // returned value will be 1000 * 1e8
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION; // 1000 * 1e8 * 1e10 * (1 * 1e18) / 1e18
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        return _getAccountInformation(user);
    }

    // check health factor from the inside
    function calculateHealthFactor(uint256 totalMinted, uint256 collateralValueInUsd) internal view returns (uint256) {
        if (totalMinted == 0) return type(uint256).max; // this is for avoiding deviding by zero
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalMinted;
    }
}

// NatSpec 是 Solidity 的自然语言规范格式，用于编写智能合约的文档。它允许开发者用自然语言描述函数的行为，以及详细说明函数参数、返回值等详细信息。以下是一些常用的 NatSpec 标签：

// @title: 用于说明整个合约的标题或名称。
// @dev: 用于开发者的说明。这可以是关于函数的详细描述，或者解释合约的某个复杂部分。这些注释主要用于开发者参考，不会在用户界面（UI）中显示。
// @notice: 这是给最终用户的说明。这些注释可以解释函数的主要行为，并可以在用户界面（UI）中显示。例如，当用户与合约交互时，这些注释可能会显示给用户，帮助他们理解函数的行为。
// @param: 这个标签后面通常会跟着一个参数名，然后是对这个参数的描述。每个参数都需要一个 @param 标签。
// @return: 这个标签用来描述函数的返回值。
