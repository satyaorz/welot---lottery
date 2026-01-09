// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {WelotVault} from "../src/WelotVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockERC4626} from "../src/mocks/MockERC4626.sol";
import {MockEntropyV2} from "../src/mocks/MockEntropyV2.sol";
import {MockFaucet} from "../src/mocks/MockFaucet.sol";
import {MockLendlePool} from "../src/mocks/MockLendlePool.sol";
import {MockAToken} from "../src/mocks/MockAToken.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IEntropyV2} from "../src/interfaces/IEntropyV2.sol";

contract SecurityConfigAndMocksTest is Test {
    MockEntropyV2 internal entropy;
    WelotVault internal vault;

    MockERC20 internal usdc;
    MockERC4626 internal susdc;

    address internal alice = address(0xA11CE);
    address internal keeper = address(0xB0B);

    function setUp() public {
        entropy = new MockEntropyV2();

        usdc = new MockERC20("USDC", "USDC", 6);
        susdc = new MockERC4626(usdc, "sUSDC", "sUSDC", 6);
        susdc.setYieldRatePerSecond(0);

        vault = new WelotVault(IEntropyV2(address(entropy)), 7 days, 10);
        vault.addSupportedToken(address(usdc), IERC4626(address(susdc)));

        usdc.mint(alice, 1_000e6);
        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);
    }

    function test_Constructor_revertsOnZeroEntropy() public {
        vm.expectRevert(WelotVault.WelotVault__InvalidEntropy.selector);
        new WelotVault(IEntropyV2(address(0)), 7 days, 10);
    }

    function test_Constructor_revertsOnZeroDrawInterval() public {
        vm.expectRevert(WelotVault.WelotVault__InvalidDrawInterval.selector);
        new WelotVault(IEntropyV2(address(entropy)), 0, 10);
    }

    function test_AddSupportedToken_revertsOnZeroToken() public {
        vm.expectRevert(WelotVault.WelotVault__InvalidToken.selector);
        vault.addSupportedToken(address(0), IERC4626(address(susdc)));
    }

    function test_AddSupportedToken_revertsOnDuplicate() public {
        vm.expectRevert(WelotVault.WelotVault__TokenAlreadySupported.selector);
        vault.addSupportedToken(address(usdc), IERC4626(address(susdc)));
    }

    function test_AddSupportedToken_revertsOnAssetMismatch() public {
        MockERC20 other = new MockERC20("OTHER", "OTHER", 6);
        MockERC4626 sOther = new MockERC4626(other, "sOTHER", "sOTHER", 6);
        sOther.setYieldRatePerSecond(0);

        vm.expectRevert(WelotVault.WelotVault__InvalidToken.selector);
        // `other` is not yet supported, but `susdc.asset()` is USDC, so this should revert.
        vault.addSupportedToken(address(other), IERC4626(address(susdc)));
    }

    function test_RemoveSupportedToken_revertsWhenHasDeposits() public {
        vm.prank(alice);
        vault.deposit(address(usdc), 100e6);

        vm.expectRevert(WelotVault.WelotVault__HasDeposits.selector);
        vault.removeSupportedToken(address(usdc));
    }

    function test_RemoveSupportedToken_disablesTokenAndBlocksDeposits() public {
        // Remove works when no deposits exist.
        vault.removeSupportedToken(address(usdc));

        vm.prank(alice);
        vm.expectRevert(WelotVault.WelotVault__TokenNotSupported.selector);
        vault.deposit(address(usdc), 1e6);
    }

    function test_PerformUpkeep_restrictedToForwarderWhenSet() public {
        vault.setAutomationForwarder(keeper);
        assertEq(vault.automationForwarder(), keeper);

        vm.expectRevert(WelotVault.WelotVault__NotAutomationForwarder.selector);
        // Use a no-op action to avoid epoch-timing related reverts.
        vault.performUpkeep(abi.encode(uint8(0)));

        // Forwarder can call.
        vm.prank(keeper);
        vault.performUpkeep(abi.encode(uint8(0)));
    }

    function test_RequestRandomness_revertsWhenInsufficientFeeBalance() public {
        // Make fee non-zero.
        entropy.setFee(1);

        // Advance to closeable time.
        vm.warp(block.timestamp + 8 days);
        vault.closeEpoch();

        // No ETH in vault, should revert.
        vm.expectRevert(WelotVault.WelotVault__InsufficientFee.selector);
        vault.requestRandomness();
    }

    function test_EntropyCallback_ignoresNonEntropySender() public {
        // Close + request randomness.
        vm.warp(block.timestamp + 8 days);
        vault.closeEpoch();
        vault.requestRandomness();

        assertEq(uint8(vault.epochStatus()), uint8(WelotVault.EpochStatus.RandomnessRequested));

        // Call callback from non-entropy address, should not change status.
        vault.entropyCallback(1, address(0x1234), bytes32(uint256(123)));
        assertEq(uint8(vault.epochStatus()), uint8(WelotVault.EpochStatus.RandomnessRequested));
    }

    function test_FinalizeDraw_revertsBeforeRandomnessReady() public {
        vm.expectRevert(WelotVault.WelotVault__DrawNotReady.selector);
        vault.finalizeDraw();
    }

    function test_Pause_blocksDeposits_butWithdrawStillWorks() public {
        vm.prank(alice);
        vault.deposit(address(usdc), 100e6);

        vault.pause();

        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(address(usdc), 1e6);

        // Withdraw path is intentionally allowed (documented by this test).
        vm.prank(alice);
        vault.withdraw(address(usdc), 50e6);

        (uint256 deposits,) = vault.userPosition(address(usdc), alice);
        assertEq(deposits, 50e6);
    }

    // ---- Mock-specific error-path tests ----

    function test_MockEntropyV2_fulfillWithoutRequest_reverts() public {
        vm.expectRevert(MockEntropyV2.MockEntropyV2__NoRequest.selector);
        entropy.fulfill(999, bytes32(uint256(1)));
    }

    function test_MockFaucet_errors() public {
        MockFaucet faucet = new MockFaucet(0);

        // Non-owner addToken
        vm.prank(alice);
        vm.expectRevert(MockFaucet.MockFaucet__NotOwner.selector);
        faucet.addToken(address(usdc));

        // Claim non-registered token
        vm.prank(alice);
        vm.expectRevert(MockFaucet.MockFaucet__TokenNotRegistered.selector);
        faucet.claim(address(usdc));

        // Register token + claim twice (cooldown=0 one-time)
        faucet.addToken(address(usdc));
        vm.prank(alice);
        faucet.claim(address(usdc));
        vm.prank(alice);
        vm.expectRevert(MockFaucet.MockFaucet__ClaimCooldown.selector);
        faucet.claim(address(usdc));
    }

    function test_MockLendlePool_supplyWithoutReserve_reverts() public {
        MockLendlePool pool = new MockLendlePool();

        usdc.mint(alice, 10e6);
        vm.prank(alice);
        usdc.approve(address(pool), type(uint256).max);

        vm.prank(alice);
        vm.expectRevert(MockLendlePool.MockLendlePool__ReserveNotActive.selector);
        pool.supply(address(usdc), 1e6, alice, 0);
    }

    function test_MockLendlePool_withdrawInsufficientLiquidity_reverts() public {
        MockLendlePool pool = new MockLendlePool();
        MockAToken aUSDC = new MockAToken(usdc, address(pool), "Aave USDC", "aUSDC");
        pool.initReserve(address(usdc), address(aUSDC), 0.12e27);

        usdc.mint(alice, 100e6);
        vm.prank(alice);
        usdc.approve(address(pool), type(uint256).max);

        vm.prank(alice);
        pool.supply(address(usdc), 100e6, alice, 0);

        // Drain underlying from aToken contract to force insufficient liquidity.
        usdc.burn(address(aUSDC), 99e6);

        vm.prank(alice);
        vm.expectRevert(MockLendlePool.MockLendlePool__InsufficientLiquidity.selector);
        pool.withdraw(address(usdc), 100e6, alice);
    }
}
