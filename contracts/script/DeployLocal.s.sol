// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {WelotVault} from "../src/WelotVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockLendlePool} from "../src/mocks/MockLendlePool.sol";
import {MockAToken} from "../src/mocks/MockAToken.sol";
import {LendleYieldVault} from "../src/yield/LendleYieldVault.sol";
import {MockFaucet} from "../src/mocks/MockFaucet.sol";
import {MockEntropyV2} from "../src/mocks/MockEntropyV2.sol";
import {IEntropyV2} from "../src/interfaces/IEntropyV2.sol";
import {ILendlePool} from "../src/interfaces/ILendlePool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title DeployLocalScript
/// @notice Deploys the full welot stack for local testing on Anvil
/// @dev Uses MockLendlePool and MockAToken to simulate Lendle behavior
contract DeployLocalScript is Script {
    function run() external {
        vm.startBroadcast();

        // Deploy mock tokens (USDC and USDT only)
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 usdt = new MockERC20("Tether USD", "USDT", 6);

        // Deploy mock Lendle Pool
        MockLendlePool lendlePool = new MockLendlePool();

        // Deploy mock aTokens
        MockAToken aUSDC = new MockAToken(IERC20(address(usdc)), "Aave USDC", "aUSDC");
        MockAToken aUSDT = new MockAToken(IERC20(address(usdt)), "Aave USDT", "aUSDT");

        // Initialize reserves with APYs (12% for USDC, 5% for USDT)
        lendlePool.initReserve(address(usdc), address(aUSDC), 0.12e27); // 12% APY
        lendlePool.initReserve(address(usdt), address(aUSDT), 0.05e27);  // 5% APY

        // Set APYs on aTokens
        aUSDC.setSupplyAPY(0.12e27); // 12%
        aUSDT.setSupplyAPY(0.05e27);  // 5%

        // Deploy Lendle Yield Vaults (ERC4626 wrappers)
        LendleYieldVault usdcVault = new LendleYieldVault(
            IERC20(address(usdc)),
            ILendlePool(address(lendlePool)),
            IERC20(address(aUSDC)),
            "Welot USDC Vault",
            "wUSDC"
        );

        LendleYieldVault usdtVault = new LendleYieldVault(
            IERC20(address(usdt)),
            ILendlePool(address(lendlePool)),
            IERC20(address(aUSDT)),
            "Welot USDT Vault",
            "wUSDT"
        );

        // Deploy mock Entropy (Pyth randomness)
        MockEntropyV2 entropy = new MockEntropyV2();

        // Deploy multi-token faucet (0 cooldown = one-time claim per token)
        MockFaucet faucet = new MockFaucet(0);
        faucet.addToken(address(usdc));
        faucet.addToken(address(usdt));
        
        // Deploy WelotVault
        WelotVault vault = new WelotVault(
            IEntropyV2(address(entropy)),
            7 days,  // Draw every week
            10       // Fixed 10 pools (auto-assigned)
        );

        // Add supported tokens with Lendle yield vaults
        vault.addSupportedToken(address(usdc), usdcVault);
        vault.addSupportedToken(address(usdt), usdtVault);

        // Fund the vault with some ETH for Entropy fees
        (bool sent,) = address(vault).call{value: 0.1 ether}("");
        require(sent, "ETH send failed");

        vm.stopBroadcast();

        // Print env vars for the frontend
        console2.log("\n--- Local deployment complete (USDC/USDT only with Lendle mocks) ---");
        console2.log("NEXT_PUBLIC_RPC_URL=http://127.0.0.1:8545");
        console2.log("NEXT_PUBLIC_CHAIN_ID=31337");
        console2.log("NEXT_PUBLIC_WELOT_VAULT=%s", address(vault));
        console2.log("NEXT_PUBLIC_ENTROPY=%s", address(entropy));
        console2.log("NEXT_PUBLIC_FAUCET=%s", address(faucet));
        console2.log("");
        console2.log("# Tokens (USDC/USDT)");
        console2.log("NEXT_PUBLIC_USDC=%s", address(usdc));
        console2.log("NEXT_PUBLIC_SUSDC=%s", address(usdcVault));
        console2.log("NEXT_PUBLIC_USDT=%s", address(usdt));
        console2.log("NEXT_PUBLIC_SUSDT=%s", address(usdtVault));
        console2.log("");
        console2.log("# Mock Lendle Infrastructure");
        console2.log("LENDLE_POOL=%s", address(lendlePool));
        console2.log("aUSDC=%s", address(aUSDC));
        console2.log("aUSDT=%s", address(aUSDT));
        console2.log("-----------------------------------------------------------------------\n");
    }
}
