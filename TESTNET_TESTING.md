# Mantle Sepolia Testing Notes (Welot)

This repo supports a **full end-to-end test flow** on Mantle Sepolia by deploying mocks (tokens, ERC4626 yield vaults, faucet) plus the `WelotVault`.
Randomness can come from **real Pyth Entropy** (default) or an **on-chain mock** (opt-in).

## What we deployed on Mantle Sepolia

Deployed via `contracts/script/DeployMantle.s.sol` (chainId `5003`). For testnet we deploy:

- `WelotVault`
  - **Draw interval**: `7 days`
  - **Schedule**: **Friday 12:00 UTC** ("Friday noon")
  - **Max pools**: `10`
- Entropy provider
  - Default: real Pyth Entropy (as configured in `contracts/script/DeployMantle.s.sol`)
  - Optional: `MockEntropyV2` if you deploy with `DEPLOY_MOCK_ENTROPY=true`
- `MockERC20` tokens: `USDC` (6 decimals), `USDT` (6 decimals)
- `LendleYieldVault` ERC-4626 vaults: `sUSDC`, `sUSDT`
  - On testnet these plug into `MockLendlePool` + `MockAToken` to simulate Aave-style yield
  - **Higher yield rate** configured in the script (~12% APY USDC, ~5% APY USDT) for quick testing
- `MockFaucet`
  - Lets wallets mint test tokens once per token (cooldown=0, but still “one-time claim per token” logic)

The deploy script prints `NEXT_PUBLIC_*` values which can be copied into `frontend/.env.local` for the UI.

## Frontend configuration

The frontend reads these env vars (via `NEXT_PUBLIC_*`):

- `NEXT_PUBLIC_RPC_URL`
- `NEXT_PUBLIC_CHAIN_ID=5003`
- `NEXT_PUBLIC_WELOT_VAULT`
- `NEXT_PUBLIC_ENTROPY`
- `NEXT_PUBLIC_FAUCET`
- Token + vault addresses:
  - `NEXT_PUBLIC_USDC`, `NEXT_PUBLIC_SUSDC`
  - `NEXT_PUBLIC_USDT`, `NEXT_PUBLIC_SUSDT`

After changing `frontend/.env.local`, restart the dev server so Next inlines the new values.

## How the test draw works

`WelotVault` draw lifecycle (same contract for test and prod):

1. `closeEpoch()`
   - Can only be called once `block.timestamp >= epoch.end`
2. `requestRandomness()`
   - Requests randomness from the configured entropy contract
3. `entropyCallback(...)`
   - Called by entropy provider to deliver randomness
4. `finalizeDraw()`
  - Picks a winning pool (time-weighted by pool deposits) and distributes rewards via per-token reward indices

### Testnet randomness options

- **Real Pyth Entropy (default)**
  - Call `requestRandomness()` and wait for the provider callback (`entropyCallback`).
  - Once randomness is ready, call `finalizeDraw()`.
- **Mock entropy (opt-in)**
  - Deploy with `DEPLOY_MOCK_ENTROPY=true` (and do not override `ENTROPY_ADDRESS`).
  - Then you can deterministically fulfill by calling `MockEntropyV2.fulfill(sequence, randomness)`.

## Automation (production-grade on Mantle)

Chainlink Automation is not available on Mantle in many environments, so production automation should be done using an **off-chain keeper** (e.g. your own cron job + relayer, Gelato, OpenZeppelin Defender, etc.).

Recommended production checklist:

- Run an off-chain keeper that periodically calls `checkUpkeep` and (when needed) submits `performUpkeep(performData)`.
- With a 7-day interval, epochs end at Friday 12:00 UTC.
- Set `automationForwarder` on the vault to your keeper wallet (recommended) using `setAutomationForwarder(<keeper_wallet>)`. This prevents arbitrary callers from running upkeep.
- Use the official Pyth Entropy contract address for your target chain as the `IEntropyV2` provider; set that address in the deploy script for mainnet.
- Ensure the vault is funded with enough native currency to pay any entropy fees (`entropy.getFeeV2()`). Top up the contract as part of deployment or via a guardian script.
- Replace mock ERC4626 vaults with real yield sources (LendleYieldVault for USDC/USDT) that implement `IERC4626` so `totalAssets()` grows naturally.
- Remove any faucets and mint privileges from production builds — tokens on mainnet are real and must not be mintable.

Example production steps (high level):

1. Deploy `WelotVault` with the real `IEntropyV2` address and desired `drawInterval`.
2. Set up an off-chain keeper wallet and call `vault.setAutomationForwarder(<keeper_wallet>)` from the owner account.
4. Fund the vault with native tokens for entropy fees and with initial prize pool tokens if desired.
5. Verify `checkUpkeep` / `performUpkeep` flow on a staging network before going live.

### Keeper script (repo-provided)

This repo includes a minimal keeper that uses `viem` and works anywhere you have an RPC:

