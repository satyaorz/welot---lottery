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
    MockERC20 usde;
    MockERC4626 susde;
    MockEntropyV2 entropy;
    WelotVault vault;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xC0FFEE);
    address dave = address(0xD4D);
    address erin = address(0xE11);
    address owner = address(this);

    function setUp() public {
        // Deploy mock tokens
        usde = new MockERC20("USDe", "USDe", 18);
        susde = new MockERC4626(usde, "sUSDe", "sUSDe", 18);
        // Unit tests expect prize growth only when explicitly donated.
        susde.setYieldRatePerSecond(0);

        // Deploy mock entropy
        entropy = new MockEntropyV2();

        // Deploy vault
        vault = new WelotVault(
            IEntropyV2(address(entropy)),
            7 days,  // Weekly draws
            64       // Max pools
        );

        // Configure USDe as a supported token using addSupportedToken
        vault.addSupportedToken(address(usde), IERC4626(address(susde)));

        // Mint and approve for participants
        _mintApprove(alice);
        _mintApprove(bob);
        _mintApprove(carol);
        _mintApprove(dave);
        _mintApprove(erin);
    }

    function _mintApprove(address user) internal {
        usde.mint(user, 1_000e18);
        vm.prank(user);
        usde.approve(address(vault), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TOKEN CONFIGURATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ConfigureToken() public view {
        (bool enabled, , uint8 decimals, , ) = vault.tokenConfigs(address(usde));
        assertTrue(enabled);
        assertEq(decimals, 18);
    }

    function test_AddSupportedToken_OnlyOwner() public {
        MockERC20 usdc = new MockERC20("USDC", "USDC", 6);
        MockERC4626 susdc = new MockERC4626(usdc, "sUSDC", "sUSDC", 6);
        
        vm.prank(alice);
        vm.expectRevert();
        vault.addSupportedToken(address(usdc), IERC4626(address(susdc)));
    }

    function test_GetSupportedTokens() public view {
        address[] memory tokens = vault.getSupportedTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], address(usde));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DEPOSIT TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Deposit() public {
        vm.prank(alice);
        vault.deposit(address(usde), 100e18);

        (uint256 deposits, uint256 claimable) = vault.userPosition(address(usde), alice);
        assertEq(deposits, 100e18);
        assertEq(claimable, 0);
    }

    function test_Deposit_Multiple() public {
        vm.prank(alice);
        vault.deposit(address(usde), 100e18);
        
        vm.prank(bob);
        vault.deposit(address(usde), 200e18);

        assertEq(vault.totalDeposits(address(usde)), 300e18);
    }

    function test_Deposit_DisabledToken() public {
        MockERC20 fake = new MockERC20("FAKE", "FAKE", 18);
        
        vm.prank(alice);
        vm.expectRevert(WelotVault.TokenNotSupported.selector);
        vault.deposit(address(fake), 100e18);
    }

    function test_Deposit_ZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(WelotVault.ZeroAmount.selector);
        vault.deposit(address(usde), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // WITHDRAW TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Withdraw() public {
        vm.startPrank(alice);
        vault.deposit(address(usde), 100e18);
        vault.withdraw(address(usde), 50e18);
        vm.stopPrank();

        (uint256 deposits, ) = vault.userPosition(address(usde), alice);
        assertEq(deposits, 50e18);
        assertEq(usde.balanceOf(alice), 950e18); // 1000 - 100 + 50
    }

    function test_Withdraw_Full() public {
        vm.startPrank(alice);
        vault.deposit(address(usde), 100e18);
        vault.withdraw(address(usde), 100e18);
        vm.stopPrank();

        (uint256 deposits, ) = vault.userPosition(address(usde), alice);
        assertEq(deposits, 0);
    }

    function test_Withdraw_ExceedsBalance() public {
        vm.startPrank(alice);
        vault.deposit(address(usde), 100e18);
        vm.expectRevert(WelotVault.InsufficientBalance.selector);
        vault.withdraw(address(usde), 150e18);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EPOCH TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CloseEpoch_NotReady() public {
        // Epoch just started, should not be closeable
        vm.expectRevert(WelotVault.DrawNotReady.selector);
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
        vault.deposit(address(usde), 100e18);
        vm.prank(bob);
        vault.deposit(address(usde), 200e18);
        vm.prank(carol);
        vault.deposit(address(usde), 300e18);
        vm.prank(dave);
        vault.deposit(address(usde), 400e18);
        vm.prank(erin);
        vault.deposit(address(usde), 500e18);

        assertEq(vault.totalDeposits(address(usde)), 1500e18);

        // 2. Generate yield (donate to sUSDe mock)
        usde.mint(address(this), 100e18);
        usde.approve(address(susde), type(uint256).max);
        susde.donateYield(100e18);

        // Check prize pool includes yield (use approx due to ERC4626 rounding)
        assertApproxEqAbs(vault.prizePool(address(usde)), 100e18, 1e15);

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
            (, uint256 claimable) = vault.userPosition(address(usde), users[i]);
            totalClaimable += claimable;
        }

        // The entire prize pool should be claimable by winner(s)
        // Use approximate equality due to ERC4626 rounding
        assertApproxEqAbs(totalClaimable, 100e18, 1e15);
    }

    function test_ClaimPrize() public {
        // Setup: deposit, generate yield, complete lottery
        vm.prank(alice);
        vault.deposit(address(usde), 1000e18);

        // Generate yield
        usde.mint(address(this), 50e18);
        usde.approve(address(susde), type(uint256).max);
        susde.donateYield(50e18);

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
        (, uint256 claimable) = vault.userPosition(address(usde), alice);
        assertApproxEqAbs(claimable, 50e18, 1e15);

        // Claim prize
        uint256 balanceBefore = usde.balanceOf(alice);
        vm.prank(alice);
        vault.claimPrize(address(usde));
        
        assertApproxEqAbs(usde.balanceOf(alice), balanceBefore + 50e18, 1e15);
        
        // Claimable should now be 0
        (, uint256 claimableAfter) = vault.userPosition(address(usde), alice);
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
        vault.deposit(address(usde), 100e18);
    }

    function test_Unpause() public {
        vault.pause();
        vault.unpause();
        assertFalse(vault.paused());

        vm.prank(alice);
        vault.deposit(address(usde), 100e18);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EDGE CASES
    // ═══════════════════════════════════════════════════════════════════════════

    function test_NoPrize_NothingToClaim() public {
        // Deposit but no yield generated
        vm.prank(alice);
        vault.deposit(address(usde), 100e18);

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
        (, uint256 claimable) = vault.userPosition(address(usde), alice);
        assertEq(claimable, 0);
    }

    function test_MultipleDeposits_SameUser() public {
        vm.startPrank(alice);
        vault.deposit(address(usde), 100e18);
        vault.deposit(address(usde), 50e18);
        vault.deposit(address(usde), 25e18);
        vm.stopPrank();

        (uint256 deposits, ) = vault.userPosition(address(usde), alice);
        assertEq(deposits, 175e18);
    }

    function test_WithdrawDuringEpoch() public {
        // Deposit
        vm.prank(alice);
        vault.deposit(address(usde), 100e18);

        // Warp to mid-epoch
        vm.warp(block.timestamp + 3 days);

        // Should still be able to withdraw
        vm.prank(alice);
        vault.withdraw(address(usde), 50e18);

        (uint256 deposits, ) = vault.userPosition(address(usde), alice);
        assertEq(deposits, 50e18);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RECEIVE ETH (for entropy fees)
    // ═══════════════════════════════════════════════════════════════════════════

    receive() external payable {}
}
