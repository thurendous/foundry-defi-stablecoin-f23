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

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

    ////////////////////////
    // State Variables    //
    ////////////////////////
    mapping(address token => address priceFeed) private s_priceFeeds; // tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited; // userToTokenToAmount
    mapping(address user => uint256 amountDscminted) private s_dscMinted;

    ///////////////
    // Events /////
    ///////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);

    DecentralizedStableCoin private immutable i_dsc;

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
    function depositCollateralAndMintDsc() external {}

    /**
     * @notice follows CEI
     * @param tokenCollateralAddress The address of the token to be deposited as collateral.
     * @param amountCollateral The amount of collateral to be deposited.
     *
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
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

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    // 1. check if the collateral value > threshold DSC value
    /**
     * @notice follows CEI
     * @param amountDscToMint The amount of DSC to mint.
     * @notice they must have more collateral than the minimum threshled value of the DSC they are minting.
     */
    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountDscToMint;
        revertIfHealthFactorIsBroken(msg.sender);
        i_dsc.mint(msg.sender, amountDscToMint);
    }

    function burnDsc() external {}

    // Threshhold: 150%
    // let's say $100 ETH collateral -> $74
    // %50 DSC
    // UNDERCOLLATERALIZED!!!!
    // Hey if someone pays back your minted DSC, they can have all your collateral for a discount now. -> liquidate()
    // someone comes and pay back the $50 loan and get the 74 dollars worth of ETH. The
    // Consequence: liquidator gets rewards and the person who was undercollateralized gets punished for letting the loan get to the status of being undercollateralized.
    function liquidate() external {}

    function getHealthFactor() external view {}

    function getCollateralizationRatio() external view {}

    //////////////////////////////////
    // Private & Internal Functions //
    //////////////////////////////////
    function revertIfHealthFactorIsBroken(address user) private view {
        // 1. check health factor (do they have enough collateral?)
        // 2. Revert if they don't
    }
}
