# WeLot Smart Contracts

No-loss savings lottery on Mantle Network.

## How It Works

1. **Deposit** any supported stablecoin (USDC, USDT)
2. **Earn chances** over time based on your deposited balance
3. **Weekly draws** award accumulated yield to a random winning pool
4. **Withdraw** your deposits anytime — principal is never at risk

Your deposit is never touched — only the yield generated goes into the prize pool.

## Architecture

### Core Contract: `WelotVault`

- **Multi-token support**: Each supported token has its own ERC-4626 yield vault
- **Pools**: 10 pools are created at deployment; users are auto-assigned to a pool based on their address
- **Winner weighting**: Pool selection is time-weighted by deposited balances (normalized to 18 decimals)
- **Weekly epochs**: With `drawInterval = 7 days`, draws align to Friday 12:00 UTC
- **Automation**: `checkUpkeep()` / `performUpkeep()` support off-chain keepers
- **Pyth Entropy**: Verifiable randomness (async callback)
- **Prize claiming**: Winners claim yield prizes allocated via per-token reward indices

Operational note: when the epoch is `Closed`, `checkUpkeep()` returns `upkeepNeeded=false` if the vault does not have enough native balance to pay `entropy.getFeeV2()`. Your keeper/ops should top up the vault and retry.

### Yield Sources

WeLot integrates with Lendle (Mantle's Aave V3 fork) to generate prizes:

- **USDC**: Deposited into Lendle's lending pool, earning ~12% APY
- **USDT**: Deposited into Lendle's lending pool, earning ~5% APY

Yield is captured through aToken balance growth (rebasing mechanism). See [LENDLE_MECHANICS.md](./LENDLE_MECHANICS.md) for technical details.

Each yield source must implement ERC-4626 to be compatible with WelotVault.

### Token Configuration

Each supported token requires:
- `token`: ERC-20 token address
- `vault`: ERC-4626 yield vault whose `asset()` matches the token
- `enabled`: Whether deposits are currently accepted
- `decimals`: Token decimals (read automatically in `addSupportedToken`)

### Key Functions

| Function | Description |
|----------|-------------|
| `assignedPoolId(user)` | Get the pool ID auto-assigned to a user |
| `deposit(token, amount)` | Deposit tokens into your assigned pool |
| `depositTo(token, amount, poolId, recipient)` | Deposit into a specific pool (must match assigned pool) |
| `withdraw(token, amount)` | Withdraw from your assigned pool |
| `withdrawFrom(token, amount, poolId)` | Withdraw from a specific pool |
| `claimPrize(token)` | Claim prize from your assigned pool |
| `claimPrizeFrom(token, poolId)` | Claim prize from a specific pool |
| `closeEpoch()` | End current epoch (once end time is reached) |
| `requestRandomness()` | Request Entropy randomness (pays fee) |
| `finalizeDraw()` | Select winning pool, allocate prizes |
| `checkUpkeep()` | Automation check (returns `performData`) |
| `performUpkeep(performData)` | Automation step executor |

> **Note:** Pool creation is disabled. 10 pools are created at deployment, and each user is deterministically assigned to one pool based on their address.

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


### Local / Testnet Deployment Output

The deploy script emits the `NEXT_PUBLIC_*` variables for the frontend. For the current Mantle Sepolia deployment these values are:

```dotenv
NEXT_PUBLIC_CHAIN_ID=5003
NEXT_PUBLIC_RPC_URL=

NEXT_PUBLIC_WELOT_VAULT=0x8cdEcB86577BA93709C05B32474667a1C1360988
NEXT_PUBLIC_ENTROPY=0x98046Bd286715D3B0BC227Dd7a956b83D8978603
NEXT_PUBLIC_FAUCET=0xfC02B04FacbFD3D1b9E1C037A9d867f055BDA9CE

NEXT_PUBLIC_USDC=0xCEc970693C0FdEA3BE7a9b2BF68bF4651f27e25A
NEXT_PUBLIC_SUSDC=0x860967abD2319Ed238C5aEf085743afCb4227036
NEXT_PUBLIC_USDT=0xe02199dE8111645135873fA38157EA7B5D7423eC
NEXT_PUBLIC_SUSDT=0x7C2380BF55D4E23707a7f0708bdAD8faa8d1D254
```

When deploying locally, the same variables are printed and should be copied into `frontend/.env.local`.

## Contract Files

```
src/
├── WelotVault.sol          # Main lottery vault contract
├── interfaces/
│   ├── IEntropyV2.sol      # Pyth Entropy interface
│   ├── IYieldSource.sol    # Yield source interface
│   └── ILendlePool.sol     # Lendle lending pool interface
├── yield/
│   └── LendleYieldVault.sol  # Lendle lending pool adapter (ERC4626)
└── mocks/
    ├── MockERC20.sol       # Test ERC-20 token
    ├── MockERC4626.sol     # Test yield vault
    ├── MockAToken.sol      # Mock Lendle aToken (rebasing)
    ├── MockLendlePool.sol  # Mock Lendle Pool
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
