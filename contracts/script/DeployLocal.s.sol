// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {WelotVault} from "../src/WelotVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockERC4626} from "../src/mocks/MockERC4626.sol";
import {MockEntropyV2} from "../src/mocks/MockEntropyV2.sol";

contract DeployLocalScript is Script {
    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPk);

        MockERC20 usde = new MockERC20("USDe", "USDe", 18);
        MockERC4626 susde = new MockERC4626(usde, "sUSDe", "sUSDe", 18);
        MockEntropyV2 entropy = new MockEntropyV2(0.001 ether);

        WelotVault vault = new WelotVault(usde, susde, entropy, 7 days, 64);

        // Create one default pod so the UI can behave like a single weekly pool.
        vault.createPod(address(0));

        vm.stopBroadcast();

        // Print env vars for the frontend
        console2.log("\n--- Local deployment complete ---");
        console2.log("NEXT_PUBLIC_RPC_URL=http://127.0.0.1:8545");
        console2.log("NEXT_PUBLIC_WELOT_VAULT=%s", address(vault));
        console2.log("NEXT_PUBLIC_USDE=%s", address(usde));
        console2.log("NEXT_PUBLIC_SUSDE=%s", address(susde));
        console2.log("NEXT_PUBLIC_ENTROPY=%s", address(entropy));
        console2.log("--------------------------------\n");
    }
}
