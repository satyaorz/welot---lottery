# Lendle/Aave V3 Mechanics - Technical Reference

## Overview
Lendle is an Aave V3 fork on Mantle Network. Understanding its mechanics is crucial for implementing yield generation and withdrawals.

## Core Concepts

### 1. aToken (Interest-Bearing Tokens)
When users supply assets to Lendle, they receive aTokens (e.g., aUSDC, aUSDT) in return.

**Key Characteristics:**
- **Rebasing tokens**: Balance increases automatically over time WITHOUT transfers
- **Exchange rate model**: Uses internal liquidity index for yield accrual
- **No explicit transfers**: Yield accrues through index growth, not token transfers

### 2. Liquidity Index & Balance Calculation
The magic behind aToken balance growth:

```solidity
// Stored internally (scaled balance)
scaledBalance = depositAmount / liquidityIndex

// Actual balance (grows over time)
balanceOf(user) = scaledBalance * currentLiquidityIndex
```

**Example:**
- User deposits 1000 USDC when liquidityIndex = 1.0
- scaledBalance = 1000 / 1.0 = 1000
- After 1 year, liquidityIndex = 1.10 (10% APY)
- balanceOf(user) = 1000 * 1.10 = 1100 USDC

### 3. How Yield Accrues

**Borrowers pay interest** → **Liquidity index increases** → **All aToken balances grow proportionally**

The liquidity index is a cumulative growth factor:
```
liquidityIndex(t) = liquidityIndex(t-1) * (1 + supplyRate * Δt)
```

Every operation (supply, withdraw, borrow, repay) updates the index based on time elapsed.

### 4. Supply Mechanics

**User Action:** `Pool.supply(asset, amount, onBehalfOf, referralCode)`

**Internal Flow:**
1. Transfer `amount` of underlying asset from user to aToken contract
2. Calculate `scaledAmount = amount / liquidityIndex`
3. Mint `scaledAmount` of aTokens to user
4. User's `balanceOf()` now returns `scaledAmount * liquidityIndex`

**No yield yet** - yield accrues as liquidityIndex grows over time.

### 5. Withdraw Mechanics

**User Action:** `Pool.withdraw(asset, amount, to)`

**Internal Flow:**
1. Calculate `scaledAmount = amount / liquidityIndex`
2. Burn `scaledAmount` of aTokens from user
3. Transfer `amount` of underlying asset from aToken contract to `to` address

**Instant Withdrawals:**
- Withdrawals are instant IF pool has sufficient liquidity
- No epochs, no waiting periods
- Limited by: `min(userBalance, poolLiquidityAvailable)`

**Liquidity Constraints:**
- If utilization is 100% (all funds borrowed), withdrawals blocked
- Typically utilization caps at 80-90%, so withdrawals work
- Our vault should check `maxWithdraw()` before attempting

### 6. maxWithdraw() - Critical for Instant Withdrawals

```solidity
function maxWithdraw(address owner) external view returns (uint256) {
    uint256 userAssets = convertToAssets(balanceOf[owner]);
    uint256 availableLiquidity = asset.balanceOf(address(this));
    return min(userAssets, availableLiquidity);
}
```

**For Lendle integration:**
```solidity
function maxWithdraw(address owner) public view override returns (uint256) {
    uint256 userAssets = convertToAssets(balanceOf[owner]);
    
    // Query Lendle for available liquidity
    ReserveData memory reserve = lendlePool.getReserveData(asset);
    uint256 availableLiquidity = IERC20(asset).balanceOf(reserve.aTokenAddress);
    
    return userAssets < availableLiquidity ? userAssets : availableLiquidity;
}
```

## Implementation Strategy

### For Production (Mainnet/Testnet)
Use real Lendle contracts:
- Pool: `0xCFa5aE7c2CE8Fadc6426C1ff872cA45378Fb7cF3` (to be verified)
- Query `getReserveData(asset)` to get aToken addresses
- aUSDC and aUSDT addresses TBD (discover on-chain)

### For Local Testing (Anvil)
Create mocks that simulate Lendle behavior:

**MockLendlePool.sol:**
- Implements `supply()` → mints aTokens
- Implements `withdraw()` → burns aTokens, transfers assets
- Simulates liquidity index growth
- Tracks available liquidity

**MockAToken.sol:**
- Rebasing ERC20 (balance grows automatically)
- Uses `scaledBalance * liquidityIndex` formula
- Simulates yield accrual via time-based index updates

## Yield Distribution in WelotVault

**Our Model:**
1. Users deposit USDC/USDT → WelotVault records deposits
2. WelotVault deposits to LendleYieldVault (ERC4626 wrapper)
3. LendleYieldVault supplies to Lendle Pool → receives aTokens
4. aToken balance grows automatically (no action needed)
5. Weekly draw: `prizePool = aToken.balanceOf(vault) - totalLiabilities`
6. Winner withdraws instantly (if liquidity available)

**Key Insight:** We don't need to "claim" yield. It accrues automatically through aToken balance growth.

## Gas Optimization Note

**Infinite Approval Pattern:**
In LendleYieldVault, we use `forceApprove(type(uint256).max)` once per asset. This avoids repeated approvals on every deposit, saving ~5000 gas per transaction.

## Security Considerations

1. **Liquidity Risk:** If Lendle utilization hits 100%, withdrawals temporarily blocked
2. **Smart Contract Risk:** Lendle contracts are audited but carry inherent risk
3. **Price Oracle Risk:** Lendle uses oracles for collateral pricing (doesn't affect us directly since we only supply)
4. **Emergency Pause:** WelotVault should maintain pause mechanism for emergencies

## Testing Strategy

### Local Tests (Foundry)
- Use mocks to simulate yield accrual
- Test edge cases (full utilization, zero liquidity)
- Verify instant withdraw within liquidity limits

### Mainnet Fork Tests
- Fork Mantle mainnet
- Test against real Lendle contracts
- Verify actual APYs match expectations
- Test with real liquidity constraints

### Testnet Integration
- Deploy to Mantle Sepolia
- Perform end-to-end flow with real users
- Monitor gas costs, yields, withdrawals

## Reference Links
- Aave V3 Technical Paper: https://github.com/aave/aave-v3-core/blob/master/techpaper/Aave_V3_Technical_Paper.pdf
- Lendle Docs: https://docs.lendle.xyz/
- Aave V3 Contracts: https://github.com/aave/aave-v3-core

## Summary

**Lendle = Battle-tested lending protocol**
- aTokens automatically grow in balance (no claims needed)
- Instant withdrawals (liquidity permitting)
- ~12% APY on USDC, ~5% on USDT
- Perfect fit for no-loss lottery yield generation
