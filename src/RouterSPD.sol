// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ISPD_USD_LP} from "./interfaces/ISPD_USD_LP.sol";
import {IRouterSPD} from "./interfaces/IRouterSPD.sol";

/// @notice Router for adding liquidity, removing liquidity, and swapping through the fixed SPD/USD Pair.
contract RouterSPD is IRouterSPD, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant FEE_DENOMINATOR = 1_000;
    uint256 private constant FEE_NUMERATOR = 997;
    uint256 private constant MAX_RESERVE = type(uint112).max;

    error ZeroAddress();
    error IdenticalTokens();
    error PairTokenMismatch();
    error InvalidAmount();
    error InvalidToken();
    error SlippageExceeded();
    error InvalidReserveState();
    error InsufficientUsdAmount();
    error InsufficientLiquidity();
    error InsufficientLiquidityShares();

    IERC20 public immutable override spd;
    IERC20 public immutable override usd;
    ISPD_USD_LP public immutable override pair;

    constructor(IERC20 spd_, IERC20 usd_, ISPD_USD_LP pair_) {
        if (address(spd_) == address(0) || address(usd_) == address(0) || address(pair_) == address(0)) {
            revert ZeroAddress();
        }
        if (address(spd_) == address(usd_)) revert IdenticalTokens();
        if (address(pair_.token0()) != address(spd_) || address(pair_.token1()) != address(usd_)) {
            revert PairTokenMismatch();
        }

        spd = spd_;
        usd = usd_;
        pair = pair_;
    }

    /// @notice Deposits an exact SPD amount and the reserve-matched USD amount.
    /// @param spdAmount Exact SPD amount to deposit.
    /// @param usdAmount Maximum USD amount the caller permits the Router to deposit.
    /// @param minUsdAmount Minimum USD amount the caller permits the Router to deposit.
    /// @param minShares Minimum acceptable LP shares minted to the caller.
    function addLiquidity(uint256 spdAmount, uint256 usdAmount, uint256 minUsdAmount, uint256 minShares)
        external
        override
        nonReentrant
        returns (uint256 shares)
    {
        if (spdAmount == 0 || usdAmount == 0 || minUsdAmount > usdAmount) revert InvalidAmount();

        (uint112 spdReserve, uint112 usdReserve) = pair.getReserves();
        uint256 usdAmountToDeposit;

        if (spdReserve == 0 && usdReserve == 0) {
            usdAmountToDeposit = usdAmount;
        } else {
            if (spdReserve == 0 || usdReserve == 0) revert InvalidReserveState();

            usdAmountToDeposit = Math.mulDiv(spdAmount, usdReserve, spdReserve);
            if (usdAmountToDeposit == 0) revert InvalidAmount();
        }

        if (usdAmountToDeposit > usdAmount) revert InsufficientUsdAmount();
        if (usdAmountToDeposit < minUsdAmount) revert SlippageExceeded();

        uint256 expectedShares = pair.previewMint(spdAmount, usdAmountToDeposit);
        if (expectedShares < minShares) revert InsufficientLiquidity();

        spd.safeTransferFrom(msg.sender, address(pair), spdAmount);
        usd.safeTransferFrom(msg.sender, address(pair), usdAmountToDeposit);

        shares = pair.mint(msg.sender);
        // The preview saves gas on an obviously failing request; the actual result remains authoritative.
        if (shares < minShares) revert InsufficientLiquidity();
    }

    /// @notice Burns LP shares and returns the caller's proportional SPD and USD.
    function removeLiquidity(uint256 shares, uint256 minSpdOut, uint256 minUsdOut)
        external
        override
        nonReentrant
        returns (uint256 spdOut, uint256 usdOut)
    {
        if (shares == 0) revert InvalidAmount();
        if (shares > pair.balanceOf(msg.sender)) revert InsufficientLiquidityShares();

        (uint256 expectedSpdOut, uint256 expectedUsdOut) = pair.previewBurn(shares);
        if (expectedSpdOut < minSpdOut || expectedUsdOut < minUsdOut) revert SlippageExceeded();

        IERC20(address(pair)).safeTransferFrom(msg.sender, address(pair), shares);
        (spdOut, usdOut) = pair.burn(msg.sender);

        // Actual Pair balances are authoritative if they differ from the preview.
        if (spdOut < minSpdOut || usdOut < minUsdOut) revert SlippageExceeded();
    }

    /// @notice Swaps an exact SPD or USD input for the other token.
    function swapExactInput(address tokenIn, uint256 amountIn, uint256 minAmountOut)
        external
        override
        nonReentrant
        returns (uint256 amountOut)
    {
        if (tokenIn != address(spd) && tokenIn != address(usd)) revert InvalidToken();
        if (amountIn == 0) revert InvalidAmount();

        amountOut = getAmountOut(tokenIn, amountIn);
        if (amountOut < minAmountOut) revert SlippageExceeded();

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(pair), amountIn);
        if (tokenIn == address(spd)) {
            pair.swap(0, amountOut, msg.sender);
        } else {
            pair.swap(amountOut, 0, msg.sender);
        }
    }

    /// @notice Quotes output for a 0.3% fee-adjusted exact-input swap.
    function getAmountOut(address tokenIn, uint256 amountIn) public view override returns (uint256 amountOut) {
        if (tokenIn != address(spd) && tokenIn != address(usd)) revert InvalidToken();
        if (amountIn == 0) revert InvalidAmount();

        uint256 reserveIn;
        uint256 reserveOut;
        if (tokenIn == address(spd)) {
            reserveIn = pair.reserve0();
            reserveOut = pair.reserve1();
        } else {
            reserveIn = pair.reserve1();
            reserveOut = pair.reserve0();
        }
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        if (amountIn > MAX_RESERVE - reserveIn) revert InvalidAmount();

        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;
        amountOut = Math.mulDiv(amountInWithFee, reserveOut, (reserveIn * FEE_DENOMINATOR) + amountInWithFee);
        if (amountOut == 0) revert InsufficientLiquidity();
    }

    /// @notice Returns reserves in fixed SPD/USD order.
    function getReserves() external view override returns (uint256 spdReserve, uint256 usdReserve) {
        (uint112 reserve0_, uint112 reserve1_) = pair.getReserves();
        spdReserve = reserve0_;
        usdReserve = reserve1_;
    }
}
