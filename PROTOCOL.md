# WeLot Protocol Documentation

## Overview

WeLot is a **no-loss savings lottery** built on Mantle Network. Users deposit supported tokens, which are automatically routed to yield-generating vaults. The yield is pooled together and distributed to random winners in weekly draws — while deposits remain fully withdrawable at any time.

## Core Concept: No-Loss Lottery

Traditional lotteries require you to pay for tickets that have no value if you lose. WeLot inverts this:

1. **Deposit** → Your tokens go into an ERC-4626 yield vault
2. **Earn tickets** → Receive tickets proportional to your deposit
3. **Win yield** → Weekly draws distribute accumulated yield to winners
4. **Withdraw anytime** → Your principal is always yours to withdraw

**You can only win; you cannot lose your deposit.**

## Protocol Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        WelotVault                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   Token A   │  │   Token B   │  │   Token C   │         │
│  │   (USDe)    │  │   (USDC)    │  │   (mETH)    │         │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘         │
│         │                │                │                 │
│         ▼                ▼                ▼                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ Yield Vault │  │ Yield Vault │  │ Yield Vault │         │
│  │  (ERC4626)  │  │  (ERC4626)  │  │  (ERC4626)  │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                   Epoch Manager                       │  │
│  │  • Weekly epochs (Friday noon UTC)                   │  │
│  │  • Keeper-based automation integration               │  │
│  │  • Pyth Entropy randomness                          │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Token Support

WeLot supports multiple tokens simultaneously. Each token operates in its own pool:

| Token | Description | Yield Source |
|-------|-------------|--------------|
| USDe  | Ethena USD  | sUSDe vault  |
| USDC  | USD Coin    | Aave/Compound |
| mETH  | Mantle ETH  | Staking yield |

### Adding New Tokens

Tokens are added via `addSupportedToken(address token, address vault, uint256 ticketRatio)`:
- `token`: The ERC-20 token address
- `vault`: An ERC-4626 vault that accepts this token
- `ticketRatio`: Tickets per token unit (for decimal normalization)

## Weekly Draw Flow

### 1. Epoch Management

Epochs run weekly, closing every Friday at noon UTC:

```
Week 1                    Week 2
├────────────────────────┼────────────────────────┤
│   Deposits accumulate  │   Deposits accumulate  │
│   Yield generates      │   Yield generates      │
└────────┬───────────────┴───────────┬────────────┘
         │                           │
    closeEpoch()                closeEpoch()
         │                           │
         ▼                           ▼
    Random request              Random request
         │                           │
         ▼                           ▼
    Winner selected             Winner selected
```

### 2. Automation / Keepers

The contract implements a `checkUpkeep`/`performUpkeep` flow compatible with Chainlink-style automation, but on Mantle you may need to run a keeper off-chain (cron + relayer, Gelato, Defender, etc.).

```solidity
function checkUpkeep(bytes calldata) external view returns (bool upkeepNeeded, bytes memory) {
    upkeepNeeded = block.timestamp >= currentEpochEnd;
}

function performUpkeep(bytes calldata) external {
    closeEpoch();
}
```

Run a keeper that periodically calls `checkUpkeep` and submits `performUpkeep(performData)` when `upkeepNeeded` is true.

### 3. Pyth Entropy Randomness

Winner selection uses Pyth Entropy for verifiable on-chain randomness:

1. `closeEpoch()` calls `entropy.requestWithCallback()`
2. Pyth generates random number off-chain
3. `entropyCallback()` receives the random number
4. Winner is selected: `winner = depositors[random % totalTickets]`

## Prize Distribution

### How Prizes Are Calculated

```
Prize Pool = Vault Assets - Total Deposits (Liabilities)
```

Only the **yield surplus** becomes prizes. User deposits are tracked as liabilities and never distributed.

### Winner Selection

For each token pool:
1. Calculate total tickets from all depositors
2. Generate random number in range `[0, totalTickets)`
3. Walk through depositors until cumulative tickets exceed random number
4. That depositor wins the entire prize pool for that token

### Claiming Prizes

Winners can claim at any time:
```solidity
claimPrize(address token)
```

Prize amounts persist across epochs until claimed.

## User Actions

### Deposit

```solidity
deposit(address token, uint256 amount)
```
- Requires prior approval
- Tokens routed to yield vault
- Tickets credited immediately
- Counts toward current epoch

### Withdraw

```solidity
withdraw(address token, uint256 amount)
```
- Instantly withdrawable
- Tickets deducted
- Shares redeemed from vault
- Can withdraw partial or full amount

### Claim Prize

```solidity
claimPrize(address token)
```
- Claims accumulated winnings
- Transfers yield from vault
- Resets claimable balance to zero

## Security Model

### Principal Protection

User deposits are tracked separately from vault shares:
```solidity
mapping(bytes32 => uint256) public deposits;      // User liabilities
mapping(address => uint256) public totalDeposited; // Per-token liabilities
```

The vault may have more assets than liabilities (from yield). This surplus is the prize pool.

### Reentrancy Protection

All state-changing functions use `nonReentrant` modifier:
- `deposit()`
- `withdraw()`
- `claimPrize()`
- `closeEpoch()`

### Bounded Iterations

Pool sets are bounded to `MAX_POOL_KEYS = 100` to prevent gas exhaustion during winner selection.

### Emergency Controls

Owner can pause/unpause:
```solidity
pause()   // Blocks deposits and withdrawals
unpause() // Resumes normal operation
```

## Integration Guide

### Frontend Integration

1. **Load supported tokens**:
```typescript
const tokens = await contract.read.getSupportedTokens()
```

2. **Get user state**:
```typescript
const deposits = await contract.read.deposits([poolKey])
const claimable = await contract.read.claimable([poolKey])
```

3. **Deposit**:
```typescript
await token.write.approve([vaultAddress, amount])
await vault.write.deposit([tokenAddress, amount])
```

4. **Withdraw**:
```typescript
await vault.write.withdraw([tokenAddress, amount])
```

### Automation Setup

1. Deploy WelotVault
2. Configure your keeper
3. Fund the Automation subscription
4. Contract auto-executes weekly draws

## Deployed Addresses

### Mantle Mainnet
*Coming soon*

### Mantle Testnet
*Coming soon*

### Local Development
Run `forge script script/DeployLocal.s.sol` — addresses printed to console.

## Risks & Considerations

### Yield Risk
If the underlying vault generates negative yield (e.g., from slashing), the prize pool could be zero.

### Smart Contract Risk
As with any DeFi protocol, there's risk of bugs. The code uses audited OpenZeppelin contracts where possible.

### Randomness Trust
Pyth Entropy provides verifiable randomness, but users must trust the Pyth network's integrity.

## License

MIT
