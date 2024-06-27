// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzepplin/contracts/mocks/ERC20Mock.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantTests is StdInvariant, Test {
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;
    address[] s_colletralTokenAddresses;
    address[] s_priceFeedAddress;
    address s_wethAddress;
    address s_wethPriceFeedAddress;
    address s_wBTCAddress;
    address s_wBTCPriceFeedAddress;
    Handler handler;

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
        console.log(s_wethAddress);
        console.log(s_wBTCAddress);
        handler = new Handler(dsc, dscEngine);
        targetContract(address(handler));
    }

    function invariant_DscTotalDSCSupplyMustBeLessThanColletralValue7()
        external
        view
    {
        uint256 totalDscSupply = ERC20Mock(address(dsc)).totalSupply();
        uint256 wethBalance = ERC20Mock(s_wethAddress).balanceOf(
            address(dscEngine)
        );
        uint256 wbtcBalance = ERC20Mock(s_wBTCAddress).balanceOf(
            address(dscEngine)
        );
        console.log("TOTAL SUPPLY", totalDscSupply);
        uint256 wethInUSD = dscEngine.getPriceInUSD(
            s_wethPriceFeedAddress,
            wethBalance
        );
        uint256 wbtcInUSD = dscEngine.getPriceInUSD(
            s_wBTCPriceFeedAddress,
            wbtcBalance
        );
        console.log("totalWEthInUSD", wethInUSD);
        console.log("totalwbtcIN USD", wbtcInUSD);

        // here overFlow may occure so it may fail:(totalDscSupply >= (wethInUSD + wbtcInUSD));
        // although solidity will handle it so would through a panic attack. but I want to run all cases and revert to be 0 ;
        //so to handle that;
        //After doing it realised no Need of it as bound of colleteral is uint96 max so it wouldn't matter much as USD is 2000$ only
        if (totalDscSupply == 0) return;
        // to check overFlow
        if (wethInUSD > type(uint256).max - wbtcInUSD) {
            // since totalDSCSupply is uint256 and overflow occured means this number (totalDSCSuppply is lower than sum of wethInUSD and wbtcInUSD)
            return;
        } else {
            assert(totalDscSupply < (wethInUSD + wbtcInUSD));
        }
    }
}
