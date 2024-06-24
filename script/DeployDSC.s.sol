//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function run()
        external
        returns (
            DecentralizedStableCoin,
            DSCEngine,
            HelperConfig,
            address[] memory,
            address[] memory
        )
    {
        HelperConfig helperConfig = new HelperConfig();
        (
            address wethAddress,
            address wethPriceFeedAddress,
            address wBTCAddress,
            address wBTCPriceFeedAddress,
            uint256 deployerKey
        ) = helperConfig.activeHelperConfiguration();
        vm.startBroadcast(deployerKey);
        dsc = new DecentralizedStableCoin();
        tokenAddresses = [wethAddress, wBTCAddress];
        priceFeedAddresses = [wethPriceFeedAddress, wBTCPriceFeedAddress];
        dscEngine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(dsc)
        );
        dsc.transferOwnership(address(dscEngine));
        vm.stopBroadcast();
        return (
            dsc,
            dscEngine,
            helperConfig,
            tokenAddresses,
            priceFeedAddresses
        );
    }
}
