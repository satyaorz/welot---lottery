// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {WelotVault} from "../src/WelotVault.sol";
import {IEntropyV2} from "../src/interfaces/IEntropyV2.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

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
    
    address constant PYTH_ENTROPY_TESTNET = 0x98046Bd286715D3B0BC227Dd7a956b83D8978603;

    function run() external {
        // Determine network
        bool isMainnet = block.chainid == 5000;
        bool isTestnet = block.chainid == 5003;
        
        require(isMainnet || isTestnet, "Unsupported network");

        address entropyAddr = isMainnet ? PYTH_ENTROPY_MAINNET : PYTH_ENTROPY_TESTNET;

        vm.startBroadcast();

        // Deploy WelotVault
        WelotVault vault = new WelotVault(
            IEntropyV2(entropyAddr),
            7 days,  // Weekly draws
            64       // Max pools
        );

        // For mainnet, add real yield vaults
        if (isMainnet) {
            // Add USDe/sUSDe (Ethena)
            vault.addSupportedToken(USDE_MAINNET, IERC4626(SUSDE_MAINNET));
            
            // Note: For mETH, we'd need a wrapper vault since mETH isn't ERC4626
            // vault.addSupportedToken(METH_MAINNET, IERC4626(methVaultAddr));
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
        
        if (isMainnet) {
            console2.log("");
            console2.log("# Supported Tokens");
            console2.log("NEXT_PUBLIC_USDE=%s", USDE_MAINNET);
            console2.log("NEXT_PUBLIC_SUSDE=%s", SUSDE_MAINNET);
        }
        
        console2.log("--------------------------------\n");
    }
}
