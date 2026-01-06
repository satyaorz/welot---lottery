// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {WelotVault} from "../src/WelotVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockERC4626} from "../src/mocks/MockERC4626.sol";
import {MockFaucet} from "../src/mocks/MockFaucet.sol";
import {MockEntropyV2} from "../src/mocks/MockEntropyV2.sol";
import {IEntropyV2} from "../src/interfaces/IEntropyV2.sol";

/// @title DeployLocalScript
/// @notice Deploys the full welot stack for local testing on Anvil
contract DeployLocalScript is Script {
    function run() external {
        vm.startBroadcast();

        // Deploy mock tokens
        MockERC20 usde = new MockERC20("USDe", "USDe", 18);
        MockERC4626 susde = new MockERC4626(usde, "Staked USDe", "sUSDe", 18);

        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626 susdc = new MockERC4626(usdc, "Staked USDC", "sUSDC", 6);

        MockERC20 meth = new MockERC20("Mantle ETH", "mETH", 18);
        MockERC4626 smeth = new MockERC4626(meth, "Staked mETH", "smETH", 18);

        // Deploy mock Entropy (Pyth randomness)
        MockEntropyV2 entropy = new MockEntropyV2();

        // Deploy multi-token faucet (0 cooldown = one-time claim per token)
        MockFaucet faucet = new MockFaucet(0);
        faucet.addToken(address(usde));
        faucet.addToken(address(usdc));
        faucet.addToken(address(meth));
        
        // Deploy WelotVault
        WelotVault vault = new WelotVault(
            IEntropyV2(address(entropy)),
            7 days,  // Draw every week
            64       // Max 64 pools
        );

        // Add supported tokens
        vault.addSupportedToken(address(usde), susde);
        vault.addSupportedToken(address(usdc), susdc);
        vault.addSupportedToken(address(meth), smeth);

        // Fund the vault with some ETH for Entropy fees
        (bool sent,) = address(vault).call{value: 0.1 ether}("");
        require(sent, "ETH send failed");

        vm.stopBroadcast();

        // Print env vars for the frontend
        console2.log("\n--- Local deployment complete ---");
        console2.log("NEXT_PUBLIC_RPC_URL=http://127.0.0.1:8545");
        console2.log("NEXT_PUBLIC_CHAIN_ID=31337");
        console2.log("NEXT_PUBLIC_WELOT_VAULT=%s", address(vault));
        console2.log("NEXT_PUBLIC_ENTROPY=%s", address(entropy));
        console2.log("NEXT_PUBLIC_FAUCET=%s", address(faucet));
        console2.log("");
        console2.log("# Tokens");
        console2.log("NEXT_PUBLIC_USDE=%s", address(usde));
        console2.log("NEXT_PUBLIC_SUSDE=%s", address(susde));
        console2.log("NEXT_PUBLIC_USDC=%s", address(usdc));
        console2.log("NEXT_PUBLIC_SUSDC=%s", address(susdc));
        console2.log("NEXT_PUBLIC_METH=%s", address(meth));
        console2.log("NEXT_PUBLIC_SMETH=%s", address(smeth));
        console2.log("--------------------------------\n");
    }
}
