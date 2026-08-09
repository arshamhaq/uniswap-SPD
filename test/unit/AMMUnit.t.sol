// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {RouterSPD} from "../../src/RouterSPD.sol";
import {SPD_USD_LP} from "../../src/SPD_USD_LP.sol";
import {MockUSD} from "../../src/tokens/MockUSD.sol";
import {AMMTestBase} from "../utils/AMMTestBase.sol";

contract AMMUnitTest is AMMTestBase {
    function testInitialLiquidityCreatesGeometricMeanShares() external {
        uint256 spdAmount = 100_000 ether;
        uint256 usdAmount = 200_000 ether;
        uint256 expectedShares = Math.sqrt(spdAmount * usdAmount);

        uint256 shares = _addLiquidity(bob, spdAmount, usdAmount);

        assertEq(shares, expectedShares);
        assertEq(pair.balanceOf(bob), expectedShares);
        assertEq(pair.totalSupply(), expectedShares);
        assertEq(pair.reserve0(), spdAmount);
        assertEq(pair.reserve1(), usdAmount);
    }

    function testSecondProviderReceivesProportionalShares() external {
        uint256 initialShares = _seedTwoToOnePool();
        uint256 expectedShares = pair.previewMint(10_000 ether, 20_000 ether);

        uint256 daveShares = _addLiquidity(dave, 10_000 ether, 20_000 ether);

        assertEq(daveShares, expectedShares);
        assertEq(daveShares, initialShares / 10);
        assertEq(pair.totalSupply(), initialShares + daveShares);
        assertEq(pair.reserve0(), 110_000 ether);
        assertEq(pair.reserve1(), 220_000 ether);
    }

    function testBadDepositRatioReverts() external {
        _seedTwoToOnePool();
        _approveRouter(dave);

        vm.prank(dave);
        vm.expectRevert(RouterSPD.InsufficientUsdAmount.selector);
        router.addLiquidity(10_000 ether, 19_999 ether, 0, 0);
    }

    function testRemovingHalfSharesReturnsHalfReserves() external {
        uint256 shares = _seedEqualPool();
        uint256 halfShares = shares / 2;

        vm.startPrank(bob);
        pair.approve(address(router), halfShares);
        (uint256 spdOut, uint256 usdOut) = router.removeLiquidity(halfShares, 50_000 ether, 50_000 ether);
        vm.stopPrank();

        assertEq(spdOut, 50_000 ether);
        assertEq(usdOut, 50_000 ether);
        assertEq(pair.reserve0(), 50_000 ether);
        assertEq(pair.reserve1(), 50_000 ether);
        assertEq(pair.totalSupply(), halfShares);
    }

    function testSpdToUsdSwapWorks() external {
        _seedEqualPool();
        _approveRouter(charlie);
        uint256 amountIn = 1_000 ether;
        uint256 expectedOut = router.getAmountOut(address(spd), amountIn);
        uint256 usdBefore = usd.balanceOf(charlie);

        vm.prank(charlie);
        uint256 amountOut = router.swapExactInput(address(spd), amountIn, expectedOut);

        assertEq(amountOut, expectedOut);
        assertEq(usd.balanceOf(charlie), usdBefore + amountOut);
        assertEq(pair.reserve0(), 100_000 ether + amountIn);
        assertEq(pair.reserve1(), 100_000 ether - amountOut);
    }

    function testUsdToSpdSwapWorks() external {
        _seedEqualPool();
        _approveRouter(charlie);
        uint256 amountIn = 1_000 ether;
        uint256 expectedOut = router.getAmountOut(address(usd), amountIn);
        uint256 spdBefore = spd.balanceOf(charlie);

        vm.prank(charlie);
        uint256 amountOut = router.swapExactInput(address(usd), amountIn, expectedOut);

        assertEq(amountOut, expectedOut);
        assertEq(spd.balanceOf(charlie), spdBefore + amountOut);
        assertEq(pair.reserve0(), 100_000 ether - amountOut);
        assertEq(pair.reserve1(), 100_000 ether + amountIn);
    }

    function testLargerTradesSufferMoreSlippage() external {
        _seedEqualPool();
        uint256 smallInput = 100 ether;
        uint256 largeInput = 10_000 ether;
        uint256 smallOutput = router.getAmountOut(address(spd), smallInput);
        uint256 largeOutput = router.getAmountOut(address(spd), largeInput);

        // Output per input is lower for the larger trade.
        assertLt(largeOutput * smallInput, smallOutput * largeInput);
    }

    function testSwapFeesRemainInPool() external {
        _seedEqualPool();
        _approveRouter(charlie);
        uint256 productBefore = uint256(pair.reserve0()) * pair.reserve1();

        vm.prank(charlie);
        router.swapExactInput(address(spd), 10_000 ether, 0);

        uint256 productAfter = uint256(pair.reserve0()) * pair.reserve1();
        assertGt(productAfter, productBefore);
    }

    function testMinAmountOutProtectsTraderAndRevertsAtomically() external {
        _seedEqualPool();
        _approveRouter(charlie);
        uint256 amountIn = 1_000 ether;
        uint256 quote = router.getAmountOut(address(spd), amountIn);
        uint256 spdBefore = spd.balanceOf(charlie);
        uint256 usdBefore = usd.balanceOf(charlie);
        uint112 reserve0Before = pair.reserve0();
        uint112 reserve1Before = pair.reserve1();

        vm.prank(charlie);
        vm.expectRevert(RouterSPD.SlippageExceeded.selector);
        router.swapExactInput(address(spd), amountIn, quote + 1);

        assertEq(spd.balanceOf(charlie), spdBefore);
        assertEq(usd.balanceOf(charlie), usdBefore);
        assertEq(pair.reserve0(), reserve0Before);
        assertEq(pair.reserve1(), reserve1Before);
    }

    function testUnsupportedTokenAddressReverts() external {
        _seedEqualPool();
        MockUSD unsupportedToken = new MockUSD();
        unsupportedToken.mint(charlie, 1_000 ether);

        vm.prank(charlie);
        vm.expectRevert(RouterSPD.InvalidToken.selector);
        router.swapExactInput(address(unsupportedToken), 1 ether, 0);
    }

    function testZeroAmountsRevert() external {
        vm.startPrank(bob);
        vm.expectRevert(RouterSPD.InvalidAmount.selector);
        router.addLiquidity(0, 1 ether, 0, 0);

        vm.expectRevert(RouterSPD.InvalidAmount.selector);
        router.removeLiquidity(0, 0, 0);

        vm.expectRevert(RouterSPD.InvalidAmount.selector);
        router.swapExactInput(address(spd), 0, 0);
        vm.stopPrank();
    }

    function testEmptyPoolSwapReverts() external {
        _approveRouter(charlie);

        vm.prank(charlie);
        vm.expectRevert(RouterSPD.InsufficientLiquidity.selector);
        router.swapExactInput(address(spd), 1 ether, 0);
    }

    function testOneLpCannotWithdrawAnotherLpsLiquidity() external {
        uint256 bobShares = _seedEqualPool();
        uint256 bobSpdBefore = spd.balanceOf(bob);
        uint256 bobUsdBefore = usd.balanceOf(bob);

        vm.prank(dave);
        vm.expectRevert(RouterSPD.InsufficientLiquidityShares.selector);
        router.removeLiquidity(bobShares / 2, 0, 0);

        assertEq(pair.balanceOf(bob), bobShares);
        assertEq(spd.balanceOf(bob), bobSpdBefore);
        assertEq(usd.balanceOf(bob), bobUsdBefore);
    }
}

