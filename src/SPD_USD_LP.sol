// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {ISPD_USD_LP} from "./interfaces/ISPD_USD_LP.sol";

/// @notice Fixed SPD/USD constant-product pair whose ERC20 token represents LP ownership.
contract SPD_USD_LP is ERC20, ReentrancyGuard, ISPD_USD_LP {
    using SafeERC20 for IERC20;

    uint256 private constant FEE_DENOMINATOR = 1_000;
    uint256 private constant FEE_NUMERATOR = 997;
    uint256 private constant MAX_RESERVE = type(uint112).max;

    error ZeroAddress();
    error IdenticalTokens();
    error InvalidRecipient();
    error InvalidOutputAmount();
    error InvalidLiquidity();
    error InvalidBurnAmount();
    error InvalidReserveState();
    error InsufficientInputAmount();
    error InsufficientLiquidity();
    error ReserveOverflow();

    IERC20 public immutable override token0;
    IERC20 public immutable override token1;

    uint112 public override reserve0;
    uint112 public override reserve1;

    constructor(address spd_, address usd_) ERC20("SPD-USD-LP", "SPD-USD-LP") {
        if (spd_ == address(0) || usd_ == address(0)) revert ZeroAddress();
        if (spd_ == usd_) revert IdenticalTokens();

        token0 = IERC20(spd_);
        token1 = IERC20(usd_);
    }

    /// @inheritdoc ISPD_USD_LP
    function getReserves() external view override returns (uint112 spdReserve, uint112 usdReserve) {
        spdReserve = reserve0;
        usdReserve = reserve1;
    }

    /// @inheritdoc ISPD_USD_LP
    function previewMint(uint256 spdAmount, uint256 usdAmount) public view override returns (uint256 shares) {
        if (spdAmount == 0 || usdAmount == 0) return 0;
        _validateReserveBounds(spdAmount, usdAmount);

        uint256 currentSupply = totalSupply();
        if (currentSupply == 0) return Math.sqrt(spdAmount * usdAmount);
        if (reserve0 == 0 || reserve1 == 0) return 0;

        uint256 spdShares = Math.mulDiv(spdAmount, currentSupply, reserve0);
        uint256 usdShares = Math.mulDiv(usdAmount, currentSupply, reserve1);
        return Math.min(spdShares, usdShares);
    }

    /// @inheritdoc ISPD_USD_LP
    function previewBurn(uint256 shares) public view override returns (uint256 spdOut, uint256 usdOut) {
        uint256 currentSupply = totalSupply();
        if (shares == 0 || currentSupply == 0) return (0, 0);
        if (shares > currentSupply) revert InvalidBurnAmount();

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        _validateReserveBounds(balance0, balance1);

        spdOut = Math.mulDiv(shares, balance0, currentSupply);
        usdOut = Math.mulDiv(shares, balance1, currentSupply);
    }

    /// @inheritdoc ISPD_USD_LP
    function mint(address to) external override nonReentrant returns (uint256 shares) {
        if (to == address(0)) revert InvalidRecipient();

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        _validateReserveBounds(balance0, balance1);
        if (balance0 < reserve0 || balance1 < reserve1) revert InvalidReserveState();

        uint256 amount0 = balance0 - reserve0;
        uint256 amount1 = balance1 - reserve1;
        if (amount0 == 0 || amount1 == 0) revert InvalidLiquidity();

        shares = previewMint(amount0, amount1);
        if (shares == 0) revert InvalidLiquidity();

        _mint(to, shares);
        _updateReserves(balance0, balance1);
        emit Mint(msg.sender, amount0, amount1);
    }

    /// @inheritdoc ISPD_USD_LP
    function burn(address to) external override nonReentrant returns (uint256 amount0, uint256 amount1) {
        if (to == address(0)) revert InvalidRecipient();

        uint256 shares = balanceOf(address(this));
        if (shares == 0) revert InvalidBurnAmount();

        (amount0, amount1) = previewBurn(shares);
        if (amount0 == 0 || amount1 == 0) revert InvalidOutputAmount();

        _burn(address(this), shares);
        token0.safeTransfer(to, amount0);
        token1.safeTransfer(to, amount1);

        _updateReserves(token0.balanceOf(address(this)), token1.balanceOf(address(this)));
        emit Burn(msg.sender, amount0, amount1, to);
    }

    /// @inheritdoc ISPD_USD_LP
    function swap(uint256 amount0Out, uint256 amount1Out, address to) external override nonReentrant {
        if (to == address(0) || to == address(token0) || to == address(token1)) revert InvalidRecipient();
        if ((amount0Out == 0 && amount1Out == 0) || (amount0Out != 0 && amount1Out != 0)) {
            revert InvalidOutputAmount();
        }

        uint112 reserve0Before = reserve0;
        uint112 reserve1Before = reserve1;
        if (amount0Out >= reserve0Before || amount1Out >= reserve1Before) revert InsufficientLiquidity();

        if (amount0Out != 0) token0.safeTransfer(to, amount0Out);
        if (amount1Out != 0) token1.safeTransfer(to, amount1Out);

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        _validateReserveBounds(balance0, balance1);

        uint256 amount0In;
        uint256 amount1In;
        uint256 expectedAmountOut;

        if (amount0Out != 0) {
            // USD (token1) came in and SPD (token0) went out.
            if (balance1 <= reserve1Before) revert InsufficientInputAmount();
            amount1In = balance1 - reserve1Before;
            expectedAmountOut = _getAmountOut(reserve1Before, reserve0Before, amount1In);
            if (amount0Out > expectedAmountOut) revert InvalidOutputAmount();
        } else {
            // SPD (token0) came in and USD (token1) went out.
            if (balance0 <= reserve0Before) revert InsufficientInputAmount();
            amount0In = balance0 - reserve0Before;
            expectedAmountOut = _getAmountOut(reserve0Before, reserve1Before, amount0In);
            if (amount1Out > expectedAmountOut) revert InvalidOutputAmount();
        }

        _updateReserves(balance0, balance1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function _getAmountOut(uint256 reserveIn, uint256 reserveOut, uint256 amountIn)
        private
        pure
        returns (uint256 amountOut)
    {
        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;
        amountOut = Math.mulDiv(amountInWithFee, reserveOut, (reserveIn * FEE_DENOMINATOR) + amountInWithFee);
    }

    function _updateReserves(uint256 balance0, uint256 balance1) private {
        _validateReserveBounds(balance0, balance1);
        reserve0 = SafeCast.toUint112(balance0);
        reserve1 = SafeCast.toUint112(balance1);
        emit Sync(reserve0, reserve1);
    }

    function _validateReserveBounds(uint256 balance0, uint256 balance1) private pure {
        if (balance0 > MAX_RESERVE || balance1 > MAX_RESERVE) revert ReserveOverflow();
    }
}