```bash
cd frontend

# required
export RPC_URL=https://rpc.sepolia.mantle.xyz
export CHAIN_ID=5003
export WELOT_VAULT=0xYourVault
export PRIVATE_KEY=0xyour_keeper_private_key

# optional
export POLL_INTERVAL_MS=30000

npm run keeper
```

Note: the contract intentionally returns `upkeepNeeded=false` when the epoch is `Closed` but the vault is underfunded for the Entropy fee. A keeper must top up the vault balance (native token) and then retry.

# Mantle Sepolia Testing Notes (Welot)

This document describes the testnet deployment and operational notes for Welot on Mantle Sepolia. The test deployment uses mock tokens and yield sources to emulate production behavior while keeping tests fast and deterministic.

## Deployed components (Mantle Sepolia)

Deployed using `contracts/script/DeployMantle.s.sol` (chainId 5003). The testnet deployment includes:

- `WelotVault` — weekly draw cadence (7 days), scheduled Friday 12:00 UTC, up to 10 pools.
- Entropy provider — by default the real Pyth Entropy contract; optionally `MockEntropyV2` when `DEPLOY_MOCK_ENTROPY=true`.
- Mock tokens: `USDC`, `USDT` (6 decimals).
- ERC-4626 yield mocks: `sUSDC`, `sUSDT` (backed by `MockLendlePool` + `MockAToken` for simulated yield).
- `MockFaucet` — one-time faucet per token for convenient testing.

The deploy script prints `NEXT_PUBLIC_*` values for the frontend; these values are included below.

## Frontend configuration

The frontend reads public runtime variables via `NEXT_PUBLIC_*`. After updating `frontend/.env.local` restart the dev server so Next inlines the values.

Required variables:

- `NEXT_PUBLIC_RPC_URL`
- `NEXT_PUBLIC_CHAIN_ID=5003`
- `NEXT_PUBLIC_WELOT_VAULT`
- `NEXT_PUBLIC_ENTROPY`
- `NEXT_PUBLIC_FAUCET`
- `NEXT_PUBLIC_USDC`, `NEXT_PUBLIC_SUSDC`
- `NEXT_PUBLIC_USDT`, `NEXT_PUBLIC_SUSDT`

Current Mantle Sepolia deployment values (present):

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

## Draw lifecycle (contract behavior)

The `WelotVault` draw lifecycle follows the same sequence for test and production:

1. `closeEpoch()` — callable once `block.timestamp >= epoch.end`.
2. `requestRandomness()` — requests randomness from the configured entropy provider.
3. `entropyCallback(...)` — provider calls back with randomness.
4. `finalizeDraw()` — selects the winning pool (time-weighted by deposits) and distributes rewards.

Randomness options on testnet:

- Real Pyth Entropy (default): call `requestRandomness()` and wait for the provider callback before `finalizeDraw()`.
- Mock entropy (opt-in): deploy with `DEPLOY_MOCK_ENTROPY=true` and fulfill deterministically with `MockEntropyV2.fulfill(sequence, randomness)`.

## Automation and keeper guidance

This repository includes a minimal keeper implementation at `frontend/scripts/keeper.mjs`. The keeper polls `checkUpkeep` and calls `performUpkeep(performData)` when required. The keeper supports an `ONCE=1` mode to run a single tick.

Operational notes:

- The vault must hold sufficient native balance to pay `entropy.getFeeV2()`. When the epoch is `Closed` but the vault balance is insufficient, `checkUpkeep` intentionally returns `upkeepNeeded=false` to avoid revert loops. The keeper implementation can top up the vault balance and retry.
- If `automationForwarder` is configured on the vault, only the forwarder address is permitted to call `performUpkeep`.

Keeper example environment:

```bash
cd frontend

# required
export RPC_URL=
export CHAIN_ID=5003
export WELOT_VAULT=0x8cdEcB86577BA93709C05B32474667a1C1360988

# optional
export POLL_INTERVAL_MS=30000

npm run keeper
```

To run a single tick and exit:

```bash
ONCE=1 npm run keeper
```

Security reminders:

- Use a secure multisig for owner and deployment actions.
- Monitor gas and entropy fee costs and alert for low balances.
- Audit integrations (entropy provider, automation operator, yield sources) before production.

## Auto-yield mock behavior

The test ERC-4626 mocks auto-accrue yield over time. `totalAssets()` reports the current balance plus pending yield, which makes `WelotVault.currentPrizePool(token)` grow over time without manual donations.

## Commands (deploy + run)

Deploy to Mantle Sepolia (the deploy scripts read `contracts/.env`):

```bash
cd contracts
set -a
source .env
set +a
forge script script/DeployMantle.s.sol:DeployMantleScript --rpc-url "$MANTLE_SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY" --broadcast
```

Run the frontend:

```bash
cd frontend
npm run dev
```
