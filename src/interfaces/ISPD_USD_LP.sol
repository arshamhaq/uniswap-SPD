// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISPD_USD_LP is IERC20 {
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function token0() external view returns (IERC20);
    function token1() external view returns (IERC20);
    function reserve0() external view returns (uint112);
    function reserve1() external view returns (uint112);

    function getReserves() external view returns (uint112 spdReserve, uint112 usdReserve);
    function previewMint(uint256 spdAmount, uint256 usdAmount) external view returns (uint256 shares);
    function previewBurn(uint256 shares) external view returns (uint256 spdOut, uint256 usdOut);

    /// @notice Mints shares from token balances already transferred above the stored reserves.
    /// @dev Unclaimed excess balances can be minted by any caller, so transfer and mint atomically.
    function mint(address to) external returns (uint256 shares);

    /// @notice Burns all LP tokens already transferred to the Pair and sends both assets to `to`.
    /// @dev Unclaimed LP tokens held by the Pair can be burned by any caller, so transfer and burn atomically.
    function burn(address to) external returns (uint256 amount0, uint256 amount1);

    /// @notice Sends one output token after input tokens have already been transferred to the Pair.
    function swap(uint256 amount0Out, uint256 amount1Out, address to) external;
}
