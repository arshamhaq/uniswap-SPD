// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {ERC20SPD} from "@spd/ERC20SPD.sol";

import {RouterSPD} from "../../src/RouterSPD.sol";
import {SPD_USD_LP} from "../../src/SPD_USD_LP.sol";
import {MockUSD} from "../../src/tokens/MockUSD.sol";

abstract contract AMMTestBase is Test {
    uint256 internal constant INITIAL_SUPPLY = 10_000_000 ether;
    uint256 internal constant MAX_SUPPLY = 20_000_000 ether;

    address internal bob = makeAddr("bob");
    address internal charlie = makeAddr("charlie");
    address internal dave = makeAddr("dave");

    ERC20SPD internal spd;
    MockUSD internal usd;
    SPD_USD_LP internal pair;
    RouterSPD internal router;

    function setUp() public virtual {
        spd = new ERC20SPD(address(this), address(this), address(this), INITIAL_SUPPLY, MAX_SUPPLY);
        usd = new MockUSD();
        pair = new SPD_USD_LP(address(spd), address(usd));
        router = new RouterSPD(spd, usd, pair);

        assertTrue(spd.transfer(bob, 1_000_000 ether));
        assertTrue(spd.transfer(charlie, 1_000_000 ether));
        assertTrue(spd.transfer(dave, 1_000_000 ether));
        usd.mint(bob, 2_000_000 ether);
        usd.mint(charlie, 2_000_000 ether);
        usd.mint(dave, 2_000_000 ether);
    }

    function _approveRouter(address provider) internal {
        vm.startPrank(provider);
        spd.approve(address(router), type(uint256).max);
        usd.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    function _addLiquidity(address provider, uint256 spdAmount, uint256 usdAmount) internal returns (uint256 shares) {
        _approveRouter(provider);
        vm.prank(provider);
        shares = router.addLiquidity(spdAmount, usdAmount, 0, 0);
    }

    function _seedEqualPool() internal returns (uint256 shares) {
        shares = _addLiquidity(bob, 100_000 ether, 100_000 ether);
    }

    function _seedTwoToOnePool() internal returns (uint256 shares) {
        shares = _addLiquidity(bob, 100_000 ether, 200_000 ether);
    }
}
