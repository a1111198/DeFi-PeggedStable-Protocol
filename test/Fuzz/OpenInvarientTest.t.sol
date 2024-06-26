// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzepplin/contracts/mocks/ERC20Mock.sol";

contract OpenInvarientTests is StdInvariant, Test {
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;
    address[] s_colletralTokenAddresses;
    address[] s_priceFeedAddress;
    address s_wethAddress;
    address s_wethPriceFeedAddress;
    address s_wBTCAddress;
    address s_wBTCPriceFeedAddress;

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
        targetContract(address(dscEngine));
    }

    function testDscTotalSupplyMustBeLessThanColletralValue() external view {
        uint256 totalDscSupply = ERC20Mock(address(dsc)).totalSupply();
        uint256 wethBalance = ERC20Mock(s_wethAddress).balanceOf(
            address(dscEngine)
        );
        uint256 wbtcBalance = ERC20Mock(s_wBTCAddress).balanceOf(
            address(dscEngine)
        );
        assert(
            totalDscSupply <=
                dscEngine.getPriceInUSD(s_wethPriceFeedAddress, wethBalance) +
                    dscEngine.getPriceInUSD(s_wBTCPriceFeedAddress, wbtcBalance)
        );
    }
}
