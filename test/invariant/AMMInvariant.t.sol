// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {RouterSPD} from "../../src/RouterSPD.sol";
import {SPD_USD_LP} from "../../src/SPD_USD_LP.sol";
import {AMMTestBase} from "../utils/AMMTestBase.sol";

contract SwapHandler {
    RouterSPD public immutable router;
    SPD_USD_LP public immutable pair;
    IERC20 public immutable spd;
    IERC20 public immutable usd;

    bool public productDecreased;
    uint256 public successfulSwaps;

    constructor(RouterSPD router_, SPD_USD_LP pair_, IERC20 spd_, IERC20 usd_) {
        router = router_;
        pair = pair_;
        spd = spd_;
        usd = usd_;

        require(spd_.approve(address(router_), type(uint256).max));
        require(usd_.approve(address(router_), type(uint256).max));
    }

    function swapSpdForUsd(uint256 seed) external {
        _swap(address(spd), seed);
    }

    function swapUsdForSpd(uint256 seed) external {
        _swap(address(usd), seed);
    }

    function _swap(address tokenIn, uint256 seed) private {
        uint256 tokenBalance = IERC20(tokenIn).balanceOf(address(this));
        uint256 reserveIn = tokenIn == address(spd) ? pair.reserve0() : pair.reserve1();
        uint256 maxAmount = tokenBalance < reserveIn / 5 ? tokenBalance : reserveIn / 5;
        if (maxAmount == 0) return;

        uint256 amountIn = (seed % maxAmount) + 1;
        uint256 productBefore = uint256(pair.reserve0()) * pair.reserve1();

        try router.swapExactInput(tokenIn, amountIn, 0) returns (uint256 amountOut) {
            if (amountOut == 0) return;
            successfulSwaps++;

            uint256 productAfter = uint256(pair.reserve0()) * pair.reserve1();
            if (productAfter < productBefore) productDecreased = true;
        } catch {}
    }
}

contract AMMInvariantTest is AMMTestBase {
    SwapHandler internal handler;

    function setUp() public override {
        super.setUp();
        _seedEqualPool();

        handler = new SwapHandler(router, pair, spd, usd);
        assertTrue(spd.transfer(address(handler), 500_000 ether));
        usd.mint(address(handler), 500_000 ether);

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = SwapHandler.swapSpdForUsd.selector;
        selectors[1] = SwapHandler.swapUsdForSpd.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_RecordedReservesEqualActualBalances() external view {
        assertEq(pair.reserve0(), spd.balanceOf(address(pair)));
        assertEq(pair.reserve1(), usd.balanceOf(address(pair)));
    }

    function invariant_SuccessfulFeeAdjustedSwapDoesNotDecreaseProduct() external view {
        assertFalse(handler.productDecreased());
    }
}
