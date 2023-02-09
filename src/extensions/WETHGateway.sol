// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IWETH} from "../interfaces/IWETH.sol";
import {IMorpho} from "../interfaces/IMorpho.sol";

import {SafeTransferLib, ERC20} from "@solmate/utils/SafeTransferLib.sol";

contract WETHGateway {
    using SafeTransferLib for ERC20;

    error OnlyWETH();

    address internal constant _WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    IMorpho internal immutable _morpho;

    constructor(address morpho) {
        _morpho = IMorpho(morpho);
        ERC20(_WETH).safeApprove(morpho, type(uint256).max);
    }

    function WETH() external pure returns (address) {
        return _WETH;
    }

    function morpho() external view returns (IMorpho) {
        return _morpho;
    }

    function supplyETH(address onBehalf, uint256 maxIterations) external payable {
        IWETH(_WETH).deposit{value: msg.value}();
        _morpho.supply(_WETH, msg.value, onBehalf, maxIterations);
    }

    function supplyCollateralETH(address onBehalf) external payable {
        IWETH(_WETH).deposit{value: msg.value}();
        _morpho.supplyCollateral(_WETH, msg.value, onBehalf);
    }

    function borrowETH(uint256 amount, uint256 maxIterations) external {
        _morpho.borrow(_WETH, amount, msg.sender, maxIterations);
        IWETH(_WETH).withdraw(amount);
        SafeTransferLib.safeTransferETH(msg.sender, amount);
    }

    function repayETH(address onBehalf) external payable {
        IWETH(_WETH).deposit{value: msg.value}();
        _morpho.repay(_WETH, msg.value, onBehalf);
    }

    function withdrawETH(uint256 amount) external {
        _morpho.withdraw(_WETH, amount, msg.sender);
        IWETH(_WETH).withdraw(amount);
        SafeTransferLib.safeTransferETH(msg.sender, amount);
    }

    function withdrawCollateralETH(uint256 amount) external {
        _morpho.withdrawCollateral(_WETH, amount, msg.sender);
        IWETH(_WETH).withdraw(amount);
        SafeTransferLib.safeTransferETH(msg.sender, amount);
    }

    receive() external payable {
        if (msg.sender != _WETH) revert OnlyWETH();
    }
}
