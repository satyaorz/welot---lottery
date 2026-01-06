// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {WelotVault} from "../src/WelotVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC4626} from "./mocks/MockERC4626.sol";
import {MockEntropyV2} from "./mocks/MockEntropyV2.sol";

contract WelotVaultTest is Test {
    MockERC20 usde;
    MockERC4626 susde;
    MockEntropyV2 entropy;
    WelotVault vault;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        usde = new MockERC20("USDe", "USDe", 18);
        susde = new MockERC4626(usde, "sUSDe", "sUSDe", 18);
        entropy = new MockEntropyV2(0.01 ether);

        vault = new WelotVault(usde, susde, entropy, 7 days, 32);

        usde.mint(alice, 1_000e18);
        usde.mint(bob, 1_000e18);

        vm.prank(alice);
        usde.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        usde.approve(address(vault), type(uint256).max);

        // Seed some ETH for randomness fees
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
    }

    function test_DepositWithdraw_PrincipalTracks() public {
        uint256 pod = vault.createPod(alice);

        vm.prank(alice);
        vault.deposit(100e18, pod);

        assertEq(vault.totalPrincipal(), 100e18);

        vm.prank(alice);
        vault.withdraw(40e18, pod);

        assertEq(vault.totalPrincipal(), 60e18);
    }

    function test_PrizePotFromYieldOnly() public {
        uint256 podA = vault.createPod(alice);

        vm.prank(alice);
        vault.deposit(100e18, podA);

        // Donate yield into sUSDe
        usde.mint(address(this), 10e18);
        usde.approve(address(susde), type(uint256).max);
        susde.donateYield(10e18);

        assertEq(vault.prizePot(), 10e18);

        // Allocate prize to liability by finalizing epoch
        _closeRequestFulfillFinalize(bytes32(uint256(123)));

        // After allocation, prize pot should be zero because it's now liability
        assertEq(vault.prizePot(), 0);

        // Alice can claim the prize
        vm.prank(alice);
        uint256 claimed = vault.claimPrize(podA, alice);
        assertEq(claimed, 10e18);

        // Liability cleared
        assertEq(vault.totalPrizeLiability(), 0);
    }

    function test_TwoPods_WinnerGetsAllocated() public {
        uint256 podA = vault.createPod(alice);
        uint256 podB = vault.createPod(bob);

        vm.prank(alice);
        vault.deposit(100e18, podA);

        vm.prank(bob);
        vault.deposit(300e18, podB);

        // Add yield
        usde.mint(address(this), 40e18);
        usde.approve(address(susde), type(uint256).max);
        susde.donateYield(40e18);

        // Pick randomness so Bob's pod wins, regardless of podIds ordering.
        uint256 id0 = vault.podIds(0);
        uint256 id1 = vault.podIds(1);

        (,,,,,, uint256 w0) = vault.pods(id0);
        (,,,,,, uint256 w1) = vault.pods(id1);
        uint256 total = w0 + w1;
        assertGt(total, 0);

        uint256 r;
        if (id0 == podB) {
            // Bob is in the first bucket.
            r = 0;
        } else {
            // Bob is in the second bucket.
            r = w0 + 1;
        }
        _closeRequestFulfillFinalize(bytes32(r));

        // Bob should have claimable rewards in podB, Alice in podA should have 0.
        (, uint256 aliceClaimable) = vault.getUserPosition(podA, alice);
        (, uint256 bobClaimable) = vault.getUserPosition(podB, bob);

        assertEq(aliceClaimable, 0);
        assertApproxEqAbs(bobClaimable, 40e18, 200);
    }

    function _closeRequestFulfillFinalize(bytes32 rand) internal {
        // move time forward to epoch end
        (, uint64 end,,,,,) = vault.epochs(vault.currentEpochId());
        vm.warp(uint256(end) + 1);

        vault.closeEpoch();

        // request randomness
        vm.prank(alice);
        uint64 seq = vault.requestRandomness{value: entropy.fee()}();

        // fulfill
        entropy.fulfill(seq, rand);

        // finalize
        vault.finalizeEpoch();
    }
}
