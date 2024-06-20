// SPDX-License-Identifier: MIT

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
// view & pure functions

pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzepplin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzepplin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
/**
 * @title DSCEngine
 * @author Akash Bansal
 *
 * @notice This contract is the core of the DSC (Decentralized Stable Coin) system. It handles all the core logic for minting and redeeming DSC, as well as withdrawing and depositing collateral.
 *
 * The system is designed to be as minimal as possible and to maintain a stable peg of 1 DSC == $1.
 *
 * Properties:
 * - Exogenous Collateral: The system uses external assets (like WETH and WBTC) as collateral.
 * - Dollar Pegged: The value of the DSC token is pegged to the US Dollar.
 * - Algorithmically Stable: The system uses algorithms to maintain the peg and ensure stability.
 *
 * @notice The DSC system is inspired by DAI but is designed without governance and fees. It is backed solely by WETH (Wrapped Ether) and WBTC (Wrapped Bitcoin).
 *
 * @notice Our DSC system is designed to be always "over-collateralized". This means that at no point should the total value of all collateral be less than or equal to the dollar value backed by all the DSC in circulation. This ensures the stability and reliability of the system.
 *
 * @notice This contract is very loosely based on the MakerDAO DSS (DAI) system, incorporating similar concepts but with simplified governance and fee structures.
 */

