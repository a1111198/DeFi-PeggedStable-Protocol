// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzepplin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;
    address s_wethAddress;
    address s_wethPriceFeedAddress;
    address s_wBTCAddress;
    address s_wBTCPriceFeedAddress;
    address[] s_colletralTokenAddresses;
    address[] s_priceFeedAddress;
    address USER = makeAddr("user");
    uint256 public constant APPROVE_COLLATERAL_AMOUNT = 10 ether;
    uint256 public constant INITIAL_WETH_AMOUNT = 10 ether;
    uint256 public constant INITIAL_WETH_DEPOSIT_AMOUNT = 1 ether;
    uint256 public constant INITIAL_DSC_MINT_AMOUNT = 1000 ether;
    event ColletralDeposited(
        address indexed user,
        address indexed tokenAddress,
        uint256 amount
    );

    function setUp() external {
        DeployDSC deployDSC = new DeployDSC();
        (
            dsc,
            dscEngine,
            helperConfig,
            s_colletralTokenAddresses,
            s_priceFeedAddress
        ) = deployDSC.run();
        (
            s_wethAddress,
            s_wethPriceFeedAddress,
            s_wBTCAddress,
            s_wBTCPriceFeedAddress,

        ) = helperConfig.activeHelperConfiguration();
        ERC20Mock(s_wethAddress).mint(USER, INITIAL_WETH_AMOUNT);
    }

    //////////////////////////
    ///Consustructor test ///
    /////////////////////////
    function testDscContractAddress() external view {
        address expectedDSCContractAddress = address(dsc);
        address actualDSCContractAddress = dscEngine.getDscContractAddress();
        assertEq(expectedDSCContractAddress, actualDSCContractAddress);
    }

    function testAcceptableColletrals() external view {
        address[] memory actualAcceptableColletrals = dscEngine
            .getAllowedColletrals();
        for (uint i = 0; i < actualAcceptableColletrals.length; i++) {
            assertEq(
                actualAcceptableColletrals[i],
                s_colletralTokenAddresses[i]
            );
        }
    }

    function testPriceFeedForColletrals() external view {
        uint256 _length = s_colletralTokenAddresses.length;
        for (uint i = 0; i < _length; i++) {
            assertEq(
                s_priceFeedAddress[i],
                dscEngine.getPriceFeed(s_colletralTokenAddresses[i])
            );
        }
    }

    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function testMismatchLengthOfColletralAndPriceFeed() external {
        tokenAddresses = [s_wethAddress];
        priceFeedAddresses = [s_wethPriceFeedAddress, s_wBTCPriceFeedAddress];
        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenArrayAndPriceFeedArrayLengthMisMatch
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testEmptyLengthOfColletralArray() external {
        vm.expectRevert(DSCEngine.DSCEngine__TokenArrayIsEmpty.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    //////////////////////////
    ////// Price test ///////
    /////////////////////////
    function testGetPriceInUSD() external view {
        //arrange act assert
        uint256 ethAmount = 15 ether;
        uint256 expectedAmount = 30000e18;
        uint256 actualAmount = dscEngine.getPriceInUSD(
            s_wethPriceFeedAddress,
            ethAmount
        );
        assertEq(actualAmount, expectedAmount);
    }

    function getTokenAmountFromUSD() external view {
        uint256 usdAmount = 100 * 1e18;
        uint256 expectedToken = 5e16;
        uint256 actualTokenAmount = dscEngine.getTokenValueFromUSD(
            s_wethAddress,
            usdAmount
        );
        assertEq(actualTokenAmount, expectedToken);
    }

    ////// Deposit Colletral test ///////
    function testRevertIfColletralIsZero() external {
        vm.startPrank(USER);
        ERC20Mock(s_wethAddress).approveInternal(
            USER,
            address(dscEngine),
            APPROVE_COLLATERAL_AMOUNT
        );
        vm.expectRevert(DSCEngine.DSCEngine__MustBeNonZeroAmount.selector);
        dscEngine.depositCollateral(s_wethAddress, 0);
        vm.stopPrank();
    }

    function testRevertIfNonAllowedColletralIsDeposited() external {
        ERC20Mock someMockToken = new ERC20Mock(
            "NEW TOKEN",
            "NTK",
            USER,
            INITIAL_WETH_AMOUNT
        );
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__ColletralNotAllowed.selector);
        dscEngine.depositCollateral(address(someMockToken), 1 ether);
        vm.stopPrank();
    }

    modifier depositColletral() {
        vm.startPrank(USER);
        ERC20Mock(s_wethAddress).approveInternal(
            USER,
            address(dscEngine),
            APPROVE_COLLATERAL_AMOUNT
        );
        dscEngine.depositCollateral(s_wethAddress, INITIAL_WETH_DEPOSIT_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testDepositColletralAndGetAccountInfo() external depositColletral {
        (uint256 dscMinted, uint256 tokenValueInUSD) = dscEngine
            .getAccountInformation(USER);
        uint256 expectedDscMinted = 0;
        uint256 expectedTokenValue = INITIAL_WETH_DEPOSIT_AMOUNT;
        assertEq(
            INITIAL_WETH_DEPOSIT_AMOUNT,
            dscEngine.getColletralValueOfaUser(USER, s_wethAddress)
        );
        assertEq(expectedDscMinted, dscMinted);
        assertEq(
            expectedTokenValue,
            dscEngine.getTokenValueFromUSD(s_wethAddress, tokenValueInUSD)
        );
    }

    ////// Mint Function test ///////
    function testRevertIfMintingAmountIsZero() external {
        vm.expectRevert(DSCEngine.DSCEngine__MustBeNonZeroAmount.selector);
        dscEngine.mintDSC(0);
    }

    function testRevertIfHealthFactorIsbroken() external depositColletral {
        vm.startPrank(USER);
        bytes4 selector = bytes4(
            keccak256("DSCEngine__HealthFactorBroke(uint256)")
        );
        vm.expectRevert(abi.encodeWithSelector(selector, 5e17));
        dscEngine.mintDSC(2000 ether);
        vm.stopPrank();
    }

    function testMintIfEverythingIsOk() external depositColletral {
        vm.startPrank(USER);
        (uint256 dscMintedBefore, ) = dscEngine.getAccountInformation(USER);
        dscEngine.mintDSC(INITIAL_DSC_MINT_AMOUNT);
        (uint256 dscMinteAfter, ) = dscEngine.getAccountInformation(USER);
        assertEq(dscMinteAfter, dscMintedBefore + INITIAL_DSC_MINT_AMOUNT);
    }

    //////  Deposit Colletral and Mint Function test ///////

    function testdepositCollateralAndMintDSCAndEventEmission() external {
        vm.startPrank(USER);
        (uint256 dscMintedBefore, uint256 colletralValueInUSDBefore) = dscEngine
            .getAccountInformation(USER);
        ERC20Mock(s_wethAddress).approveInternal(
            USER,
            address(dscEngine),
            APPROVE_COLLATERAL_AMOUNT
        );
        address emitterAddress = address(dscEngine);

        vm.expectEmit(true, true, true, true, emitterAddress);
        emit ColletralDeposited(
            USER,
            s_wethAddress,
            INITIAL_WETH_DEPOSIT_AMOUNT
        );
        dscEngine.depositCollateralAndMintDSC(
            s_wethAddress,
            INITIAL_WETH_DEPOSIT_AMOUNT,
            INITIAL_DSC_MINT_AMOUNT
        );
        (uint256 dscMintedAfter, uint256 colletralValueInUSDAfter) = dscEngine
            .getAccountInformation(USER);
        assertEq(dscMintedAfter, dscMintedBefore + INITIAL_DSC_MINT_AMOUNT);
        assertEq(
            colletralValueInUSDAfter,
            colletralValueInUSDBefore +
                dscEngine.getTotalColleteralValueInUSD(USER)
        );
        vm.stopPrank();
    }

    modifier depositCollateralAndMintDSC() {
        vm.startPrank(USER);
        ERC20Mock(s_wethAddress).approveInternal(
            USER,
            address(dscEngine),
            APPROVE_COLLATERAL_AMOUNT
        );
        dscEngine.depositCollateral(s_wethAddress, INITIAL_WETH_DEPOSIT_AMOUNT);
        dscEngine.mintDSC(INITIAL_DSC_MINT_AMOUNT);
        _;
    }
}
