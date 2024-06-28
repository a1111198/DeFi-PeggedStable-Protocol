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
import {Script, console} from "forge-std/Script.sol";
import {OracleLib} from "./libraries/oracleLibrbray.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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

contract DSCEngine is ReentrancyGuard, Script {
    ////////////////////////
    //Errors             //
    ////////////////////////
    error DSCEngine__MustBeNonZeroAmount();
    error DSCEngine__TokenArrayAndPriceFeedArrayLengthMisMatch();
    error DSCEngine__TokenArrayIsEmpty();
    error DSCEngine__ColletralNotAllowed();
    error DSCEngine__TransferFromFailed();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorBroke(uint256 healthFactor);
    error DSCEngine__DSCMintingFailed();
    error DSCEngine__CanNotLiquiateDueToHealthyHealthFactor(
        uint256 userHealthFactor
    );
    error DSCEngine__HealthFactorNotImproved();
    ////////////////////////
    // Type    //
    ////////////////////////
    using OracleLib for AggregatorV3Interface;

    ////////////////////////
    // State Variales     //
    ////////////////////////

    uint256 private constant ADDITIONAL_DECIMAL_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDITY_THRESHOLD = 50; // 200% OverCollatralised.
    uint256 private constant LIQUIDITY_PRECESION = 100;
    uint256 private constant MINIMUM_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus for liquidator.

    DecentralizedStableCoin private immutable i_dscContract;

    mapping(address tokenAddress => address priceFeedAddress) s_priceFeed;
    mapping(address users => mapping(address colletralAddress => uint256 amount)) s_colletralDeposited;
    mapping(address userAddress => uint256 amountMinted) s_dscMinted;
    address[] s_acceptableColletrals;

    ////////////////////////
    // Events            //
    ////////////////////////

    event ColletralDeposited(
        address indexed user,
        address indexed tokenAddress,
        uint256 amount
    );
    event CollateralReedemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed tokenAddress,
        uint256 amount
    );

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
        if (s_priceFeed[colletralAddress] == address(0))
            revert DSCEngine__ColletralNotAllowed();
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
            s_acceptableColletrals.push(collateralTokenAddresses[i]);
        }
        i_dscContract = DecentralizedStableCoin(dscTokenAddress);
    }

    ////////////////////////
    //Functions External //
    ////////////////////////
    /**
     * @notice Deposits collateral and mints DSC
     * @param collateralTokenAddress The address of the token contract to be used as collateral
     * @param amountOfCollateral The amount of the collateral token to deposit
     * @param dscAmountToMint The amount of DSC to mint
     */

    function depositCollateralAndMintDSC(
        address collateralTokenAddress,
        uint256 amountOfCollateral,
        uint256 dscAmountToMint
    ) external {
        depositCollateral(collateralTokenAddress, amountOfCollateral);
        mintDSC(dscAmountToMint);
    }

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
    function depositCollateral(
        address collateralTokenAddress,
        uint256 amountOfCollateral
    )
        public
        nonZeroAmount(amountOfCollateral)
        onlyAllowedTokens(collateralTokenAddress)
        nonReentrant
    {
        s_colletralDeposited[msg.sender][
            collateralTokenAddress
        ] += amountOfCollateral;
        emit ColletralDeposited(
            msg.sender,
            collateralTokenAddress,
            amountOfCollateral
        );
        bool status = IERC20(collateralTokenAddress).transferFrom(
            msg.sender,
            address(this),
            amountOfCollateral
        );
        if (!status) {
            revert DSCEngine__TransferFromFailed();
        }
    }

    /**
     * @notice Mints DSC tokens to the user
     * @param dscAmountToMint The amount of DSC to mint
     */

    function mintDSC(
        uint256 dscAmountToMint
    ) public nonZeroAmount(dscAmountToMint) nonReentrant {
        s_dscMinted[msg.sender] += dscAmountToMint;
        // Check If the HealFactor is Ok
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dscContract.mint(msg.sender, dscAmountToMint);
        if (!minted) {
            revert DSCEngine__DSCMintingFailed();
        }
    }

    /**
     * @notice Redeems collateral for DSC and burns the specified amount of DSC.
     * @param collateralTokenAddress The address of the token contract to be redeemed as collateral.
     * @param amountOfCollateralToRedeem The amount of collateral to redeem.
     * @param dscAmountToBurn The amount of DSC to burn.
     * @dev Ensures health factor maintenance after the transaction.
     */
    function burnDSCAndredeemCollateral(
        address collateralTokenAddress,
        uint256 amountOfCollateralToRedeem,
        uint256 dscAmountToBurn
    ) external {
        burnDSC(dscAmountToBurn);
        redeemCollateral(collateralTokenAddress, amountOfCollateralToRedeem);
        // No need to check health factor again.
        // No need to emit event again as it has been emitted.
    }

    /**
     * @notice Redeems a specified amount of collateral from the DSC system.
     * @param collateralTokenAddress The address of the token contract to be redeemed as collateral.
     * @param amountOfCollateralToRedeem The amount of collateral to redeem.
     * @dev Checks if the sender's balance is sufficient and maintains health factor after transfer.
     */
    function redeemCollateral(
        address collateralTokenAddress,
        uint256 amountOfCollateralToRedeem
    ) public nonZeroAmount(amountOfCollateralToRedeem) nonReentrant {
        // Here balance will be checked by Solidity SafeMath by default
        _redeemColletral(
            msg.sender,
            msg.sender,
            collateralTokenAddress,
            amountOfCollateralToRedeem
        );
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Burns a specified amount of DSC tokens.
     * @param dscAmountToBurn The amount of DSC to burn.
     * @dev Transfers DSC from the sender to the contract and then burns it.
     * Ensures health factor is maintained after burning DSC.
     */
    function burnDSC(
        uint256 dscAmountToBurn
    ) public nonZeroAmount(dscAmountToBurn) {
        _burnDsc(msg.sender, msg.sender, dscAmountToBurn);
        _revertIfHealthFactorIsBroken(msg.sender); // unlikely to hit anyway
    }

    /**
     *
     * @param colletralAdrress Colletral token Address an ERC20 token address.
     * @param user Address of user whome we want to liquidate where his health factor is below MIN_HEALTH_FACTOR.
     * @param debtAmountToCover amount that needs to burn to maintain user HelathFactor
     * @notice you can partially liquidate a user.
     * @notice Liquidators will be incentivized for maintaining protocols integrity.
     * @notice A known bug is there if the protocol is 100% or less collateralized in that liquidators is not incentivized
     */

    function liquidate(
        address colletralAdrress,
        address user,
        uint256 debtAmountToCover
    ) external nonZeroAmount(debtAmountToCover) nonReentrant {
        uint256 startingUserHealthFactor = _getHealthFactor(user);
        if (startingUserHealthFactor >= MINIMUM_HEALTH_FACTOR) {
            revert DSCEngine__CanNotLiquiateDueToHealthyHealthFactor(
                startingUserHealthFactor
            );
        }
        uint256 tokenAmountFromDebtCovered = getTokenValueFromUSD(
            colletralAdrress,
            debtAmountToCover
        );
        uint256 bonusColletral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDITY_PRECESION;
        uint256 totalColletralToRedeem = (tokenAmountFromDebtCovered +
            bonusColletral);
        _redeemColletral(
            user,
            msg.sender,
            colletralAdrress,
            totalColletralToRedeem
        );
        _burnDsc(user, msg.sender, debtAmountToCover);
        uint256 endingHealthFactor = _getHealthFactor(user);
        if (endingHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        // Also checking that HealthFactor is not broken for the sender by this activity.
    }

    function getHealthFactor(address user) public view returns (uint256) {
        return _getHealthFactor(user);
    }

    ////////////////////////
    //Functions Internal  //
    ////////////////////////
    function _redeemColletral(
        address from,
        address to,
        address collateralTokenAddress,
        uint256 amountOfCollateralToRedeem
    ) internal {
        uint256 userColletralAmount = s_colletralDeposited[from][
            collateralTokenAddress
        ];
        console.log("DSC_USER_COLLETRAL", userColletralAmount);
        console.log("DSC_AMOUNT_TOREDEEM", amountOfCollateralToRedeem);

        s_colletralDeposited[from][collateralTokenAddress] =
            userColletralAmount -
            amountOfCollateralToRedeem;
        console.log(
            "DSC AFTER AMOUNT",
            s_colletralDeposited[from][collateralTokenAddress]
        );
        emit CollateralReedemed(
            from,
            to,
            collateralTokenAddress,
            amountOfCollateralToRedeem
        );
        bool _success = IERC20(collateralTokenAddress).transfer(
            to,
            amountOfCollateralToRedeem
        );
        if (!_success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /// Don't let anyone call this internal function without ever checking or the Health Factor

    function _burnDsc(
        address onBehalfOf,
        address dscFrom,
        uint256 dscAmountToBurn
    ) internal {
        s_dscMinted[onBehalfOf] -= dscAmountToBurn;
        bool _success = i_dscContract.transferFrom(
            dscFrom,
            address(this),
            dscAmountToBurn
        );
        if (!_success) {
            revert DSCEngine__TransferFromFailed();
        }
        i_dscContract.burn(dscAmountToBurn);
    }

    function _getHealthFactor(
        address user
    ) private view returns (uint256 userHelthFactor) {
        // total DSC minted.
        // totalColletralValueInUSD
        (
            uint256 dscMinted,
            uint256 totalColleteralValueInUSD
        ) = _getAccountInformation(user);
        if (dscMinted == 0) {
            return type(uint256).max;
        }
        uint256 adjustedColleteralValueInUSD = (totalColleteralValueInUSD *
            LIQUIDITY_THRESHOLD) / LIQUIDITY_PRECESION;
        userHelthFactor =
            (adjustedColleteralValueInUSD * PRECISION) /
            dscMinted;
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
    function _getAccountInformation(
        address user
    )
        internal
        view
        returns (uint256 dscMinted, uint256 totalColleteralValueInUSD)
    {
        dscMinted = s_dscMinted[user];
        totalColleteralValueInUSD = getTotalColleteralValueInUSD(user);
    }

    function getTotalColleteralValueInUSD(
        address user
    ) public view returns (uint256 totalColleteralValueInUSD) {
        uint256 allAcceptableColletralsLength = s_acceptableColletrals.length;

        for (uint256 i = 0; i < allAcceptableColletralsLength; i++) {
            uint256 amountOfColletral = s_colletralDeposited[user][
                s_acceptableColletrals[i]
            ];
            totalColleteralValueInUSD += getPriceInUSD(
                s_priceFeed[s_acceptableColletrals[i]],
                amountOfColletral
            );
        }
    }

    function getTokenValueFromUSD(
        address colletralAddress,
        uint256 usdAmountInWei
    ) public view returns (uint256 tokenValue) {
        AggregatorV3Interface priceFeedInterface = AggregatorV3Interface(
            s_priceFeed[colletralAddress]
        );
        (, int256 pertokenValueInUSD, , , ) = priceFeedInterface
            .stalePriceCheck();
        return
            (usdAmountInWei * PRECISION) /
            (uint256(pertokenValueInUSD) * ADDITIONAL_DECIMAL_PRECISION);
    }

    function getPriceInUSD(
        address _priceFeedAddress,
        uint256 _amount
    ) public view returns (uint256 valueInUSD) {
        AggregatorV3Interface priceFeedInterface = AggregatorV3Interface(
            _priceFeedAddress
        );
        (, int256 pertokenValueInUSD, , , ) = priceFeedInterface
            .stalePriceCheck();
        valueInUSD =
            (uint256(pertokenValueInUSD) *
                ADDITIONAL_DECIMAL_PRECISION *
                _amount) /
            PRECISION;
    }

    function getAccountInformation(
        address user
    )
        public
        view
        returns (uint256 dscMinted, uint256 totalColleteralValueInUSD)
    {
        return _getAccountInformation(user);
    }

    function getColletralValueOfaUser(
        address user,
        address colletralAddress
    ) public view returns (uint256) {
        return s_colletralDeposited[user][colletralAddress];
    }

    function getDscContractAddress() external view returns (address) {
        return address(i_dscContract);
    }

    function getAllowedColletrals() external view returns (address[] memory) {
        return s_acceptableColletrals;
    }

    function getPriceFeed(
        address colletralAddress
    ) external view returns (address) {
        return s_priceFeed[colletralAddress];
    }
}
