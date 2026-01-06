// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {WelotVault} from "../src/WelotVault.sol";
import {IEntropyV2} from "../src/interfaces/IEntropyV2.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockERC4626} from "../src/mocks/MockERC4626.sol";
import {MockFaucet} from "../src/mocks/MockFaucet.sol";
import {MockEntropyV2} from "../src/mocks/MockEntropyV2.sol";

/// @title DeployMantleScript
/// @notice Deploys WelotVault to Mantle Network
/// @dev Uses real addresses for Mantle mainnet/testnet
contract DeployMantleScript is Script {
    // ═══════════════════════════════════════════════════════════════════
    // MANTLE MAINNET ADDRESSES
    // ═══════════════════════════════════════════════════════════════════
    
    // Pyth Entropy on Mantle
    // See: https://docs.pyth.network/entropy/contract-addresses
    address constant PYTH_ENTROPY_MAINNET = 0x98046Bd286715D3B0BC227Dd7a956b83D8978603;
    
    // mETH (Mantle's native LST)
    address constant METH_MAINNET = 0xcDA86A272531e8640cD7F1a92c01839911B90bb0;
    
    // USDe (Ethena's stablecoin) on Mantle
    address constant USDE_MAINNET = 0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34;
    // sUSDe (staked USDe) on Mantle
    address constant SUSDE_MAINNET = 0x211Cc4DD073734dA055fbF44a2b4667d5E5fE5d2;
    
    // USDC on Mantle
    address constant USDC_MAINNET = 0x09Bc4E0D864854c6aFB6eB9A9cdF58aC190D0dF9;
    
    // USDT on Mantle
    address constant USDT_MAINNET = 0x201EBa5CC46D216Ce6DC03F6a759e8E766e956aE;
    
    // WETH on Mantle
    address constant WETH_MAINNET = 0xdEAddEaDdeadDEadDEADDEAddEADDEAddead1111;

    // ═══════════════════════════════════════════════════════════════════
    // MANTLE SEPOLIA TESTNET ADDRESSES
    // ═══════════════════════════════════════════════════════════════════
    
    // NOTE: For Mantle Sepolia testing we deploy a local MockEntropyV2 on-chain so
    // the full flow works without relying on external providers.
    address constant PYTH_ENTROPY_TESTNET = 0x98046Bd286715D3B0BC227Dd7a956b83D8978603;



    function run() external {
        // Determine network
        bool isMainnet = block.chainid == 5000;
        bool isTestnet = block.chainid == 5003;
        
        require(isMainnet || isTestnet, "Unsupported network");
        vm.startBroadcast();

        // Default entropy address by network, but allow override via env to test real Pyth.
        address entropyAddr = isMainnet ? PYTH_ENTROPY_MAINNET : PYTH_ENTROPY_TESTNET;
        address entropyOverride = vm.envOr("ENTROPY_ADDRESS", address(0));
        if (entropyOverride != address(0)) {
            entropyAddr = entropyOverride;
        }

        // For testnet, deploy mocks so the app is fully testable.
        MockERC20 usde;
        MockERC4626 susde;
        MockERC20 usdc;
        MockERC4626 susdc;
        MockERC20 meth;
        MockERC4626 smeth;
        MockFaucet faucet;

        if (isTestnet && entropyOverride == address(0)) {
            // Mock tokens + yield vaults
            usde = new MockERC20("USDe", "USDe", 18);
            susde = new MockERC4626(usde, "Staked USDe", "sUSDe", 18);

            usdc = new MockERC20("USD Coin", "USDC", 6);
            susdc = new MockERC4626(usdc, "Staked USDC", "sUSDC", 6);

            meth = new MockERC20("Mantle ETH", "mETH", 18);
            smeth = new MockERC4626(meth, "Staked mETH", "smETH", 18);

            // Higher yield rate for testing: 10 tokens/minute => (10 / 60) tokens/sec.
            // For 18 decimals: 1e18 / 6. For 6 decimals: 1e6 / 6.
            susde.setYieldRatePerSecond(166666666666666666);
            susdc.setYieldRatePerSecond(166666);
            smeth.setYieldRatePerSecond(166666666666666666);

            // Mock entropy (free)
            MockEntropyV2 mockEntropy = new MockEntropyV2();
            entropyAddr = address(mockEntropy);


            // Faucet (0 cooldown = one-time claim per token)
            faucet = new MockFaucet(0);
            faucet.addToken(address(usde));
            faucet.addToken(address(usdc));
            faucet.addToken(address(meth));
        }

        // Deploy WelotVault
        WelotVault vault = new WelotVault(
            IEntropyV2(entropyAddr),
            7 days,  // Weekly draws (Friday noon UTC)
            64       // Max pools
        );

        // Optional: lock down upkeep execution to a specific keeper EOA.
        // If not set, `automationForwarder` stays as address(0) and anyone can call `performUpkeep`.
        address keeperForwarder = vm.envOr("AUTOMATION_FORWARDER", address(0));
        if (keeperForwarder != address(0)) {
            vault.setAutomationForwarder(keeperForwarder);
        }

        // For mainnet, add real yield vaults
        if (isMainnet) {
            // Add USDe/sUSDe (Ethena)
            vault.addSupportedToken(USDE_MAINNET, IERC4626(SUSDE_MAINNET));
            
            // Note: For mETH, we'd need a wrapper vault since mETH isn't ERC4626
            // vault.addSupportedToken(METH_MAINNET, IERC4626(methVaultAddr));
        }

        // For testnet, add mock tokens
        if (isTestnet) {
            vault.addSupportedToken(address(usde), susde);
            vault.addSupportedToken(address(usdc), susdc);
            vault.addSupportedToken(address(meth), smeth);
            // In test mode we rely on the on-chain mock entropy and direct calls.
        }

        // Fund vault with ETH for Entropy fees
        (bool sent,) = address(vault).call{value: 0.1 ether}("");
        require(sent, "ETH send failed");

        vm.stopBroadcast();

        console2.log("\n--- Mantle deployment complete ---");
        console2.log("Network: %s", isMainnet ? "Mainnet" : "Testnet");
        console2.log("Chain ID: %s", block.chainid);
        console2.log("");
        console2.log("NEXT_PUBLIC_WELOT_VAULT=%s", address(vault));
        console2.log("NEXT_PUBLIC_ENTROPY=%s", entropyAddr);

        if (isTestnet) {
            console2.log("NEXT_PUBLIC_FAUCET=%s", address(faucet));
            console2.log("");
            console2.log("# Tokens");
            console2.log("NEXT_PUBLIC_USDE=%s", address(usde));
            console2.log("NEXT_PUBLIC_SUSDE=%s", address(susde));
            console2.log("NEXT_PUBLIC_USDC=%s", address(usdc));
            console2.log("NEXT_PUBLIC_SUSDC=%s", address(susdc));
            console2.log("NEXT_PUBLIC_METH=%s", address(meth));
            console2.log("NEXT_PUBLIC_SMETH=%s", address(smeth));
        }
        
        if (isMainnet) {
            console2.log("");
            console2.log("# Supported Tokens");
            console2.log("NEXT_PUBLIC_USDE=%s", USDE_MAINNET);
            console2.log("NEXT_PUBLIC_SUSDE=%s", SUSDE_MAINNET);
        }
        
        console2.log("--------------------------------\n");
    }
}
