// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzepplin/contracts/mocks/ERC20Mock.sol";

contract Handler is Test {
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint256 public mintCalled;
    uint256 public mintCalled1;
    uint256 public mintCalled2;
    uint256 public mintCalled4;
    address[] public s_depositors;
    uint256 MAX_COLLETRAL_DEPOSIT = type(uint96).max;

    constructor(DecentralizedStableCoin _dsc, DSCEngine _dscEngine) {
        dsc = _dsc;
        dscEngine = _dscEngine;
        address[] memory colletralArray = dscEngine.getAllowedColletrals();
        weth = ERC20Mock(colletralArray[0]);

        wbtc = ERC20Mock(colletralArray[1]);
    }

    function depositColletral(
        uint256 colletralSeed,
        uint256 colleteralAmount
    ) external {
        ERC20Mock colleteral = _getColletralFromSeed(colletralSeed);
        colleteralAmount = bound(colleteralAmount, 1, MAX_COLLETRAL_DEPOSIT);
        vm.startPrank(msg.sender);
        colleteral.mint(msg.sender, colleteralAmount);
        colleteral.approve(address(dscEngine), colleteralAmount);
        dscEngine.depositCollateral(address(colleteral), colleteralAmount);
        s_depositors.push(msg.sender);
        vm.stopPrank();
    }

    function redeemColleteral(
        uint256 colletralSeed,
        uint256 colleteralAmount
    ) external {
        vm.startPrank(msg.sender);
        ERC20Mock colleteral = _getColletralFromSeed(colletralSeed);
        uint256 max_redeem_Colleteral = dscEngine.getColletralValueOfaUser(
            msg.sender,
            address(colleteral)
        );
        uint256 boundColletralAmount = bound(
            colleteralAmount,
            0,
            max_redeem_Colleteral
        );
        if (boundColletralAmount == 0) return;
        if (dscEngine.getHealthFactor(msg.sender) >= 1e18) return;
        console.log("user Balance", max_redeem_Colleteral);
        console.log("bound Amount", boundColletralAmount);

        dscEngine.redeemCollateral(address(colleteral), boundColletralAmount);
        vm.stopPrank();
    }

    function mintDSC(uint256 dscAmount, uint256 senderAddressSeed) external {
        if (s_depositors.length == 0) return;
        address sender = s_depositors[senderAddressSeed % s_depositors.length];

        vm.startPrank(sender);

        (uint256 dscMinted, uint256 totalColleteralValueInUSD) = dscEngine
            .getAccountInformation(sender);
        mintCalled1++;
        uint256 dscCanBeMinted = (totalColleteralValueInUSD / 2) - dscMinted;
        mintCalled2++;
        dscAmount = bound(dscAmount, 0, dscCanBeMinted);
        mintCalled++;
        if (dscAmount == 0) return;
        dscEngine.mintDSC(dscAmount);
    }

    function _getColletralFromSeed(
        uint256 seed
    ) private view returns (ERC20Mock) {
        if (seed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
