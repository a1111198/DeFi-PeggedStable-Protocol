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
    address USER = makeAddr("user");
    uint256 public constant APPROVE_COLLATERAL_AMOUNT = 10 ether;
    uint256 public constant INITIAL_WETH_AMOUNT = 10 ether;

    function setUp() external {
        DeployDSC deployDSC = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployDSC.run();
        (
            s_wethAddress,
            s_wethPriceFeedAddress,
            s_wBTCAddress,
            s_wBTCPriceFeedAddress,

        ) = helperConfig.activeHelperConfiguration();
        ERC20Mock(s_wethAddress).mint(USER, INITIAL_WETH_AMOUNT);
    }

    ////// Price test ///////
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
}
