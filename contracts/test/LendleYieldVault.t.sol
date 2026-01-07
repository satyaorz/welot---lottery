// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {LendleYieldVault} from "../src/yield/LendleYieldVault.sol";
import {ILendlePool} from "../src/interfaces/ILendlePool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title LendleYieldVault.t.sol
/// @notice Tests for the Lendle yield vault integration
/// @dev Uses Mantle mainnet fork to test against real Lendle contracts
contract LendleYieldVaultTest is Test {
    // Mantle Mainnet addresses
    address constant LENDLE_POOL = 0xCFa5aE7c2CE8Fadc6426C1ff872cA45378Fb7cF3;
    address constant USDC = 0x09Bc4E0D864854c6aFB6eB9A9cdF58aC190D0dF9;
    address constant USDT = 0x201EBa5CC46D216Ce6DC03F6a759e8E766e956aE;
    
    // aToken addresses (to be discovered via on-chain query)
    address constant aUSDC = 0x0000000000000000000000000000000000000000; // TBD
    address constant aUSDT = 0x0000000000000000000000000000000000000000; // TBD

    // Test accounts
    address user = makeAddr("user");
    address user2 = makeAddr("user2");
    
    // Contracts
    LendleYieldVault usdcVault;
    LendleYieldVault usdtVault;
    ILendlePool lendlePool;

    // Constants
    uint256 constant INITIAL_DEPOSIT = 1000e6; // 1000 USDC/USDT (6 decimals)
    uint256 constant FORK_BLOCK = 0; // Use latest block; set to specific block for reproducibility
    
    function setUp() public {
        // Skip tests if aToken addresses not yet configured
        if (aUSDC == address(0) || aUSDT == address(0)) {
            console2.log("Skipping tests: aToken addresses not yet configured");
            console2.log("Run the following commands to discover aToken addresses:");
            console2.log("  cast call --rpc-url https://rpc.mantle.xyz %s \"getReserveData(address)\" %s", LENDLE_POOL, USDC);
            console2.log("  cast call --rpc-url https://rpc.mantle.xyz %s \"getReserveData(address)\" %s", LENDLE_POOL, USDT);
            vm.skip(true);
            return;
        }

        // Fork Mantle mainnet
        string memory mantleRpc = vm.envOr("MANTLE_RPC_URL", string("https://rpc.mantle.xyz"));
        vm.createSelectFork(mantleRpc, FORK_BLOCK);
        
        lendlePool = ILendlePool(LENDLE_POOL);

        // Deploy vaults
        usdcVault = new LendleYieldVault(
            IERC20(USDC),
            lendlePool,
            IERC20(aUSDC),
            "Lendle USDC Vault",
            "lendleUSDC"
        );

        usdtVault = new LendleYieldVault(
            IERC20(USDT),
            lendlePool,
            IERC20(aUSDT),
            "Lendle USDT Vault",
            "lendleUSDT"
        );

        // Fund test users with USDC and USDT
        // We'll get tokens from a whale address on Mantle mainnet
        _fundUserWithTokens(user, USDC, INITIAL_DEPOSIT * 2);
        _fundUserWithTokens(user, USDT, INITIAL_DEPOSIT * 2);
        _fundUserWithTokens(user2, USDC, INITIAL_DEPOSIT);
        _fundUserWithTokens(user2, USDT, INITIAL_DEPOSIT);
    }

    /// @dev Helper to fund a user with tokens from a whale or by dealing
    function _fundUserWithTokens(address recipient, address token, uint256 amount) internal {
        // Try to find a whale with the token
        // For USDC/USDT on Mantle, we can use the Lendle aToken contract as a source
        address whale = token == USDC ? aUSDC : aUSDT;
        
        // If whale has tokens, transfer from whale; otherwise use vm.deal cheatcode
        uint256 whaleBalance = IERC20(token).balanceOf(whale);
        if (whaleBalance >= amount) {
            vm.prank(whale);
            IERC20(token).transfer(recipient, amount);
        } else {
            // Fallback: use vm.deal to mint tokens (only works if token allows it)
            deal(token, recipient, amount);
        }
    }

    /// @notice Test: Basic deposit into USDC vault
    function test_DepositUSDC() public {
        vm.startPrank(user);
        
        uint256 depositAmount = INITIAL_DEPOSIT;
        IERC20(USDC).approve(address(usdcVault), depositAmount);
        
        uint256 sharesBefore = usdcVault.balanceOf(user);
        usdcVault.deposit(depositAmount, user);
        uint256 sharesAfter = usdcVault.balanceOf(user);
        
        assertGt(sharesAfter, sharesBefore, "User should receive vault shares");
        assertEq(usdcVault.totalAssets(), depositAmount, "Vault totalAssets should equal deposit");
        
        vm.stopPrank();
    }

    /// @notice Test: Basic deposit into USDT vault
    function test_DepositUSDT() public {
        vm.startPrank(user);
        
        uint256 depositAmount = INITIAL_DEPOSIT;
        IERC20(USDT).approve(address(usdtVault), depositAmount);
        
        uint256 sharesBefore = usdtVault.balanceOf(user);
        usdtVault.deposit(depositAmount, user);
        uint256 sharesAfter = usdtVault.balanceOf(user);
        
        assertGt(sharesAfter, sharesBefore, "User should receive vault shares");
        assertEq(usdtVault.totalAssets(), depositAmount, "Vault totalAssets should equal deposit");
        
        vm.stopPrank();
    }

    /// @notice Test: Yield accrual over time
    function test_YieldAccrual() public {
        vm.startPrank(user);
        
        uint256 depositAmount = INITIAL_DEPOSIT;
        IERC20(USDC).approve(address(usdcVault), depositAmount);
        usdcVault.deposit(depositAmount, user);
        
        uint256 assetsBefore = usdcVault.totalAssets();
        
        // Advance time by 1 week
        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + (7 days / 2)); // Assuming ~2 sec block time on Mantle
        
        // Interact with Lendle to trigger interest accrual (deposit 1 wei to another user)
        deal(USDC, user2, 100);
        vm.stopPrank();
        vm.startPrank(user2);
        IERC20(USDC).approve(LENDLE_POOL, 100);
        lendlePool.supply(USDC, 100, user2, 0);
        vm.stopPrank();
        
        uint256 assetsAfter = usdcVault.totalAssets();
        
        // Yield should have increased
        assertGt(assetsAfter, assetsBefore, "Vault should have earned yield after 1 week");
        console2.log("Yield earned (USDC): %s", assetsAfter - assetsBefore);
    }

    /// @notice Test: Withdraw from vault
    function test_Withdraw() public {
        vm.startPrank(user);
        
        uint256 depositAmount = INITIAL_DEPOSIT;
        IERC20(USDC).approve(address(usdcVault), depositAmount);
        usdcVault.deposit(depositAmount, user);
        
        uint256 usdcBefore = IERC20(USDC).balanceOf(user);
        uint256 sharesBefore = usdcVault.balanceOf(user);
        
        usdcVault.withdraw(depositAmount / 2, user, user);
        
        uint256 usdcAfter = IERC20(USDC).balanceOf(user);
        uint256 sharesAfter = usdcVault.balanceOf(user);
        
        assertGt(usdcAfter, usdcBefore, "User should receive USDC");
        assertLt(sharesAfter, sharesBefore, "Shares should decrease");
        assertEq(usdcAfter - usdcBefore, depositAmount / 2, "Should withdraw correct amount");
        
        vm.stopPrank();
    }

    /// @notice Test: maxWithdraw respects available liquidity
    function test_MaxWithdraw() public {
        vm.startPrank(user);
        
        uint256 depositAmount = INITIAL_DEPOSIT;
        IERC20(USDC).approve(address(usdcVault), depositAmount);
        usdcVault.deposit(depositAmount, user);
        
        uint256 maxWithdrawable = usdcVault.maxWithdraw(user);
        
        // Should be able to withdraw up to the deposited amount
        assertGe(maxWithdrawable, depositAmount, "Max withdraw should be at least deposit amount");
        
        // Actual max withdraw is limited by Lendle pool liquidity
        uint256 availableLiquidity = IERC20(USDC).balanceOf(aUSDC);
        console2.log("Available Lendle liquidity (USDC): %s", availableLiquidity);
        assertLe(maxWithdrawable, availableLiquidity, "Max withdraw capped by pool liquidity");
        
        vm.stopPrank();
    }

    /// @notice Test: Multiple users depositing
    function test_MultipleUsers() public {
        // User 1 deposits
        vm.startPrank(user);
        IERC20(USDC).approve(address(usdcVault), INITIAL_DEPOSIT);
        usdcVault.deposit(INITIAL_DEPOSIT, user);
        vm.stopPrank();
        
        // User 2 deposits
        vm.startPrank(user2);
        IERC20(USDC).approve(address(usdcVault), INITIAL_DEPOSIT);
        usdcVault.deposit(INITIAL_DEPOSIT, user2);
        vm.stopPrank();
        
        // Total assets should be sum of deposits
        assertEq(usdcVault.totalAssets(), INITIAL_DEPOSIT * 2, "Total assets should be sum");
        
        // Each user should have roughly half the shares (may differ slightly due to rounding)
        uint256 user1Shares = usdcVault.balanceOf(user);
        uint256 user2Shares = usdcVault.balanceOf(user2);
        assertApproxEqRel(user1Shares, user2Shares, 1e15, "Users should have similar shares");
    }

    /// @notice Test: Redeem shares
    function test_Redeem() public {
        vm.startPrank(user);
        
        uint256 depositAmount = INITIAL_DEPOSIT;
        IERC20(USDC).approve(address(usdcVault), depositAmount);
        uint256 shares = usdcVault.deposit(depositAmount, user);
        
        uint256 usdcBefore = IERC20(USDC).balanceOf(user);
        
        // Redeem half the shares
        usdcVault.redeem(shares / 2, user, user);
        
        uint256 usdcAfter = IERC20(USDC).balanceOf(user);
        
        assertGt(usdcAfter, usdcBefore, "User should receive USDC from redeem");
        assertEq(usdcVault.balanceOf(user), shares / 2, "Half shares should remain");
        
        vm.stopPrank();
    }
}
