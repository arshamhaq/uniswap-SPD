// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {ERC20SPD} from "@spd/ERC20SPD.sol";

import {RouterSPD} from "../src/RouterSPD.sol";
import {SPD_USD_LP} from "../src/SPD_USD_LP.sol";
import {MockUSD} from "../src/tokens/MockUSD.sol";

contract FullScenarioTest is Test {
    struct BurnSnapshot {
        uint256 bobShares;
        uint256 sharesToBurn;
        uint256 expectedSpdOut;
        uint256 expectedUsdOut;
        uint256 bobSpdBefore;
        uint256 bobUsdBefore;
        uint256 supplyBefore;
        uint256 reserve0Before;
        uint256 reserve1Before;
    }

    uint256 private constant INITIAL_SPD_SUPPLY = 1_000_000 ether;
    uint256 private constant MAX_SPD_SUPPLY = 2_000_000 ether;

    address private alice = makeAddr("alice");
    address private bob = makeAddr("bob");
    address private charlie = makeAddr("charlie");

    function testFullLiquidityAndSwapScenario() external {
        // Alice deploys the two tokens, the fixed Pair, and its Router.
        vm.startPrank(alice);
        ERC20SPD spd = new ERC20SPD(alice, alice, alice, INITIAL_SPD_SUPPLY, MAX_SPD_SUPPLY);
        MockUSD usd = new MockUSD();
        SPD_USD_LP pair = new SPD_USD_LP(address(spd), address(usd));
        RouterSPD router = new RouterSPD(spd, usd, pair);

        assertTrue(spd.transfer(bob, 100_000 ether));
        assertTrue(spd.transfer(charlie, 10_000 ether));
        usd.mint(bob, 200_000 ether);
        usd.mint(charlie, 20_000 ether);
        vm.stopPrank();

        assertEq(address(pair.token0()), address(spd));
        assertEq(address(pair.token1()), address(usd));
        assertEq(address(router.pair()), address(pair));
        assertEq(spd.balanceOf(bob), 100_000 ether);
        assertEq(usd.balanceOf(charlie), 20_000 ether);

        // Bob establishes a 1 SPD : 2 USD pool and receives all initial LP shares.
        {
            uint256 expectedShares = pair.previewMint(100_000 ether, 200_000 ether);
            assertGt(expectedShares, 0);

            vm.startPrank(bob);
            spd.approve(address(router), 100_000 ether);
            usd.approve(address(router), 200_000 ether);
            uint256 mintedShares = router.addLiquidity(100_000 ether, 200_000 ether, 200_000 ether, expectedShares);
            vm.stopPrank();

            assertEq(mintedShares, expectedShares);
            assertEq(pair.balanceOf(bob), mintedShares);
            assertEq(pair.totalSupply(), mintedShares);
            (uint256 reserve0, uint256 reserve1) = router.getReserves();
            assertEq(reserve0, 100_000 ether);
            assertEq(reserve1, 200_000 ether);
            assertEq(spd.balanceOf(address(pair)), reserve0);
            assertEq(usd.balanceOf(address(pair)), reserve1);
        }

        // Charlie swaps SPD for USD. The quote must match all observed balance changes.
        {
            (uint256 reserve0Before, uint256 reserve1Before) = router.getReserves();
            uint256 quotedOut = router.getAmountOut(address(spd), 1_000 ether);
            uint256 spdBefore = spd.balanceOf(charlie);
            uint256 usdBefore = usd.balanceOf(charlie);
            uint256 invariantBefore = reserve0Before * reserve1Before;

            vm.startPrank(charlie);
            spd.approve(address(router), type(uint256).max);
            usd.approve(address(router), type(uint256).max);
            uint256 actualOut = router.swapExactInput(address(spd), 1_000 ether, quotedOut);
            vm.stopPrank();

            assertEq(actualOut, quotedOut);
            assertEq(spd.balanceOf(charlie), spdBefore - 1_000 ether);
            assertEq(usd.balanceOf(charlie), usdBefore + actualOut);
            (uint256 reserve0After, uint256 reserve1After) = router.getReserves();
            assertEq(reserve0After, reserve0Before + 1_000 ether);
            assertEq(reserve1After, reserve1Before - actualOut);
            assertGe(reserve0After * reserve1After, invariantBefore);
        }

        // Charlie swaps USD back to SPD through the opposite reserve direction.
        {
            (uint256 reserve0Before, uint256 reserve1Before) = router.getReserves();
            uint256 quotedOut = router.getAmountOut(address(usd), 2_000 ether);
            uint256 spdBefore = spd.balanceOf(charlie);
            uint256 usdBefore = usd.balanceOf(charlie);
            uint256 invariantBefore = reserve0Before * reserve1Before;

            vm.prank(charlie);
            uint256 actualOut = router.swapExactInput(address(usd), 2_000 ether, quotedOut);

            assertEq(actualOut, quotedOut);
            assertEq(usd.balanceOf(charlie), usdBefore - 2_000 ether);
            assertEq(spd.balanceOf(charlie), spdBefore + actualOut);
            (uint256 reserve0After, uint256 reserve1After) = router.getReserves();
            assertEq(reserve0After, reserve0Before - actualOut);
            assertEq(reserve1After, reserve1Before + 2_000 ether);
            assertGe(reserve0After * reserve1After, invariantBefore);
        }

        // Bob burns half his position and receives exactly the current pro-rata preview.
        {
            BurnSnapshot memory snapshot;
            snapshot.bobShares = pair.balanceOf(bob);
            snapshot.sharesToBurn = snapshot.bobShares / 2;
            (snapshot.expectedSpdOut, snapshot.expectedUsdOut) = pair.previewBurn(snapshot.sharesToBurn);
            snapshot.bobSpdBefore = spd.balanceOf(bob);
            snapshot.bobUsdBefore = usd.balanceOf(bob);
            snapshot.supplyBefore = pair.totalSupply();
            (snapshot.reserve0Before, snapshot.reserve1Before) = router.getReserves();

            vm.startPrank(bob);
            pair.approve(address(router), snapshot.sharesToBurn);
            (uint256 spdOut, uint256 usdOut) =
                router.removeLiquidity(snapshot.sharesToBurn, snapshot.expectedSpdOut, snapshot.expectedUsdOut);
            vm.stopPrank();

            assertEq(spdOut, snapshot.expectedSpdOut);
            assertEq(usdOut, snapshot.expectedUsdOut);
            assertEq(spd.balanceOf(bob), snapshot.bobSpdBefore + spdOut);
            assertEq(usd.balanceOf(bob), snapshot.bobUsdBefore + usdOut);
            assertEq(pair.balanceOf(bob), snapshot.bobShares - snapshot.sharesToBurn);
            assertEq(pair.balanceOf(address(pair)), 0);
            assertEq(pair.totalSupply(), snapshot.supplyBefore - snapshot.sharesToBurn);

            (uint256 reserve0After, uint256 reserve1After) = router.getReserves();
            assertEq(reserve0After, snapshot.reserve0Before - spdOut);
            assertEq(reserve1After, snapshot.reserve1Before - usdOut);
            assertEq(spd.balanceOf(address(pair)), reserve0After);
            assertEq(usd.balanceOf(address(pair)), reserve1After);
        }
    }
}
