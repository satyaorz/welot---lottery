# WeLot Smart Contracts

No-loss savings lottery on Mantle Network.

## How It Works

1. **Deposit** any supported stablecoin (USDe, USDC, mETH, etc.)
2. **Earn chances** over time based on your deposited balance
3. **Weekly draws** award accumulated yield to a random winning pool
4. **Withdraw** your deposits anytime — principal is never at risk

Your deposit is never touched — only the yield generated goes into the prize pool.

## Architecture

### Core Contract: `WelotVault`

- **Multi-token support**: Each supported token has its own ERC-4626 yield vault
- **Pools**: Users deposit into pools; pool `1` is created by default
- **Winner weighting**: Pool selection is time-weighted by deposited balances (normalized to 18 decimals)
- **Weekly epochs**: With `drawInterval = 7 days`, draws align to Friday 12:00 UTC
- **Automation**: `checkUpkeep()` / `performUpkeep()` support off-chain keepers
- **Pyth Entropy**: Verifiable randomness (async callback)
- **Prize claiming**: Winners claim yield prizes allocated via per-token reward indices

### Token Configuration

Each supported token requires:
- `token`: ERC-20 token address
- `vault`: ERC-4626 yield vault whose `asset()` matches the token
- `enabled`: Whether deposits are currently accepted
- `decimals`: Token decimals (read automatically in `addSupportedToken`)

### Key Functions

| Function | Description |
|----------|-------------|
| `createPool()` | Create a new pool |
| `deposit(token, amount)` | Deposit tokens into pool `1` |
| `depositTo(token, amount, poolId, recipient)` | Deposit into a specific pool |
| `withdraw(token, amount)` | Withdraw from pool `1` |
| `withdrawFrom(token, amount, poolId)` | Withdraw from a specific pool |
| `claimPrize(token)` | Claim prize from pool `1` |
| `claimPrizeFrom(token, poolId)` | Claim prize from a specific pool |
| `closeEpoch()` | End current epoch (once end time is reached) |
| `requestRandomness()` | Request Entropy randomness (pays fee) |
| `finalizeDraw()` | Select winning pool, allocate prizes |
| `checkUpkeep()` | Automation check (returns `performData`) |
| `performUpkeep(performData)` | Automation step executor |

## Development

### Prerequisites

- [Foundry](https://getfoundry.sh/) installed
- Node.js 18+ (for frontend)

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Run Tests with Verbose Output

```bash
forge test -vvv
```

### Deploy Locally

```bash
# Terminal 1: Start local chain
anvil

# Terminal 2: Deploy contracts
forge script script/DeployLocal.s.sol:DeployLocalScript \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast

# Copy the output environment variables to frontend/.env.local
```

### Local Deployment Output

The deploy script outputs all necessary environment variables:
- `NEXT_PUBLIC_RPC_URL` / `NEXT_PUBLIC_CHAIN_ID`
- `NEXT_PUBLIC_WELOT_VAULT` - WelotVault contract address
- `NEXT_PUBLIC_ENTROPY` - Entropy provider address
- `NEXT_PUBLIC_FAUCET` - Multi-token faucet for demos
- Token + yield vault addresses:
  - `NEXT_PUBLIC_USDE`, `NEXT_PUBLIC_SUSDE`
  - `NEXT_PUBLIC_USDC`, `NEXT_PUBLIC_SUSDC`
  - `NEXT_PUBLIC_METH`, `NEXT_PUBLIC_SMETH`

## Contract Files

```
src/
├── WelotVault.sol          # Main lottery vault contract
└── mocks/
    ├── MockERC20.sol       # Test ERC-20 token
    ├── MockERC4626.sol     # Test yield vault
    ├── MockFaucet.sol      # Multi-token test faucet
    └── MockEntropyV2.sol   # Mock Pyth Entropy
```

## Dependencies

- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) - ReentrancyGuard, Pausable, Ownable
- [Forge Std](https://github.com/foundry-rs/forge-std) - Testing utilities

## Security Considerations

- **Principal protection**: Deposits tracked as liabilities, never used for prizes
- **Yield-only prizes**: Only vault yield surplus goes to prize pool
- **Reentrancy protection**: OpenZeppelin ReentrancyGuard on all state-changing functions
- **Bounded gas**: Draw iterates over pools and supported tokens; deployments set a `maxPools` cap (64 in scripts)
- **Emergency pause**: Owner can pause all deposits/withdrawals
- **Verified randomness**: Pyth Entropy provides on-chain verifiable randomness

## License

UNLICENSED (hackathon/demo)
