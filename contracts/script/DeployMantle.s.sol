// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {WelotVault} from "../src/WelotVault.sol";
import {IEntropyV2} from "../src/interfaces/IEntropyV2.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockLendlePool} from "../src/mocks/MockLendlePool.sol";
import {MockAToken} from "../src/mocks/MockAToken.sol";
import {MockFaucet} from "../src/mocks/MockFaucet.sol";
import {MockEntropyV2} from "../src/mocks/MockEntropyV2.sol";

import {LendleYieldVault} from "../src/yield/LendleYieldVault.sol";
import {ILendlePool} from "../src/interfaces/ILendlePool.sol";

/// @title DeployMantleScript
/// @notice Deploys WelotVault to Mantle Network (USDC/USDT only with Lendle)
/// @dev Uses real Lendle addresses for mainnet, mocks for testnet
contract DeployMantleScript is Script {
    // ═══════════════════════════════════════════════════════════════════
    // MANTLE MAINNET ADDRESSES
    // ═══════════════════════════════════════════════════════════════════
    
    // Pyth Entropy on Mantle
    address constant PYTH_ENTROPY_MAINNET = 0x98046Bd286715D3B0BC227Dd7a956b83D8978603;
    
    // USDC on Mantle
    address constant USDC_MAINNET = 0x09Bc4E0D864854c6aFB6eB9A9cdF58aC190D0dF9;
    
    // USDT on Mantle
    address constant USDT_MAINNET = 0x201EBa5CC46D216Ce6DC03F6a759e8E766e956aE;

    // Lendle (Aave V3 fork) on Mantle Mainnet
    // Pool contract address (verified from Lendle docs)
    address constant LENDLE_POOL_MAINNET = 0xCFa5aE7c2CE8Fadc6426C1ff872cA45378Fb7cF3;
    
    // aToken addresses for USDC and USDT in Lendle
    // TODO: These must be retrieved via on-chain query before mainnet deployment:
    // cast call --rpc-url https://rpc.mantle.xyz 0xCFa5aE7c2CE8Fadc6426C1ff872cA45378Fb7cF3 \
    //   "getReserveData(address)" 0x09Bc4E0D864854c6aFB6eB9A9cdF58aC190D0dF9
    address constant LENDLE_aUSDC_MAINNET = 0x0000000000000000000000000000000000000000; // TBD
    address constant LENDLE_aUSDT_MAINNET = 0x0000000000000000000000000000000000000000; // TBD

    // ═══════════════════════════════════════════════════════════════════
    // MANTLE SEPOLIA TESTNET ADDRESSES
    // ═══════════════════════════════════════════════════════════════════
    
    // Pyth Entropy V2 on Mantle Sepolia
    address constant PYTH_ENTROPY_TESTNET = 0x98046Bd286715D3B0BC227Dd7a956b83D8978603;

    // Testnet state (mocks)
    MockERC20 public usdc;
    MockERC20 public usdt;
    MockLendlePool public lendlePool;
    MockAToken public aUSDC;
    MockAToken public aUSDT;
    MockFaucet public faucet;

    function run() external {
        // Determine network
        bool isMainnet = block.chainid == 5000;
        bool isTestnet = block.chainid == 5003;
        
        require(isMainnet || isTestnet, "Unsupported network");
        vm.startBroadcast();

        // Entropy address (allow override via env)
        address entropyAddr = isMainnet ? PYTH_ENTROPY_MAINNET : PYTH_ENTROPY_TESTNET;
        address entropyOverride = vm.envOr("ENTROPY_ADDRESS", address(0));
        if (entropyOverride != address(0)) {
            entropyAddr = entropyOverride;
        }

        bool deployMockEntropy = vm.envOr("DEPLOY_MOCK_ENTROPY", false);
        
        // Lendle yield vaults
        LendleYieldVault usdcVault;
        LendleYieldVault usdtVault;

        if (isTestnet) {
            // Deploy mock tokens
            usdc = new MockERC20("USD Coin", "USDC", 6);
            usdt = new MockERC20("Tether USD", "USDT", 6);

            // Deploy mock Lendle Pool
            lendlePool = new MockLendlePool();

            // Deploy mock aTokens
            aUSDC = new MockAToken(IERC20(address(usdc)), "Aave USDC", "aUSDC");
            aUSDT = new MockAToken(IERC20(address(usdt)), "Aave USDT", "aUSDT");

            // Initialize reserves with realistic APYs
            lendlePool.initReserve(address(usdc), address(aUSDC), 0.12e27); // 12% APY
            lendlePool.initReserve(address(usdt), address(aUSDT), 0.05e27);  // 5% APY

            // Set APYs on aTokens
            aUSDC.setSupplyAPY(0.12e27);
            aUSDT.setSupplyAPY(0.05e27);

            // Deploy Lendle yield vaults
            usdcVault = new LendleYieldVault(
                IERC20(address(usdc)),
                ILendlePool(address(lendlePool)),
                IERC20(address(aUSDC)),
                "Welot USDC Vault",
                "wUSDC"
            );

            usdtVault = new LendleYieldVault(
                IERC20(address(usdt)),
                ILendlePool(address(lendlePool)),
                IERC20(address(aUSDT)),
                "Welot USDT Vault",
                "wUSDT"
            );

            // Deploy faucet
            faucet = new MockFaucet(0);
            faucet.addToken(address(usdc));
            faucet.addToken(address(usdt));

            // Optional mock entropy
            if (deployMockEntropy && entropyOverride == address(0)) {
                MockEntropyV2 mockEntropy = new MockEntropyV2();
                entropyAddr = address(mockEntropy);
            }
        }

        // Deploy WelotVault
        WelotVault vault = new WelotVault(
            IEntropyV2(entropyAddr),
            7 days,  // Weekly draws
            10       // Fixed 10 pools (auto-assigned)
        );

        // Set automation forwarder (optional)
        address keeperForwarder = vm.envOr("AUTOMATION_FORWARDER", address(0));
        if (keeperForwarder != address(0)) {
            vault.setAutomationForwarder(keeperForwarder);
        }

        // Add supported tokens
        if (isMainnet) {
            // Mainnet: Deploy real Lendle vaults (only if aToken addresses configured)
            require(LENDLE_aUSDC_MAINNET != address(0), "LENDLE_aUSDC_MAINNET not set");
            require(LENDLE_aUSDT_MAINNET != address(0), "LENDLE_aUSDT_MAINNET not set");

            usdcVault = new LendleYieldVault(
                IERC20(USDC_MAINNET),
                ILendlePool(LENDLE_POOL_MAINNET),
                IERC20(LENDLE_aUSDC_MAINNET),
                "Lendle USDC Vault",
                "lendleUSDC"
            );

            usdtVault = new LendleYieldVault(
                IERC20(USDT_MAINNET),
                ILendlePool(LENDLE_POOL_MAINNET),
                IERC20(LENDLE_aUSDT_MAINNET),
                "Lendle USDT Vault",
                "lendleUSDT"
            );

            vault.addSupportedToken(USDC_MAINNET, IERC4626(address(usdcVault)));
            vault.addSupportedToken(USDT_MAINNET, IERC4626(address(usdtVault)));
        }

        if (isTestnet) {
            vault.addSupportedToken(address(usdc), IERC4626(address(usdcVault)));
            vault.addSupportedToken(address(usdt), IERC4626(address(usdtVault)));
        }

        // Fund vault with ETH for Entropy fees
        (bool sent,) = address(vault).call{value: 0.1 ether}("");
        require(sent, "ETH send failed");

        vm.stopBroadcast();

        // Print deployment info
        console2.log("\n--- Mantle deployment complete (USDC/USDT + Lendle) ---");
        console2.log("Network: %s", isMainnet ? "Mainnet" : "Testnet");
        console2.log("Chain ID: %s", block.chainid);
        console2.log("");
        console2.log("NEXT_PUBLIC_WELOT_VAULT=%s", address(vault));
        console2.log("NEXT_PUBLIC_ENTROPY=%s", entropyAddr);

        if (isTestnet) {
            console2.log("NEXT_PUBLIC_FAUCET=%s", address(faucet));
            console2.log("");
            console2.log("# Tokens (Testnet Mocks)");
            console2.log("NEXT_PUBLIC_USDC=%s", address(usdc));
            console2.log("NEXT_PUBLIC_SUSDC=%s", address(usdcVault));
            console2.log("NEXT_PUBLIC_USDT=%s", address(usdt));
            console2.log("NEXT_PUBLIC_SUSDT=%s", address(usdtVault));
            console2.log("");
            console2.log("# Mock Lendle Infrastructure");
            console2.log("LENDLE_POOL=%s", address(lendlePool));
            console2.log("aUSDC=%s", address(aUSDC));
            console2.log("aUSDT=%s", address(aUSDT));
        }
        
        if (isMainnet) {
            console2.log("");
            console2.log("# Real Tokens (Mainnet)");
            console2.log("NEXT_PUBLIC_USDC=%s", USDC_MAINNET);
            console2.log("NEXT_PUBLIC_SUSDC=%s", address(usdcVault));
            console2.log("NEXT_PUBLIC_USDT=%s", USDT_MAINNET);
            console2.log("NEXT_PUBLIC_SUSDT=%s", address(usdtVault));
            console2.log("");
            console2.log("# Real Lendle Infrastructure");
            console2.log("LENDLE_POOL=%s", LENDLE_POOL_MAINNET);
            console2.log("aUSDC=%s", LENDLE_aUSDC_MAINNET);
            console2.log("aUSDT=%s", LENDLE_aUSDT_MAINNET);
        }
        
        console2.log("---------------------------------------------------------------\n");
    }
}
