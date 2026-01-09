// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";

import {WelotVault} from "../src/WelotVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockERC4626} from "../src/mocks/MockERC4626.sol";
import {MockEntropyV2} from "../src/mocks/MockEntropyV2.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IEntropyV2} from "../src/interfaces/IEntropyV2.sol";

contract WelotVaultTest is Test {
    MockERC20 usdc;
    MockERC4626 susdc;
    MockEntropyV2 entropy;
    WelotVault vault;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xC0FFEE);
    address dave = address(0xD4D);
    address erin = address(0xE11);
    address owner = address(this);

    function setUp() public {
        // Deploy mock tokens (USDC with 6 decimals)
        usdc = new MockERC20("USDC", "USDC", 6);
        susdc = new MockERC4626(usdc, "sUSDC", "sUSDC", 6);
        // Unit tests expect prize growth only when explicitly donated.
        susdc.setYieldRatePerSecond(0);

        // Deploy mock entropy
        entropy = new MockEntropyV2();

        // Deploy vault
        vault = new WelotVault(
            IEntropyV2(address(entropy)),
            7 days,  // Weekly draws
            10       // Fixed 10 pools (auto-assigned)
        );

        // Configure USDC as a supported token using addSupportedToken
        vault.addSupportedToken(address(usdc), IERC4626(address(susdc)));

        // Mint and approve for participants
        _mintApprove(alice);
        _mintApprove(bob);
        _mintApprove(carol);
        _mintApprove(dave);
        _mintApprove(erin);
    }

    function _mintApprove(address user) internal {
        usdc.mint(user, 1_000e6);
        vm.prank(user);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TOKEN CONFIGURATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ConfigureToken() public view {
        (bool enabled, , uint8 decimals, , ) = vault.tokenConfigs(address(usdc));
        assertTrue(enabled);
        assertEq(decimals, 6);
    }

    function test_AddSupportedToken_OnlyOwner() public {
        MockERC20 usdt = new MockERC20("USDT", "USDT", 6);
        MockERC4626 susdt = new MockERC4626(usdt, "sUSDT", "sUSDT", 6);
        
        vm.prank(alice);
        vm.expectRevert();
        vault.addSupportedToken(address(usdt), IERC4626(address(susdt)));
    }

    function test_GetSupportedTokens() public view {
        address[] memory tokens = vault.getSupportedTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], address(usdc));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DEPOSIT TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Deposit() public {
        vm.prank(alice);
        vault.deposit(address(usdc), 100e6);

        (uint256 deposits, uint256 claimable) = vault.userPosition(address(usdc), alice);
        assertEq(deposits, 100e6);
        assertEq(claimable, 0);
    }

    function test_Deposit_Multiple() public {
        vm.prank(alice);
        vault.deposit(address(usdc), 100e6);
        
        vm.prank(bob);
        vault.deposit(address(usdc), 200e6);

        assertEq(vault.totalDeposits(address(usdc)), 300e6);
    }

    function test_Deposit_DisabledToken() public {
        MockERC20 fake = new MockERC20("FAKE", "FAKE", 6);
        
        vm.prank(alice);
        vm.expectRevert(WelotVault.WelotVault__TokenNotSupported.selector);
        vault.deposit(address(fake), 100e6);
    }

    function test_Deposit_ZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(WelotVault.WelotVault__ZeroAmount.selector);
        vault.deposit(address(usdc), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // WITHDRAW TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Withdraw() public {
        vm.startPrank(alice);
        vault.deposit(address(usdc), 100e6);
        vault.withdraw(address(usdc), 50e6);
        vm.stopPrank();

        (uint256 deposits, ) = vault.userPosition(address(usdc), alice);
        assertEq(deposits, 50e6);
        assertEq(usdc.balanceOf(alice), 950e6); // 1000 - 100 + 50
    }

    function test_Withdraw_Full() public {
        vm.startPrank(alice);
        vault.deposit(address(usdc), 100e6);
        vault.withdraw(address(usdc), 100e6);
        vm.stopPrank();

        (uint256 deposits, ) = vault.userPosition(address(usdc), alice);
        assertEq(deposits, 0);
    }

    function test_Withdraw_ExceedsBalance() public {
        vm.startPrank(alice);
        vault.deposit(address(usdc), 100e6);
        vm.expectRevert(WelotVault.WelotVault__InsufficientBalance.selector);
        vault.withdraw(address(usdc), 150e6);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EPOCH TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CloseEpoch_NotReady() public {
        // Epoch just started, should not be closeable
        vm.expectRevert(WelotVault.WelotVault__DrawNotReady.selector);
        vault.closeEpoch();
    }

    function test_CloseEpoch() public {
        // Warp past epoch end
        vm.warp(block.timestamp + 8 days);
        vault.closeEpoch();

        assertEq(uint8(vault.epochStatus()), 1); // Closed
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FULL LOTTERY FLOW TEST
    // ═══════════════════════════════════════════════════════════════════════════

    function test_FullLotteryFlow() public {
        // 1. Multiple users deposit
        vm.prank(alice);
        vault.deposit(address(usdc), 100e6);
        vm.prank(bob);
        vault.deposit(address(usdc), 200e6);
        vm.prank(carol);
        vault.deposit(address(usdc), 300e6);
        vm.prank(dave);
        vault.deposit(address(usdc), 400e6);
        vm.prank(erin);
        vault.deposit(address(usdc), 500e6);

        assertEq(vault.totalDeposits(address(usdc)), 1500e6);

        // 2. Generate yield (donate to sUSDC mock)
        usdc.mint(address(this), 100e6);
        usdc.approve(address(susdc), type(uint256).max);
        susdc.donateYield(100e6);

        // Check prize pool includes yield (use approx due to ERC4626 rounding)
        assertApproxEqAbs(vault.prizePool(address(usdc)), 100e6, 1e3);

        // 3. Warp to after epoch end (Friday noon)
        vm.warp(block.timestamp + 8 days);

        // 4. Close epoch
        vault.closeEpoch();
        assertEq(uint8(vault.epochStatus()), 1); // Closed

        // 5. Request randomness (requires payment)
        uint256 fee = entropy.getFeeV2();
        vm.deal(address(vault), fee);
        vault.requestRandomness{value: 0}();
        assertEq(uint8(vault.epochStatus()), 2); // RandomnessRequested

        // 6. Mock fulfills randomness
        bytes32 randomNumber = keccak256(abi.encodePacked("test_random"));
        (,,, uint64 seq,,,) = vault.epochs(vault.currentEpoch());
        entropy.fulfill(seq, randomNumber);
        assertEq(uint8(vault.epochStatus()), 3); // RandomnessReady

        // 7. Finalize draw
        vault.finalizeDraw();
        assertEq(uint8(vault.epochStatus()), 0); // Back to Open (new epoch)

        // 8. Check someone won (exactly one winner per token)
        uint256 totalClaimable = 0;
        address[] memory users = new address[](5);
        users[0] = alice;
        users[1] = bob;
        users[2] = carol;
        users[3] = dave;
        users[4] = erin;

        for (uint256 i = 0; i < users.length; i++) {
            (, uint256 claimable) = vault.userPosition(address(usdc), users[i]);
            totalClaimable += claimable;
        }

        // The entire prize pool should be claimable by winner(s)
        // Use approximate equality due to ERC4626 rounding
        assertApproxEqAbs(totalClaimable, 100e6, 1e3);
    }

    function test_ClaimPrize() public {
        // Setup: deposit, generate yield, complete lottery
        vm.prank(alice);
        vault.deposit(address(usdc), 1000e6);

        // Generate yield
        usdc.mint(address(this), 50e6);
        usdc.approve(address(susdc), type(uint256).max);
        susdc.donateYield(50e6);

        // Complete epoch
        vm.warp(block.timestamp + 8 days);
        vault.closeEpoch();
        
        uint256 fee = entropy.getFeeV2();
        vm.deal(address(vault), fee);
        vault.requestRandomness{value: 0}();
        
        bytes32 randomNumber = keccak256(abi.encodePacked("alice_wins"));
        (,,, uint64 seq,,,) = vault.epochs(vault.currentEpoch());
        entropy.fulfill(seq, randomNumber);
        
        vault.finalizeDraw();

        // Alice should have won (only depositor)
        (, uint256 claimable) = vault.userPosition(address(usdc), alice);
        assertApproxEqAbs(claimable, 50e6, 1e3);

        // Claim prize
        uint256 balanceBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        vault.claimPrize(address(usdc));
        
        assertApproxEqAbs(usdc.balanceOf(alice), balanceBefore + 50e6, 1e3);
        
        // Claimable should now be 0
        (, uint256 claimableAfter) = vault.userPosition(address(usdc), alice);
        assertEq(claimableAfter, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // AUTOMATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CheckUpkeep_NotNeeded() public view {
        (bool needed, ) = vault.checkUpkeep("");
        assertFalse(needed);
    }

    function test_CheckUpkeep_EpochEnded() public {
        // Warp past epoch end
        vm.warp(block.timestamp + 8 days);
        
        (bool needed, ) = vault.checkUpkeep("");
        assertTrue(needed);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PAUSE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Pause() public {
        vault.pause();
        assertTrue(vault.paused());

        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(address(usdc), 100e6);
    }

    function test_Unpause() public {
        vault.pause();
        vault.unpause();
        assertFalse(vault.paused());

        vm.prank(alice);
        vault.deposit(address(usdc), 100e6);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EDGE CASES
    // ═══════════════════════════════════════════════════════════════════════════

    function test_NoPrize_NothingToClaim() public {
        // Deposit but no yield generated
        vm.prank(alice);
        vault.deposit(address(usdc), 100e6);

        // Complete epoch with no yield
        vm.warp(block.timestamp + 8 days);
        vault.closeEpoch();
        
        uint256 fee = entropy.getFeeV2();
        vm.deal(address(vault), fee);
        vault.requestRandomness{value: 0}();
        
        bytes32 randomNumber = keccak256(abi.encodePacked("no_prize"));
        entropy.fulfillRandomness(address(vault), vault.currentEpoch(), randomNumber);
        
        vault.finalizeDraw();

        // No claimable since no yield was generated
        (, uint256 claimable) = vault.userPosition(address(usdc), alice);
        assertEq(claimable, 0);
    }

    function test_MultipleDeposits_SameUser() public {
        vm.startPrank(alice);
        vault.deposit(address(usdc), 100e6);
        vault.deposit(address(usdc), 50e6);
        vault.deposit(address(usdc), 25e6);
        vm.stopPrank();

        (uint256 deposits, ) = vault.userPosition(address(usdc), alice);
        assertEq(deposits, 175e6);
    }

    function test_WithdrawDuringEpoch() public {
        // Deposit
        vm.prank(alice);
        vault.deposit(address(usdc), 100e6);

        // Warp to mid-epoch
        vm.warp(block.timestamp + 3 days);

        // Should still be able to withdraw
        vm.prank(alice);
        vault.withdraw(address(usdc), 50e6);

        (uint256 deposits, ) = vault.userPosition(address(usdc), alice);
        assertEq(deposits, 50e6);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RECEIVE ETH (for entropy fees)
    // ═══════════════════════════════════════════════════════════════════════════

    receive() external payable {}
}
