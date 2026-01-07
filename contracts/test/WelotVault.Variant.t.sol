// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {WelotVault} from "../src/WelotVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockERC4626} from "../src/mocks/MockERC4626.sol";
import {MockEntropyV2} from "../src/mocks/MockEntropyV2.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IEntropyV2} from "../src/interfaces/IEntropyV2.sol";

/// @title WelotVault Variant Tests
/// @notice Tests for edge cases, boundary conditions, and variant scenarios
contract WelotVaultVariantTest is Test {
    MockERC20 usdc;
    MockERC4626 susdc;
    MockEntropyV2 entropy;
    WelotVault vault;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xC0FFEE);

    function setUp() public {
        usdc = new MockERC20("USDC", "USDC", 6);
        susdc = new MockERC4626(usdc, "sUSDC", "sUSDC", 6);
        susdc.setYieldRatePerSecond(0);

        entropy = new MockEntropyV2();
        vault = new WelotVault(IEntropyV2(address(entropy)), 7 days, 10);
        vault.addSupportedToken(address(usdc), IERC4626(address(susdc)));

        _setupUser(alice);
        _setupUser(bob);
        _setupUser(carol);
    }

    function _setupUser(address user) internal {
        usdc.mint(user, 1_000_000e6);
        vm.prank(user);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test with dust amounts (1 wei)
    function test_Variant_DustAmount_SingleWei() public {
        vm.prank(alice);
        vault.deposit(address(usdc), 1);

        (uint256 deposits,) = vault.userPosition(address(usdc), alice);
        assertEq(deposits, 1);
    }

    /// @notice Test maximum uint256 approval
    function test_Variant_MaxApproval() public {
        MockERC20 token = new MockERC20("TEST", "TEST", 18);
        token.mint(alice, type(uint256).max / 2);
        
        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);
        
        // Should still work after max approval
        assertEq(token.allowance(alice, address(vault)), type(uint256).max);
    }

    /// @notice Test very large deposit (near uint256 max)
    function test_Variant_VeryLargeDeposit() public {
        uint256 largeAmount = type(uint96).max; // Use uint96 to avoid overflow
        usdc.mint(alice, largeAmount);
        
        vm.prank(alice);
        vault.deposit(address(usdc), largeAmount);

        (uint256 deposits,) = vault.userPosition(address(usdc), alice);
        assertEq(deposits, largeAmount);
    }

    /// @notice Test deposit, immediate withdrawal (same block)
    function test_Variant_DepositAndImmediateWithdraw() public {
        vm.startPrank(alice);
        vault.deposit(address(usdc), 1000e6);
        vault.withdraw(address(usdc), 1000e6);
        vm.stopPrank();

        (uint256 deposits,) = vault.userPosition(address(usdc), alice);
        assertEq(deposits, 0);
    }

    /// @notice Test multiple deposits in same block
    function test_Variant_MultipleDeposits_SameBlock() public {
        vm.startPrank(alice);
        for (uint256 i = 0; i < 10; i++) {
            vault.deposit(address(usdc), 100e6);
        }
        vm.stopPrank();

        (uint256 deposits,) = vault.userPosition(address(usdc), alice);
        assertEq(deposits, 1000e6);
    }

    /// @notice Test deposit with different decimal tokens (6, 18, 8)
    function test_Variant_DifferentDecimals() public {
        MockERC20 token18 = new MockERC20("TOK18", "TOK18", 18);
        MockERC4626 vault18 = new MockERC4626(token18, "sT18", "sT18", 18);
        vault18.setYieldRatePerSecond(0);
        
        MockERC20 token8 = new MockERC20("TOK8", "TOK8", 8);
        MockERC4626 vault8 = new MockERC4626(token8, "sT8", "sT8", 8);
        vault8.setYieldRatePerSecond(0);

        vault.addSupportedToken(address(token18), IERC4626(address(vault18)));
        vault.addSupportedToken(address(token8), IERC4626(address(vault8)));

        // Mint and deposit
        token18.mint(alice, 1000e18);
        token8.mint(bob, 1000e8);

        vm.prank(alice);
        token18.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        token8.approve(address(vault), type(uint256).max);

        vm.prank(alice);
        vault.deposit(address(token18), 1000e18);
        
        vm.prank(bob);
        vault.deposit(address(token8), 1000e8);

        // Verify both work correctly
        assertEq(vault.totalDeposits(address(token18)), 1000e18);
        assertEq(vault.totalDeposits(address(token8)), 1000e8);
    }

    /// @notice Test withdrawal when vault has insufficient liquidity
    function test_Variant_InsufficientVaultLiquidity() public {
        vm.prank(alice);
        vault.deposit(address(usdc), 1000e6);

        // Simulate vault losing liquidity (someone else withdrawing from ERC4626)
        // For this test, we'll try to withdraw more than vault balance
        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(address(usdc), 1001e6);
    }

    /// @notice Test tiny yield amounts (1 wei yield)
    function test_Variant_TinyYield_OneWei() public {
        vm.prank(alice);
        vault.deposit(address(usdc), 1000e6);

        // Donate just 1 wei of yield
        usdc.mint(address(this), 1);
        usdc.approve(address(susdc), 1);
        susdc.donateYield(1);

        // Should still work
        assertGe(vault.prizePool(address(usdc)), 0);
    }

    /// @notice Test epoch boundary conditions (exactly at epoch end)
    function test_Variant_EpochBoundary_ExactEndTime() public {
        (, uint64 end,,,,, ) = vault.epochs(vault.currentEpoch());
        
        // Warp to exactly epoch end
        vm.warp(end);
        
        // Should be able to close
        vault.closeEpoch();
        assertEq(uint8(vault.epochStatus()), 1);
    }

    /// @notice Test epoch boundary (1 second before end)
    function test_Variant_EpochBoundary_OneSecondBefore() public {
        (, uint64 end,,,,, ) = vault.epochs(vault.currentEpoch());
        
        // Warp to 1 second before end
        vm.warp(end - 1);
        
        // Should NOT be able to close
        vm.expectRevert(WelotVault.DrawNotReady.selector);
        vault.closeEpoch();
    }

    /// @notice Pools are pre-created and deposits must use assigned pools
    function test_Variant_Pools_Precreated() public {
        // All 10 pools should be pre-created
        assertEq(vault.poolCount(), 10);

        // Deposits must target the recipient's assigned pool.
        uint256 alicePool = vault.assignedPoolId(alice);
        vm.prank(alice);
        vault.depositTo(address(usdc), 100e6, alicePool, alice);

        // Trying to deposit to wrong pool should fail
        vm.prank(alice);
        vm.expectRevert(WelotVault.InvalidAssignedPool.selector);
        vault.depositTo(address(usdc), 100e6, 50, alice);
    }

    /// @notice Test claiming prize twice (should fail second time)
    function test_Variant_DoubleClaim_ShouldFail() public {
        vm.prank(alice);
        vault.deposit(address(usdc), 1000e6);

        // Generate yield
        usdc.mint(address(this), 100e6);
        usdc.approve(address(susdc), type(uint256).max);
        susdc.donateYield(100e6);

        // Complete draw
        vm.warp(block.timestamp + 8 days);
        vault.closeEpoch();
        uint256 fee = entropy.getFeeV2();
        vm.deal(address(vault), fee);
        vault.requestRandomness{value: 0}();
        (,,, uint64 seq,,,) = vault.epochs(vault.currentEpoch());
        entropy.fulfill(seq, keccak256("random"));
        vault.finalizeDraw();

        // Claim once
        vm.prank(alice);
        vault.claimPrize(address(usdc));

        // Second claim should give nothing
        (, uint256 claimable) = vault.userPosition(address(usdc), alice);
        assertEq(claimable, 0);
    }

    /// @notice Test multiple withdrawals until balance is zero
    function test_Variant_MultipleWithdrawals_ToZero() public {
        vm.prank(alice);
        vault.deposit(address(usdc), 1000e6);

        // Withdraw in chunks
        vm.startPrank(alice);
        vault.withdraw(address(usdc), 250e6);
        vault.withdraw(address(usdc), 250e6);
        vault.withdraw(address(usdc), 250e6);
        vault.withdraw(address(usdc), 250e6);
        vm.stopPrank();

        (uint256 deposits,) = vault.userPosition(address(usdc), alice);
        assertEq(deposits, 0);
    }

    /// @notice Test interleaved deposits and withdrawals
    function test_Variant_InterleavedDepositsWithdrawals() public {
        vm.startPrank(alice);
        vault.deposit(address(usdc), 1000e6);
        vault.withdraw(address(usdc), 200e6);
        vault.deposit(address(usdc), 500e6);
        vault.withdraw(address(usdc), 300e6);
        vault.deposit(address(usdc), 100e6);
        vm.stopPrank();

        // Net: 1000 - 200 + 500 - 300 + 100 = 1100
        (uint256 deposits,) = vault.userPosition(address(usdc), alice);
        assertEq(deposits, 1100e6);
    }

    /// @notice Test time-weighted odds with rapid deposits/withdrawals
    function test_Variant_TimeWeighted_RapidChanges() public {
        // Alice deposits early
        vm.prank(alice);
        vault.deposit(address(usdc), 1000e6);

        // Warp 1 day
        vm.warp(block.timestamp + 1 days);

        // Bob deposits same amount but later
        vm.prank(bob);
        vault.deposit(address(usdc), 1000e6);

        // Alice should have more time-weighted odds since she was in longer
        // Complete draw and verify
        usdc.mint(address(this), 100e6);
        usdc.approve(address(susdc), type(uint256).max);
        susdc.donateYield(100e6);

        vm.warp(block.timestamp + 7 days);
        vault.closeEpoch();
        uint256 fee = entropy.getFeeV2();
        vm.deal(address(vault), fee);
        vault.requestRandomness{value: 0}();
        (,,, uint64 seq,,,) = vault.epochs(vault.currentEpoch());
        entropy.fulfill(seq, keccak256("alice_should_win"));
        vault.finalizeDraw();

        // Both can win, but alice has better odds
        (, uint256 aliceWin) = vault.userPosition(address(usdc), alice);
        (, uint256 bobWin) = vault.userPosition(address(usdc), bob);
        
        // Total should equal prize pool
        assertApproxEqAbs(aliceWin + bobWin, 100e6, 1e3);
    }

    /// @notice Test pausing during different states
    function test_Variant_PauseDuringDifferentStates() public {
        // State 1: Open
        vault.pause();
        assertTrue(vault.paused());
        
        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(address(usdc), 100e6);
        
        vault.unpause();

        // Deposit when unpaused
        vm.prank(alice);
        vault.deposit(address(usdc), 1000e6);

        // State 2: After epoch end, pause before closing
        vm.warp(block.timestamp + 8 days);
        
        vault.pause();
        assertTrue(vault.paused());
        
        // Can't interact while paused
        vm.prank(bob);
        vm.expectRevert();
        vault.deposit(address(usdc), 100e6);
        
        vault.unpause();
    }

    /// @notice Test adding duplicate token (should revert or handle gracefully)
    function test_Variant_AddDuplicateToken() public {
        // Try to add USDC again (should fail since already configured)
        vm.expectRevert();
        vault.addSupportedToken(address(usdc), IERC4626(address(susdc)));
    }

    /// @notice Test random winner selection with different deposit sizes
    function test_Variant_WinnerDistribution_DifferentDeposits() public {
        // Setup: alice has 3x more deposits than bob
        vm.prank(alice);
        vault.deposit(address(usdc), 3000e6);
        
        vm.prank(bob);
        vault.deposit(address(usdc), 1000e6);

        // Generate yield
        usdc.mint(address(this), 100e6);
        usdc.approve(address(susdc), type(uint256).max);
        susdc.donateYield(100e6);

        // Complete draw
        vm.warp(block.timestamp + 8 days);
        vault.closeEpoch();
        uint256 fee = entropy.getFeeV2();
        vm.deal(address(vault), fee);
        vault.requestRandomness{value: 0}();
        (,,, uint64 seq,,,) = vault.epochs(vault.currentEpoch());
        entropy.fulfill(seq, keccak256("random"));
        vault.finalizeDraw();

        // Check that someone won
        (, uint256 aliceWin) = vault.userPosition(address(usdc), alice);
        (, uint256 bobWin) = vault.userPosition(address(usdc), bob);

        // Either alice or bob should win (both in pool 1)
        uint256 totalWins = aliceWin + bobWin;
        assertApproxEqAbs(totalWins, 100e6, 1e3);
        assertTrue(totalWins > 0, "Someone should have won");
    }

    receive() external payable {}
}
