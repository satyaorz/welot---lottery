# WeLot Smart Contracts

No-loss savings lottery on Mantle Network.

## How It Works

1. **Deposit** any supported stablecoin (USDe, USDC, mETH, etc.)
2. **Earn tickets** proportional to deposit value
3. **Weekly draws** award accumulated yield to random winners
4. **Withdraw** your deposits anytime — principal is never at risk

Your deposit is never touched — only the yield generated goes into the prize pool.

## Architecture

### Core Contract: `WelotVault`

- **Multi-token support**: Each supported token has its own ERC-4626 yield vault
- **Ticket system**: 1 ticket per token unit deposited (adjusted for decimals)
- **Weekly epochs**: Automated draws every Friday at noon UTC
- **Chainlink Automation**: `checkUpkeep()` / `performUpkeep()` for decentralized execution
- **Pyth Entropy**: Verifiable randomness for provably fair winner selection
- **Prize claiming**: Winners claim accumulated yield prizes

### Token Configuration

Each supported token requires:
- `token`: ERC-20 token address
- `vault`: ERC-4626 yield vault whose `asset()` matches the token
- `enabled`: Whether deposits are currently accepted
- `ticketRatio`: Tickets per token unit (for decimal normalization)

### Key Functions

| Function | Description |
|----------|-------------|
| `deposit(token, amount)` | Deposit tokens to enter the lottery |
| `withdraw(token, amount)` | Withdraw deposited tokens |
| `claimPrize(token)` | Claim accumulated prize winnings |
| `closeEpoch()` | End current epoch, request random number |
| `checkUpkeep()` | Chainlink Automation check |
| `performUpkeep()` | Chainlink Automation execution |

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
- `NEXT_PUBLIC_VAULT` - WelotVault contract address
- `NEXT_PUBLIC_USDE` / `NEXT_PUBLIC_USDC` / `NEXT_PUBLIC_METH` - Token addresses
- `NEXT_PUBLIC_USDE_VAULT` / etc. - Yield vault addresses
- `NEXT_PUBLIC_FAUCET` - Multi-token faucet for testing
- `NEXT_PUBLIC_ENTROPY` - Mock entropy provider

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
- [Chainlink Brownie Contracts](https://github.com/smartcontractkit/chainlink-brownie-contracts) - Automation interfaces
- [Forge Std](https://github.com/foundry-rs/forge-std) - Testing utilities

## Security Considerations

- **Principal protection**: Deposits tracked as liabilities, never used for prizes
- **Yield-only prizes**: Only vault yield surplus goes to prize pool
- **Reentrancy protection**: OpenZeppelin ReentrancyGuard on all state-changing functions
- **Bounded gas**: Pool set limited to MAX_POOL_KEYS (100) to prevent gas exhaustion
- **Emergency pause**: Owner can pause all deposits/withdrawals
- **Verified randomness**: Pyth Entropy provides on-chain verifiable randomness

## License

MIT
