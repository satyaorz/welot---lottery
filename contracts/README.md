# welot Smart Contracts

No-loss savings lottery on Mantle Network.

## How It Works

1. **Deposit** stablecoins (USDe)
2. **Earn tickets** (1 ticket per $1 deposited)
3. **Weekly draws** award the yield to winners
4. **Withdraw** your deposits anytime

Your principal is never at risk — only the yield generated goes into the prize pool.

## Architecture

### Core Contract: `WelotVault`

- Accepts deposits and routes them to a yield-generating vault
- Tracks user deposits as "tickets" for lottery eligibility
- Manages weekly epochs with automated prize draws
- Integrates Chainlink Automation for decentralized draw execution
- Uses verifiable randomness (Entropy) for fair winner selection

### V2 Features

The new `WelotVaultV2` includes:
- **OpenZeppelin**: ReentrancyGuard, Pausable, Ownable
- **Chainlink Automation**: `checkUpkeep()` / `performUpkeep()` for automated draws
- **Simplified API**: `deposit()`, `withdraw()`, `claimPrize()`

## Development

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Deploy Locally

```bash
# Terminal 1
anvil

# Terminal 2
forge script script/DeployLocal.s.sol:DeployLocalScript --rpc-url http://127.0.0.1:8545 --broadcast
```

## Dependencies

- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) - Security primitives
- [Chainlink Brownie Contracts](https://github.com/smartcontractkit/chainlink-brownie-contracts) - Automation interfaces
- [Forge Std](https://github.com/foundry-rs/forge-std) - Testing utilities

## Safety

- Principal is tracked as a liability — never used for prizes
- Prizes come only from yield surplus
- Randomness callback is non-reverting
- Pool set is bounded to keep gas predictable
- Emergency pause functionality included
