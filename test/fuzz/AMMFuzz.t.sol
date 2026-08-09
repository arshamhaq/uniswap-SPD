// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {AMMTestBase} from "../utils/AMMTestBase.sol";

contract AMMFuzzTest is AMMTestBase {
    function testFuzz_InitialLiquidityShares(uint96 rawSpdAmount, uint96 rawUsdAmount) external {
        uint256 spdAmount = bound(uint256(rawSpdAmount), 1 ether, 500_000 ether);
        uint256 usdAmount = bound(uint256(rawUsdAmount), 1 ether, 1_000_000 ether);
        uint256 expectedShares = Math.sqrt(spdAmount * usdAmount);

        uint256 shares = _addLiquidity(bob, spdAmount, usdAmount);

        assertEq(shares, expectedShares);
        assertEq(pair.totalSupply(), expectedShares);
        assertEq(pair.reserve0(), spdAmount);
        assertEq(pair.reserve1(), usdAmount);
    }

    function testFuzz_SecondProviderReceivesProportionalShares(uint96 rawSpdAmount) external {
        uint256 initialShares = _seedTwoToOnePool();
        uint256 spdAmount = bound(uint256(rawSpdAmount), 1 ether, 100_000 ether);
        uint256 usdAmount = spdAmount * 2;
        uint256 expectedShares = Math.mulDiv(spdAmount, initialShares, 100_000 ether);

        uint256 shares = _addLiquidity(dave, spdAmount, usdAmount);

        assertEq(shares, expectedShares);
        assertEq(pair.balanceOf(dave), expectedShares);
        assertEq(pair.totalSupply(), initialShares + expectedShares);
    }

    function testFuzz_SwapMaintainsBalancesAndProduct(uint96 rawAmountIn, bool spdToUsd) external {
        _seedEqualPool();
        _approveRouter(charlie);
        uint256 amountIn = bound(uint256(rawAmountIn), 1 ether, 50_000 ether);
        address tokenIn = spdToUsd ? address(spd) : address(usd);
        uint256 productBefore = uint256(pair.reserve0()) * pair.reserve1();

        vm.prank(charlie);
        uint256 amountOut = router.swapExactInput(tokenIn, amountIn, 0);

        assertGt(amountOut, 0);
        assertEq(pair.reserve0(), spd.balanceOf(address(pair)));
        assertEq(pair.reserve1(), usd.balanceOf(address(pair)));
        assertGe(uint256(pair.reserve0()) * pair.reserve1(), productBefore);
    }

    function testFuzz_RemoveLiquidityIsProRata(uint96 rawShares) external {
        uint256 totalShares = _seedEqualPool();
        uint256 shares = bound(uint256(rawShares), 1, totalShares);
        (uint256 expectedSpdOut, uint256 expectedUsdOut) = pair.previewBurn(shares);

        vm.startPrank(bob);
        pair.approve(address(router), shares);
        (uint256 spdOut, uint256 usdOut) = router.removeLiquidity(shares, expectedSpdOut, expectedUsdOut);
        vm.stopPrank();

        assertEq(spdOut, expectedSpdOut);
        assertEq(usdOut, expectedUsdOut);
        assertEq(pair.totalSupply(), totalShares - shares);
        assertEq(pair.reserve0(), spd.balanceOf(address(pair)));
        assertEq(pair.reserve1(), usd.balanceOf(address(pair)));
    }
}
