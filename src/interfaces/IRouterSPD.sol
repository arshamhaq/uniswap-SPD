// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ISPD_USD_LP} from "./ISPD_USD_LP.sol";

interface IRouterSPD {
    function spd() external view returns (IERC20);
    function usd() external view returns (IERC20);
    function pair() external view returns (ISPD_USD_LP);

    function addLiquidity(uint256 spdAmount, uint256 usdAmount, uint256 minUsdAmount, uint256 minShares)
        external
        returns (uint256 shares);

    function removeLiquidity(uint256 shares, uint256 minSpdOut, uint256 minUsdOut)
        external
        returns (uint256 spdOut, uint256 usdOut);

    function swapExactInput(address tokenIn, uint256 amountIn, uint256 minAmountOut)
        external
        returns (uint256 amountOut);

    function getAmountOut(address tokenIn, uint256 amountIn) external view returns (uint256 amountOut);
    function getReserves() external view returns (uint256 spdReserve, uint256 usdReserve);
}
