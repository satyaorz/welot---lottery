# WeLot Protocol Documentation

## Overview

WeLot is a no-loss savings lottery on Mantle. Users deposit supported ERC-20 tokens into the protocol, which routes them into per-token ERC-4626 yield sources. The yield surplus (assets above liabilities) becomes the prize pool.

Draws run on a cadence (weekly in this repo). A draw selects a winning **pool**, then distributes each token’s prize to depositors of that token **inside the winning pool**, pro-rata.

## On-chain components

### `WelotVault` (core)

`WelotVault` manages:

- Supported deposit tokens (`addSupportedToken(token, yieldVault)`)
- User deposits per token, per pool
- Epoch state machine and draw scheduling
- Randomness via Pyth Entropy (async callback)
- Prize accounting via per-token “reward indices”

### Yield sources

Each supported token is configured with an ERC-4626 vault whose `asset()` must equal the token. `WelotVault` deposits assets into these vaults and later withdraws assets to satisfy withdrawals/prize claims.

### Randomness (Pyth Entropy)

`WelotVault` uses Entropy V2:

- `requestRandomness()` pays `entropy.getFeeV2()` and calls `entropy.requestV2()`
- Entropy later calls back `entropyCallback(sequenceNumber, provider, randomNumber)`
- The callback must not revert; the contract ignores invalid callbacks and only accepts messages from the configured entropy address

## Pools (the “lottery tickets”)

Users deposit into **pools**. Pool `1` is created in the constructor as the default.

- Create a new pool: `createPool()`
- Deposit into pool 1: `deposit(token, amount)`
- Deposit into a specific pool: `depositTo(token, amount, poolId, recipient)`

### Winner weighting: time-weighted deposits

Winner selection is pool-based and **time-weighted**.

Each pool maintains a cumulative weight that approximates:

$$\text{poolWeight} = \int \text{poolBalanceNormalized}(t)\,dt$$

Where `poolBalanceNormalized` is the pool’s total deposits across all supported tokens, normalized to 18 decimals.

At draw time, `finalizeDraw()` selects a pool with probability proportional to this cumulative weight.

## Epochs and draw lifecycle

### Scheduling

This repo’s deploy scripts set `drawInterval = 7 days`. When `drawInterval == 7 days`, end times are aligned to **Friday 12:00 UTC**.

If `drawInterval` is something else (for local demos), end times are interval-aligned boundaries.

### State machine

An epoch progresses through:

1. **Open** — accepts deposits/withdrawals
2. **Closed** — epoch ended; deposits are still allowed by the contract, but the draw lifecycle starts here
3. **RandomnessRequested** — waiting for Entropy callback
4. **RandomnessReady** — random number received; ready to finalize

The intended operational flow is:

1. `closeEpoch()` once `block.timestamp >= epoch.end`
2. `requestRandomness()` (requires enough ETH/MNT in the vault to pay `entropy.getFeeV2()`)
3. Wait for `entropyCallback(...)`
4. `finalizeDraw()` to pick a winning pool and distribute prizes

## Prize pools and accounting

### Liabilities vs assets

For each token, the protocol tracks:

- `totalDeposits` — user principal (liability)
- `totalUnclaimedPrizes` — prizes allocated to winners but not yet claimed (liability)

The current prize pool for a token is:

$$\text{prizePool(token)} = \max(\text{totalAssets(token)} - (\text{totalDeposits(token)} + \text{totalUnclaimedPrizes(token)}), 0)$$

### Distribution model

When a winning pool is selected, `finalizeDraw()` loops over supported tokens and, for each token:

- Computes `prize = currentPrizePool(token)`
- If the winning pool has any deposits of that token, it updates:
  - `poolTokenRewardIndex[token][winningPoolId] += (prize * 1e18) / winnerTokenDeposits`
  - `totalUnclaimedPrizes += prize`

This means:

- Prizes are claimable per token and per pool.
- If the winning pool has **zero** deposits of a token, that token’s prize pool is not allocated in that draw (it remains as surplus for future draws).

### Claiming

Users claim via:

- `claimPrize(token)` (default pool 1)
- `claimPrizeFrom(token, poolId)` (specific pool)

Claims withdraw assets from the token’s yield vault.

## Automation / keepers

`WelotVault` exposes Chainlink-style automation endpoints:

- `checkUpkeep(bytes)` returns `(upkeepNeeded, performData)`
- `performUpkeep(bytes performData)` executes one step based on `performData`

The contract uses `performData` to encode an action:

- `1` = close epoch
- `2` = request randomness
- `3` = finalize draw

Optionally, the owner can set an `automationForwarder` via `setAutomationForwarder(address)`. If set, only that address may call `performUpkeep`.

## Key read methods (for UIs)

- `getSupportedTokens()`
- `getUserPosition(token, poolId, user)` → `(deposited, claimable)`
- `currentPrizePool(token)`
- `getTimeUntilDraw()`
- `epochStatus()` / `getCurrentEpoch()` / `getEpoch(epochId)`
- `getPastWinners(limit)`

## Risks / notes

- Yield source risk: ERC-4626 vaults can lose money; prize pools can be $0.
- Randomness is async: draws are not a single transaction; you need automation/off-chain ops.
- This is hackathon/demo code; treat it accordingly.

## License

UNLICENSED (repo code). Dependencies are under their own licenses.
