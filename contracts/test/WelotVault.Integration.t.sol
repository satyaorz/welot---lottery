// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {WelotVault} from "../src/WelotVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockERC4626} from "../src/mocks/MockERC4626.sol";
import {MockEntropyV2} from "../src/mocks/MockEntropyV2.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IEntropyV2} from "../src/interfaces/IEntropyV2.sol";

/// @title WelotVault Integration Tests
/// @notice Comprehensive integration tests for full lottery lifecycle with multiple tokens and users
contract WelotVaultIntegrationTest is Test {
    MockERC20 usdc;
    MockERC20 usdt;
    MockERC4626 susdc;
    MockERC4626 susdt;
    MockEntropyV2 entropy;
    WelotVault vault;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xC0FFEE);
    address dave = address(0xD4D);
    address erin = address(0xE11);
    address frank = address(0xF44);

    function setUp() public {
        // Deploy USDC (6 decimals) and USDT (6 decimals)
        usdc = new MockERC20("USDC", "USDC", 6);
        usdt = new MockERC20("USDT", "USDT", 6);
        
        // Deploy yield vaults
        susdc = new MockERC4626(usdc, "sUSDC", "sUSDC", 6);
        susdt = new MockERC4626(usdt, "sUSDT", "sUSDT", 6);
        
        // No auto-yield in integration tests - we control yield explicitly
        susdc.setYieldRatePerSecond(0);
        susdt.setYieldRatePerSecond(0);

        // Deploy entropy
        entropy = new MockEntropyV2();

        // Deploy vault
        vault = new WelotVault(
            IEntropyV2(address(entropy)),
            7 days,
            10
        );

        // Configure both tokens
        vault.addSupportedToken(address(usdc), IERC4626(address(susdc)));
        vault.addSupportedToken(address(usdt), IERC4626(address(susdt)));

        // Mint and approve for all users
        _setupUser(alice);
        _setupUser(bob);
        _setupUser(carol);
        _setupUser(dave);
        _setupUser(erin);
        _setupUser(frank);
    }

    function _setupUser(address user) internal {
        usdc.mint(user, 10_000e6);
        usdt.mint(user, 10_000e6);
        
        vm.startPrank(user);
        usdc.approve(address(vault), type(uint256).max);
        usdt.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    function _completeDraw() internal {
        // Warp past epoch end
        vm.warp(block.timestamp + 8 days);
        vault.closeEpoch();
        
        // Request randomness
        uint256 fee = entropy.getFeeV2();
        vm.deal(address(vault), fee);
        vault.requestRandomness{value: 0}();
        
        // Fulfill randomness
        bytes32 randomNumber = keccak256(abi.encodePacked(block.timestamp, block.number));
        (,,, uint64 seq,,,) = vault.epochs(vault.currentEpoch());
        entropy.fulfill(seq, randomNumber);
        
        // Finalize
        vault.finalizeDraw();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FULL MULTI-TOKEN INTEGRATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test complete lottery flow with two tokens (USDC and USDT)
    function test_Integration_MultiToken_FullFlow() public {
        // === PHASE 1: Deposits ===
        vm.prank(alice);
        vault.deposit(address(usdc), 1000e6);
        
        vm.prank(bob);
        vault.deposit(address(usdt), 2000e6);
        
        vm.prank(carol);
        vault.deposit(address(usdc), 500e6);
        
        vm.prank(dave);
        vault.deposit(address(usdt), 1500e6);

        // Verify deposits
        assertEq(vault.totalDeposits(address(usdc)), 1500e6);
        assertEq(vault.totalDeposits(address(usdt)), 3500e6);

        // === PHASE 2: Generate Yield ===
        // USDC: 100 USDC yield
        usdc.mint(address(this), 100e6);
        usdc.approve(address(susdc), type(uint256).max);
        susdc.donateYield(100e6);
        
        // USDT: 50 USDT yield
        usdt.mint(address(this), 50e6);
        usdt.approve(address(susdt), type(uint256).max);
        susdt.donateYield(50e6);

        // Verify prize pools
        uint256 usdcPrizeBefore = vault.prizePool(address(usdc));
        uint256 usdtPrizeBefore = vault.prizePool(address(usdt));
        assertApproxEqAbs(usdcPrizeBefore, 100e6, 1e3);
        assertApproxEqAbs(usdtPrizeBefore, 50e6, 1e3);

        // === PHASE 3: Complete Draw ===
        _completeDraw();

        // Completed epoch is previous currentEpoch()
        uint256 finishedEpoch = vault.currentEpoch() - 1;

        // Per-token prize allocation is pool-dependent: if the winning pool has
        // zero deposits for a token, that token's prize remains unallocated.
        uint256 usdcAllocated = vault.epochTokenPrize(finishedEpoch, address(usdc));
        uint256 usdtAllocated = vault.epochTokenPrize(finishedEpoch, address(usdt));
        assertTrue(usdcAllocated == 0 || usdcAllocated == usdcPrizeBefore);
        assertTrue(usdtAllocated == 0 || usdtAllocated == usdtPrizeBefore);

        // === PHASE 4: Verify Winners ===
        // Check USDC winners (alice or carol)
        (, uint256 aliceUSDCWin) = vault.userPosition(address(usdc), alice);
        (, uint256 carolUSDCWin) = vault.userPosition(address(usdc), carol);
        uint256 totalUSDCWins = aliceUSDCWin + carolUSDCWin;
        
        // Check USDT winners (bob or dave)
        (, uint256 bobUSDTWin) = vault.userPosition(address(usdt), bob);
        (, uint256 daveUSDTWin) = vault.userPosition(address(usdt), dave);
        uint256 totalUSDTWins = bobUSDTWin + daveUSDTWin;

        // Total prizes should equal what was actually allocated this epoch.
        assertApproxEqAbs(totalUSDCWins, usdcAllocated, 1e3);
        assertApproxEqAbs(totalUSDTWins, usdtAllocated, 1e3);

        // === PHASE 5: Claim Prizes ===
        if (aliceUSDCWin > 0) {
            uint256 balBefore = usdc.balanceOf(alice);
            vm.prank(alice);
            vault.claimPrize(address(usdc));
            assertApproxEqAbs(usdc.balanceOf(alice), balBefore + aliceUSDCWin, 1e3);
        }
        
        if (bobUSDTWin > 0) {
            uint256 balBefore = usdt.balanceOf(bob);
            vm.prank(bob);
            vault.claimPrize(address(usdt));
            assertApproxEqAbs(usdt.balanceOf(bob), balBefore + bobUSDTWin, 1e3);
        }
    }

    /// @notice Test multiple consecutive draws with ongoing participation
    function test_Integration_MultipleDraws_ConsecutiveEpochs() public {
        // === EPOCH 1 ===
        vm.prank(alice);
        vault.deposit(address(usdc), 1000e6);
        
        vm.prank(bob);
        vault.deposit(address(usdt), 1000e6);

        // Generate yield
        usdc.mint(address(this), 50e6);
        usdc.approve(address(susdc), type(uint256).max);
        susdc.donateYield(50e6);

        _completeDraw();
        
        (, uint256 aliceWin1) = vault.userPosition(address(usdc), alice);

        // === EPOCH 2 ===
        // Alice deposits more, Carol joins
        vm.prank(alice);
        vault.deposit(address(usdc), 500e6);
        
        vm.prank(carol);
        vault.deposit(address(usdc), 2000e6);

        // Generate more yield
        usdc.mint(address(this), 75e6);
        usdc.approve(address(susdc), type(uint256).max);
        susdc.donateYield(75e6);

        _completeDraw();

        // Winners should be alice or carol
        (, uint256 aliceWin2) = vault.userPosition(address(usdc), alice);
        
        // Alice should still have first prize unclaimed + potential second prize
        assertGe(aliceWin2, aliceWin1);
    }

    /// @notice Test mid-epoch withdrawals and deposits
    function test_Integration_MidEpoch_WithdrawalsAndDeposits() public {
        // Initial deposits
        vm.prank(alice);
        vault.deposit(address(usdc), 2000e6);
        
        vm.prank(bob);
        vault.deposit(address(usdc), 1000e6);

        // Warp to mid-epoch
        vm.warp(block.timestamp + 3 days);

        // Alice withdraws half
        vm.prank(alice);
        vault.withdraw(address(usdc), 1000e6);
        
        // Carol joins mid-epoch
        vm.prank(carol);
        vault.deposit(address(usdc), 1500e6);

        // Generate yield
        usdc.mint(address(this), 100e6);
        usdc.approve(address(susdc), type(uint256).max);
        susdc.donateYield(100e6);

        // Complete draw
        _completeDraw();

        // All three should have winning chances based on their time-weighted balances
        (, uint256 aliceWin) = vault.userPosition(address(usdc), alice);
        (, uint256 bobWin) = vault.userPosition(address(usdc), bob);
        (, uint256 carolWin) = vault.userPosition(address(usdc), carol);
        
        uint256 totalWins = aliceWin + bobWin + carolWin;
        assertApproxEqAbs(totalWins, 100e6, 1e3);
    }

    /// @notice Test multiple pools competing for prizes
    function test_Integration_MultiplePools_Competition() public {
        // Pools are pre-created (fixed 10) and users are deterministically assigned.
        // Add a couple of small-int addresses to guarantee distinct pools.
        address u1 = address(0x1);
        address u2 = address(0x2);
        _setupUser(u1);
        _setupUser(u2);

        // Deposits across pools
        vm.prank(carol);
        vault.deposit(address(usdc), 1000e6);

        vm.prank(dave);
        vault.deposit(address(usdc), 500e6);

        vm.prank(u1);
        vault.deposit(address(usdc), 2000e6);

        vm.prank(u2);
        vault.deposit(address(usdc), 1500e6);

        // Sanity: ensure at least two distinct pools were used.
        assertTrue(vault.assignedPoolId(u1) != vault.assignedPoolId(u2));

        // Generate yield
        usdc.mint(address(this), 200e6);
        usdc.approve(address(susdc), type(uint256).max);
        susdc.donateYield(200e6);

        // Verify prize pool
        assertGt(vault.prizePool(address(usdc)), 0, "Prize pool should have yield");

        // Complete draw
        _completeDraw();

        // Check prize pool was distributed
        // Pool 2 won (alice's pool), but we check default pool 1 positions
        // This test just verifies the draw completed and prize was allocated
        uint256 prizePoolAfter = vault.prizePool(address(usdc));
        
        // Prize pool should be reduced (claimed by winning pool)
        assertLt(prizePoolAfter, 200e6, "Prize should have been distributed");
    }

    /// @notice Test large-scale deposits with many users
    function test_Integration_LargeScale_ManyUsers() public {
        address[] memory users = new address[](10);
        users[0] = alice;
        users[1] = bob;
        users[2] = carol;
        users[3] = dave;
        users[4] = erin;
        users[5] = frank;
        users[6] = address(0x777);
        users[7] = address(0x888);
        users[8] = address(0x999);
        users[9] = address(0xAAA);

        // Setup additional users
        for (uint256 i = 6; i < 10; i++) {
            _setupUser(users[i]);
        }

        // Random deposits from all users
        for (uint256 i = 0; i < users.length; i++) {
            uint256 amount = (i + 1) * 100e6; // 100, 200, 300, ... 1000 USDC
            vm.prank(users[i]);
            vault.deposit(address(usdc), amount);
        }

        // Total: 5500 USDC deposited
        assertEq(vault.totalDeposits(address(usdc)), 5500e6);

        // Generate 10% yield
        usdc.mint(address(this), 550e6);
        usdc.approve(address(susdc), type(uint256).max);
        susdc.donateYield(550e6);

        // Complete draw
        _completeDraw();

        // Verify total prizes distributed
        uint256 totalPrizes = 0;
        for (uint256 i = 0; i < users.length; i++) {
            (, uint256 prize) = vault.userPosition(address(usdc), users[i]);
            totalPrizes += prize;
        }
        
        assertApproxEqAbs(totalPrizes, 550e6, 1e4);
    }

    /// @notice Test zero yield scenario (no winners)
    function test_Integration_ZeroYield_NoWinners() public {
        vm.prank(alice);
        vault.deposit(address(usdc), 1000e6);
        
        vm.prank(bob);
        vault.deposit(address(usdt), 1000e6);

        // No yield generated
        assertEq(vault.prizePool(address(usdc)), 0);
        assertEq(vault.prizePool(address(usdt)), 0);

        // Complete draw anyway
        _completeDraw();

        // No prizes should be distributed
        (, uint256 aliceWin) = vault.userPosition(address(usdc), alice);
        (, uint256 bobWin) = vault.userPosition(address(usdt), bob);
        
        assertEq(aliceWin, 0);
        assertEq(bobWin, 0);
    }

    /// @notice Test automated upkeep integration
    function test_Integration_Automation_CheckAndPerformUpkeep() public {
        // Setup deposits
        vm.prank(alice);
        vault.deposit(address(usdc), 1000e6);

        // Initially no upkeep needed
        (bool needed,) = vault.checkUpkeep("");
        assertFalse(needed);

        // Warp to epoch end
        vm.warp(block.timestamp + 8 days);

        // Now upkeep should be needed
        (bool needed2, bytes memory performData) = vault.checkUpkeep("");
        assertTrue(needed2);

        // Perform upkeep (step 1: close epoch)
        vault.performUpkeep(performData);
        assertEq(uint8(vault.epochStatus()), 1); // Closed

        // Check again (step 2: request randomness)
        (bool needed3, bytes memory performData2) = vault.checkUpkeep("");
        assertTrue(needed3);
        
        vm.deal(address(vault), entropy.getFeeV2());
        vault.performUpkeep(performData2);
        assertEq(uint8(vault.epochStatus()), 2); // RandomnessRequested

        // Fulfill randomness
        (,,, uint64 seq,,,) = vault.epochs(vault.currentEpoch());
        entropy.fulfill(seq, keccak256("random"));

        // Check again (step 3: finalize)
        (bool needed4, bytes memory performData3) = vault.checkUpkeep("");
        assertTrue(needed4);
        
        vault.performUpkeep(performData3);
        assertEq(uint8(vault.epochStatus()), 0); // New epoch opened
    }

    /// @notice Test claiming prizes across multiple tokens
    function test_Integration_MultiToken_PrizeClaiming() public {
        // Alice deposits both tokens
        vm.startPrank(alice);
        vault.deposit(address(usdc), 1000e6);
        vault.deposit(address(usdt), 1000e6);
        vm.stopPrank();

        // Generate yield for both
        usdc.mint(address(this), 100e6);
        usdc.approve(address(susdc), type(uint256).max);
        susdc.donateYield(100e6);
        
        usdt.mint(address(this), 50e6);
        usdt.approve(address(susdt), type(uint256).max);
        susdt.donateYield(50e6);

        _completeDraw();

        // Alice should win both (only depositor)
        (, uint256 usdcWin) = vault.userPosition(address(usdc), alice);
        (, uint256 usdtWin) = vault.userPosition(address(usdt), alice);
        
        assertApproxEqAbs(usdcWin, 100e6, 1e3);
        assertApproxEqAbs(usdtWin, 50e6, 1e3);

        // Claim USDC prize
        uint256 usdcBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        vault.claimPrize(address(usdc));
        assertApproxEqAbs(usdc.balanceOf(alice), usdcBefore + 100e6, 1e3);

        // Claim USDT prize
        uint256 usdtBefore = usdt.balanceOf(alice);
        vm.prank(alice);
        vault.claimPrize(address(usdt));
        assertApproxEqAbs(usdt.balanceOf(alice), usdtBefore + 50e6, 1e3);

        // Both should be claimed
        (, uint256 usdcAfter) = vault.userPosition(address(usdc), alice);
        (, uint256 usdtAfter) = vault.userPosition(address(usdt), alice);
        assertEq(usdcAfter, 0);
        assertEq(usdtAfter, 0);
    }

    receive() external payable {}
}
