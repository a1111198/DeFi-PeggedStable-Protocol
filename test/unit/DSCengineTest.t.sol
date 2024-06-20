// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract DSCEngineTest is Test {
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;
    address s_wethAddress;
    address s_wethPriceFeedAddress;
    address s_wBTCAddress;
    address s_wBTCPriceFeedAddress;

    function setUp() external {
        DeployDSC deployDSC = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployDSC.run();
        (
            s_wethAddress,
            s_wethPriceFeedAddress,
            s_wBTCAddress,
            s_wBTCPriceFeedAddress,

        ) = helperConfig.activeHelperConfiguration();
    }

    /// Price test ///
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
}
