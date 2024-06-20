//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzepplin/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    uint8 private constant DECIMALS = 8;
    int256 public constant INITIAL_ETH_USD_PRICE = 2000 * 1e8;
    int256 public constant INITIAL_BTC_USD_PRICE = 1000 * 1e8;
    uint256 public constant INITIAL_WETH = 1000 ether;
    uint256 public constant DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    struct NetworkCongiguration {
        address wethAddress;
        address wethPriceFeedAddress;
        address wBTCAddress;
        address wBTCPriceFeedAddress;
        uint256 deployerKey;
    }

    NetworkCongiguration public activeHelperConfiguration;

    constructor() {
        if (block.chainid == 11155111) {
            activeHelperConfiguration = getSepoliaConfiguration();
        } else {
            activeHelperConfiguration = makeAndgetAnvilConfiguration();
        }
    }

    function getSepoliaConfiguration()
        public
        view
        returns (NetworkCongiguration memory)
    {
        return
            NetworkCongiguration({
                wethAddress: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
                wethPriceFeedAddress: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
                wBTCAddress: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
                wBTCPriceFeedAddress: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
                deployerKey: vm.envUint("PRIVATE_KEY")
            });
    }

    function makeAndgetAnvilConfiguration()
        public
        returns (NetworkCongiguration memory)
    {
        if (activeHelperConfiguration.wethAddress != address(0)) {
            return activeHelperConfiguration;
        }
        vm.startBroadcast(DEFAULT_ANVIL_PRIVATE_KEY);
        MockV3Aggregator mockV3AggregatorEth = new MockV3Aggregator(
            DECIMALS,
            INITIAL_ETH_USD_PRICE
        );
        ERC20Mock wethMock = new ERC20Mock(
            "wrapped Ether",
            "WETH",
            msg.sender,
            INITIAL_WETH
        );
        MockV3Aggregator mockV3AggregatorBtc = new MockV3Aggregator(
            DECIMALS,
            INITIAL_BTC_USD_PRICE
        );
        ERC20Mock wbtcMock = new ERC20Mock(
            "wrapped BTC",
            "WBTC",
            msg.sender,
            INITIAL_WETH
        );
        vm.stopBroadcast();
        return
            NetworkCongiguration({
                wethAddress: address(wethMock),
                wethPriceFeedAddress: address(mockV3AggregatorEth),
                wBTCAddress: address(wbtcMock),
                wBTCPriceFeedAddress: address(mockV3AggregatorBtc),
                deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
            });
    }
}