contract DSCEngine is ReentrancyGuard {
    ////////////////////////
    //Errors             //
    ////////////////////////
    error DSCEngine__MustBeNonZeroAmount();
    error DSCEngine__TokenArrayAndPriceFeedArrayLengthMisMatch();
    error DSCEngine__TokenArrayIsEmpty();
    error DSCEngine__ColletralNotAllowed();
    error DSCEngine__TransferFromFailed();
    error DSCEngine__HealthFactorBroke(uint256 healthFactor);
    error DSCEngine__DSCMintingFailed();
    ////////////////////////
    // State Variales     //
    ////////////////////////

    mapping(address tokenAddress => address priceFeedAddress) s_priceFeed;
    mapping(address users => mapping(address colletralAddress => uint256 amount)) s_colletralDeposited;
    mapping(address userAddress => uint256 amountMinted) s_dscMinted;
    address[] allAcceptableColletrals;

    DecentralizedStableCoin private immutable i_dscContract;

    uint256 private constant ADDITIONAL_DECIMAL_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDITY_THRESHOLD = 50; // 200% OverCollatralised.
    uint256 private constant LIQUIDITY_PRECESION = 100;
    uint256 private constant MINIMUM_HEALTH_FACTOR = 1;
    ////////////////////////
    // Events            //
    ////////////////////////

    event ColletralDeposited(address indexed, address indexed, uint256);

    ////////////////////////
    //Modifiers          //
    ////////////////////////

    modifier nonZeroAmount(uint256 _amount) {
        if (_amount == 0) {
            revert DSCEngine__MustBeNonZeroAmount();
        }
        _;
    }

    modifier onlyAllowedTokens(address colletralAddress) {
        if (s_priceFeed[colletralAddress] == address(0)) revert DSCEngine__ColletralNotAllowed();
        _;
    }

    ////////////////////////
    //Functions           //
    ////////////////////////

    ////////////////////////
    //Constructor        //
    ////////////////////////

    /**
     * @notice Initializes the DSCEngine contract with the provided parameters.
     *
     * @param collateralTokenAddresses An array of addresses for the tokens that will be used as collateral.
     * These should be the addresses of the token contracts that the DSC system accepts as collateral (e.g., WETH, WBTC).
     *
     * @param priceFeedAddresses An array of addresses for the price feed contracts corresponding to each collateral token.
     * Each address in this array should be the address of an oracle or price feed contract that provides the price of the associated collateral token in USD.
     *
     * @param dscTokenAddress The address of the DSC (Decentralized Stable Coin) token contract.
     * This should be the address of the token contract that represents the stable coin within the DSC system.
     *
     * @dev The length of `collateralTokenAddresses` and `priceFeedAddresses` arrays must be equal and non-zero.
     * If the lengths do not match or if any array is empty, the function will revert.
     * The constructor maps each collateral token address to its corresponding price feed address.
     */
    constructor(
        address[] memory collateralTokenAddresses,
        address[] memory priceFeedAddresses,
        address dscTokenAddress
    ) {
        if (collateralTokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenArrayAndPriceFeedArrayLengthMisMatch();
        }
        if (collateralTokenAddresses.length == 0) {
            revert DSCEngine__TokenArrayIsEmpty();
        }
        for (uint256 i = 0; i < collateralTokenAddresses.length; i++) {
            s_priceFeed[collateralTokenAddresses[i]] = priceFeedAddresses[i];
            allAcceptableColletrals.push(collateralTokenAddresses[i]);
        }
        i_dscContract = DecentralizedStableCoin(dscTokenAddress);
    }

    ////////////////////////
    //Functions External //
    ////////////////////////

    function depositCollateralAndMintDSC() external {}

    /**
     * @notice Deposits a specified amount of collateral into the DSC system.
     *
     * @notice It follows CEI pattern.
     *
     * @param collateralTokenAddress The address of the token contract that will be used as collateral.
     * This should be the address of a token that the DSC system accepts as collateral (e.g., WETH or WBTC).
     *
     * @param amountOfCollateral The amount of the collateral token to deposit.
     * This value should be specified in the smallest unit of the token (e.g., wei for WETH).
     */
    function depositCollateral(address collateralTokenAddress, uint256 amountOfCollateral)
        external
        nonZeroAmount(amountOfCollateral)
        onlyAllowedTokens(collateralTokenAddress)
        nonReentrant
    {
        s_colletralDeposited[msg.sender][collateralTokenAddress] += amountOfCollateral;
        emit ColletralDeposited(msg.sender, collateralTokenAddress, amountOfCollateral);
        bool status = IERC20(collateralTokenAddress).transferFrom(msg.sender, address(this), amountOfCollateral);
        if (!status) {
            revert DSCEngine__TransferFromFailed();
        }
    }

    function mintDSC(uint256 dscAmountToMint) external nonZeroAmount(dscAmountToMint) nonReentrant {
        s_dscMinted[msg.sender] = dscAmountToMint;
        // Check If the HealFactor is Ok
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dscContract.mint(msg.sender, dscAmountToMint);
        if (!minted) {
            revert DSCEngine__DSCMintingFailed();
        }
    }

    function redeemCollateralForDSC() external {}

    function redeemCollateral() external {}

    function burnDSC() external {}

    function liquidate() external {}

    function getHealthFactor() external {}
    ////////////////////////
    //Functions Internal  //
    ////////////////////////

    function _getHealthFactor(address user) private view returns (uint256 userHelthFactor) {
        // total DSC minted.
        // totalColletralValueInUSD
        (uint256 dscMinted, uint256 totalColleteralValueInUSD) = getAccountInformation(user);
        uint256 adjustedColleteralValueInUSD = (totalColleteralValueInUSD * LIQUIDITY_THRESHOLD) / LIQUIDITY_PRECESION;
        userHelthFactor = adjustedColleteralValueInUSD / dscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _getHealthFactor(user);
        if (userHealthFactor < MINIMUM_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorBroke(userHealthFactor);
        }
    }
    //////////////////////////
    //Functions public view //
    //////////////////////////

    function getTotalColleteralValueInUSD(address user) public view returns (uint256 totalColleteralValueInUSD) {
        uint256 allAcceptableColletralsLength = allAcceptableColletrals.length;

        for (uint256 i = 0; i < allAcceptableColletralsLength; i++) {
            uint256 amountOfColletral = s_colletralDeposited[user][allAcceptableColletrals[i]];
            totalColleteralValueInUSD += getPriceInUSD(s_priceFeed[allAcceptableColletrals[i]], amountOfColletral);
        }
    }

    function getPriceInUSD(address _priceFeedAddress, uint256 _amount) public view returns (uint256 valueInUSD) {
        AggregatorV3Interface priceFeedInterface = AggregatorV3Interface(_priceFeedAddress);
        (, int256 pertokenValueInUSD,,,) = priceFeedInterface.latestRoundData();
        valueInUSD = (uint256(pertokenValueInUSD) * ADDITIONAL_DECIMAL_PRECISION * _amount) / PRECISION;
    }

    function getAccountInformation(address user)
        public
        view
        returns (uint256 dscMinted, uint256 totalColleteralValueInUSD)
    {
        dscMinted = s_dscMinted[user];
        totalColleteralValueInUSD = getTotalColleteralValueInUSD(user);
    }
}
