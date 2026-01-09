// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockLendlePool} from "../src/mocks/MockLendlePool.sol";
import {MockAToken} from "../src/mocks/MockAToken.sol";

contract MocksLendlePoolATokenTest is Test {
    MockERC20 internal usdc;
    MockLendlePool internal pool;
    MockAToken internal aUSDC;

    address internal user = address(0xBEEF);

    function setUp() public {
        usdc = new MockERC20("USDC", "USDC", 6);
        pool = new MockLendlePool();
        aUSDC = new MockAToken(usdc, address(pool), "Aave USDC", "aUSDC");

        pool.initReserve(address(usdc), address(aUSDC), 0.12e27);
        aUSDC.setSupplyAPY(0.12e27);

        usdc.mint(user, 1_000e6);
        vm.prank(user);
        usdc.approve(address(pool), type(uint256).max);
    }

    function test_MockAToken_onlyPool_reverts() public {
        vm.expectRevert(MockAToken.MockAToken__OnlyPool.selector);
        aUSDC.mint(user, 1e6);
    }

    function test_Supply_mintsATokens_and_movesUnderlying() public {
        uint256 amount = 100e6;

        vm.prank(user);
        pool.supply(address(usdc), amount, user, 0);

        assertEq(aUSDC.balanceOf(user), amount);
        assertEq(usdc.balanceOf(address(aUSDC)), amount);
        assertEq(usdc.balanceOf(user), 900e6);
    }

    function test_Withdraw_burnsATokens_and_returnsUnderlying() public {
        uint256 amount = 250e6;

        vm.prank(user);
        pool.supply(address(usdc), amount, user, 0);

        vm.prank(user);
        uint256 withdrawn = pool.withdraw(address(usdc), 100e6, user);

        assertEq(withdrawn, 100e6);
        assertEq(usdc.balanceOf(user), 850e6); // 1000 - 250 + 100
        assertEq(aUSDC.balanceOf(user), 150e6);
        assertEq(usdc.balanceOf(address(aUSDC)), 150e6);
    }

    function test_YieldAccrual_increasesATokenBalance_andUnderlyingBacksIt() public {
        uint256 amount = 100e6;

        vm.prank(user);
        pool.supply(address(usdc), amount, user, 0);

        uint256 beforeBal = aUSDC.balanceOf(user);
        uint256 beforeUnderlying = usdc.balanceOf(address(aUSDC));

        vm.warp(block.timestamp + 30 days);
        pool.simulateYieldAccrual(address(usdc));

        uint256 afterBal = aUSDC.balanceOf(user);
        uint256 afterUnderlying = usdc.balanceOf(address(aUSDC));

        assertGt(afterBal, beforeBal);
        assertGe(afterUnderlying, afterBal);
        assertGt(afterUnderlying, beforeUnderlying);
    }
}
