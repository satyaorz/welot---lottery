// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script, console2} from "forge-std/Script.sol";

import {WelotVault} from "../src/WelotVault.sol";
import {MockEntropyV2} from "../src/mocks/MockEntropyV2.sol";

/// @notice Helper script for testnets using MockEntropyV2.
/// Runs: closeEpoch -> requestRandomness -> fulfill -> finalizeDraw
///
/// Env vars:
/// - WELOT_VAULT
/// - ENTROPY
/// - MOCK_ENTROPY (optional, bool; defaults to true)
/// - RANDOM_WORD (optional, uint256; defaults to 1)
contract RunDrawScript is Script {
    error RunDrawScript__NeedSeq();

    function run() external {
        address vaultAddr = vm.envAddress("WELOT_VAULT");
        address entropyAddr = vm.envAddress("ENTROPY");
        bool mockEntropyMode = vm.envOr("MOCK_ENTROPY", true);
        uint256 randomWord = vm.envOr("RANDOM_WORD", uint256(1));

        WelotVault vault = WelotVault(payable(vaultAddr));
        MockEntropyV2 entropy = MockEntropyV2(entropyAddr);

        vm.startBroadcast();

        // 1) Close the epoch (must be past end time)
        try vault.closeEpoch() {
            console2.log("closeEpoch() ok");
        } catch {
            console2.log("closeEpoch() reverted (maybe too early or already closed)");
        }

        // 2) Request randomness (sequence number is stored in the epoch)
        uint64 seq;
        uint256 epochId = vault.currentEpochId();
        try vault.requestRandomness() {
            (,,, uint64 entropySequence,,,) = vault.epochs(epochId);
            seq = entropySequence;
            console2.log("requestRandomness() ok, epoch:", epochId);
            console2.log("entropySequence:", uint256(seq));
        } catch {
            console2.log("requestRandomness() reverted (maybe already requested)");
        }

        if (!mockEntropyMode) {
            console2.log("MOCK_ENTROPY=false; waiting for real Entropy callback, skipping local fulfill/finalize");
            vm.stopBroadcast();
            return;
        }

        if (seq == 0) {
            uint256 forcedSeq = vm.envOr("RANDOM_SEQ", uint256(0));
            if (forcedSeq == 0) revert RunDrawScript__NeedSeq();
            seq = uint64(forcedSeq);
        }

        // 3) Fulfill with deterministic randomness
        bytes32 randomBytes = bytes32(randomWord);
        entropy.fulfill(seq, randomBytes);
        console2.log("entropy.fulfill() ok");

        // 4) Finalize draw
        vault.finalizeDraw();
        console2.log("finalizeDraw() ok");

        vm.stopBroadcast();
    }
}