contract ReentrantToken is ERC20 {
    RouterSPD private router;
    bool public armed;
    bool public reentryAttempted;
    bool public reentrySucceeded;

    constructor() ERC20("Reentrant Token", "REENT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function arm(RouterSPD router_) external {
        router = router_;
        armed = true;
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (armed && from != address(0) && msg.sender == address(router)) {
            armed = false;
            reentryAttempted = true;
            (reentrySucceeded,) =
                address(router).call(abi.encodeWithSelector(RouterSPD.addLiquidity.selector, 1 ether, 1 ether, 0, 0));
        }
        super._update(from, to, amount);
    }
}

contract AMMReentrancyTest is AMMTestBase {
    function testRouterRejectsReentrantLiquidityCall() external {
        ReentrantToken reentrantSpd = new ReentrantToken();
        MockUSD localUsd = new MockUSD();
        SPD_USD_LP localPair = new SPD_USD_LP(address(reentrantSpd), address(localUsd));
        RouterSPD localRouter = new RouterSPD(IERC20(address(reentrantSpd)), localUsd, localPair);

        reentrantSpd.mint(bob, 100 ether);
        localUsd.mint(bob, 100 ether);
        reentrantSpd.arm(localRouter);

        vm.startPrank(bob);
        reentrantSpd.approve(address(localRouter), 100 ether);
        localUsd.approve(address(localRouter), 100 ether);
        uint256 shares = localRouter.addLiquidity(100 ether, 100 ether, 100 ether, 0);
        vm.stopPrank();

        assertTrue(reentrantSpd.reentryAttempted());
        assertFalse(reentrantSpd.reentrySucceeded());
        assertEq(shares, 100 ether);
        assertEq(localPair.balanceOf(bob), shares);
    }
}
