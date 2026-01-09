// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {LendleYieldVault} from "../src/yield/LendleYieldVault.sol";
import {ILendlePool} from "../src/interfaces/ILendlePool.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockLendlePool} from "../src/mocks/MockLendlePool.sol";
import {MockAToken} from "../src/mocks/MockAToken.sol";

contract LendleYieldVaultMockedTest is Test {
    MockERC20 internal usdc;
    MockLendlePool internal pool;
    MockAToken internal aUSDC;
    LendleYieldVault internal vault;

    address internal user = address(0xA11CE);

    function setUp() public {
        usdc = new MockERC20("USDC", "USDC", 6);
        pool = new MockLendlePool();
        aUSDC = new MockAToken(usdc, address(pool), "Aave USDC", "aUSDC");

        pool.initReserve(address(usdc), address(aUSDC), 0.12e27);
        aUSDC.setSupplyAPY(0.12e27);

        vault = new LendleYieldVault(usdc, ILendlePool(address(pool)), aUSDC, "Welot USDC Vault", "wUSDC");

        usdc.mint(user, 1_000e6);
        vm.prank(user);
        usdc.approve(address(vault), type(uint256).max);
    }

    function test_Deposit_mintsShares_and_suppliesToPool() public {
        uint256 amount = 100e6;

        vm.prank(user);
        uint256 shares = vault.deposit(amount, user);

        assertGt(shares, 0);
        assertEq(vault.balanceOf(user), shares);
        assertEq(vault.totalAssets(), amount);
        assertEq(usdc.balanceOf(address(aUSDC)), amount);
        assertEq(aUSDC.balanceOf(address(vault)), amount);
    }

    function test_Withdraw_returnsUnderlying_and_burnsShares() public {
        uint256 amount = 200e6;

        vm.startPrank(user);
        uint256 shares = vault.deposit(amount, user);

        uint256 before = usdc.balanceOf(user);
        uint256 sharesBefore = vault.balanceOf(user);

        vault.withdraw(50e6, user, user);

        uint256 afterBal = usdc.balanceOf(user);
        assertEq(afterBal - before, 50e6);
        assertLt(vault.balanceOf(user), sharesBefore);
        assertLt(vault.totalSupply(), shares);
        assertEq(vault.totalAssets(), amount - 50e6);
        vm.stopPrank();
    }

    function test_YieldAccrual_increasesTotalAssets() public {
        uint256 amount = 100e6;

        vm.prank(user);
        vault.deposit(amount, user);

        uint256 beforeAssets = vault.totalAssets();

        vm.warp(block.timestamp + 30 days);
        pool.simulateYieldAccrual(address(usdc));

        uint256 afterAssets = vault.totalAssets();
        assertGt(afterAssets, beforeAssets);
    }
}
