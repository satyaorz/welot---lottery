# Mantle Sepolia Testing Notes (Welot)

This repo supports a **full end-to-end test flow** on Mantle Sepolia by deploying mocks (tokens, ERC4626 yield vaults, faucet) plus the `WelotVault`.
Randomness can come from **real Pyth Entropy** (default) or an **on-chain mock** (opt-in).

## What we deployed on Mantle Sepolia

Deployed via `contracts/script/DeployMantle.s.sol` (chainId `5003`). For testnet we deploy:

- `WelotVault`
  - **Draw interval**: `7 days`
  - **Schedule**: **Friday 12:00 UTC** ("Friday noon")
  - **Max pools**: `64`
- Entropy provider
  - Default: real Pyth Entropy (as configured in `contracts/script/DeployMantle.s.sol`)
  - Optional: `MockEntropyV2` if you deploy with `DEPLOY_MOCK_ENTROPY=true`
- `MockERC20` tokens: `USDe` (18), `USDC` (6), `mETH` (18)
- `MockERC4626` yield vaults: `sUSDe`, `sUSDC`, `smETH`
  - Auto-accrues yield over time (see “Auto-yield mock” below)
  - **Higher yield rate** configured in the script (~10 tokens/minute) so prize pools move quickly in demos
- `MockFaucet`
  - Lets wallets mint test tokens once per token (cooldown=0, but still “one-time claim per token” logic)

The deploy script prints `NEXT_PUBLIC_*` values which were copied into `frontend/.env.local` for the UI.

## Frontend configuration

The frontend reads these env vars (via `NEXT_PUBLIC_*`):

- `NEXT_PUBLIC_RPC_URL`
- `NEXT_PUBLIC_CHAIN_ID=5003`
- `NEXT_PUBLIC_WELOT_VAULT`
- `NEXT_PUBLIC_ENTROPY`
- `NEXT_PUBLIC_FAUCET`
- Token + vault addresses:
  - `NEXT_PUBLIC_USDE`, `NEXT_PUBLIC_SUSDE`
  - `NEXT_PUBLIC_USDC`, `NEXT_PUBLIC_SUSDC`
  - `NEXT_PUBLIC_METH`, `NEXT_PUBLIC_SMETH`

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
   - Picks a winning pool and distributes rewards via `rewardIndex`

### Testnet randomness options

- **Real Pyth Entropy (default)**
  - Call `requestRandomness()` and wait for the provider callback (`entropyCallback`).
  - Once randomness is ready, call `finalizeDraw()`.
- **Mock entropy (opt-in)**
  - Deploy with `DEPLOY_MOCK_ENTROPY=true`.
  - Then you can deterministically fulfill locally by calling `MockEntropyV2.fulfill(...)`.

## Automation (production-grade on Mantle)

Chainlink Automation is not available on Mantle in many environments, so production automation should be done using an **off-chain keeper** (e.g. your own cron job + relayer, Gelato, OpenZeppelin Defender, etc.).

Recommended production checklist:

- Run an off-chain keeper that periodically calls `checkUpkeep` and (when needed) submits `performUpkeep(performData)`.
- With a 7-day interval, epochs end at Friday 12:00 UTC.
- Set `automationForwarder` on the vault to your keeper wallet (recommended) using `setAutomationForwarder(<keeper_wallet>)`. This prevents arbitrary callers from running upkeep.
- Use the official Pyth Entropy contract address for your target chain as the `IEntropyV2` provider; set that address in the deploy script for mainnet.
- Ensure the vault is funded with enough native currency to pay any entropy fees (`entropy.getFeeV2()`). Top up the contract as part of deployment or via a guardian script.
- Replace mock ERC4626 vaults with real yield sources that implement `IERC4626` so `totalAssets()` grows naturally.
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

To run a single tick and exit:

```bash
ONCE=1 npm run keeper
```

Security notes:

- Use a secure multisig for `owner` and deployment actions.
- Monitor gas and entropy fee costs and add alerting for low balances.
- Audit the integration points (entropy provider, automation operator, yield sources) for correctness and permissions.

## Auto-yield mock (how prize pool grows on testnet)

`MockERC4626` is modified to **auto-accrue yield over time**.

- It exposes `yieldRatePerSecond` and tracks `lastYieldTimestamp`
- `totalAssets()` returns `currentBalance + pendingYield`
- On deposits/withdrawals, pending yield is “realized” by minting underlying tokens into the vault

Result: the `WelotVault.currentPrizePool(token)` becomes non-zero over time without needing a user to donate tokens.

## Production: what changes (no mocks)

For production, replace the mocks with real integrations:

- **Entropy/VRF**
  - Use the real Pyth Entropy contract address for the target chain
  - Keep ETH/MNT funded for entropy fees
  - Randomness arrives asynchronously via the provider callback

- **Tokens + Yield sources**
  - Use real ERC20 tokens (USDe/USDC/etc.) and real yield sources
  - The yield source should be an ERC4626 vault (or a wrapper vault) so `totalAssets()` grows naturally

- **Automation**
  - Use Chainlink Automation (or an off-chain keeper) to:
    - call `closeEpoch()` once time is up
    - call `requestRandomness()`
    - call `finalizeDraw()` once randomness is ready

- **Timing**
  - Testnet and production both use a weekly cadence in this repo.
  - If you want a faster local demo cadence, deploy to Anvil or modify the deploy script.

## Commands used

Deploy to Mantle Sepolia (reads `contracts/.env`):

```bash
cd contracts
set -a
source .env
set +a
forge script script/DeployMantle.s.sol:DeployMantleScript --rpc-url "$MANTLE_SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY" --broadcast

# Optional: deploy with an on-chain mock entropy (deterministic draw testing)
# DEPLOY_MOCK_ENTROPY=true forge script ...

# Optional: override entropy address (if Pyth address changes)
# ENTROPY_ADDRESS=0x... forge script ...
```

Run the frontend:

```bash
cd frontend
npm run dev
```
