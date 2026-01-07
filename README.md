# WeLot (welot)

No-loss savings lottery on Mantle: deposit into yield sources, get a chance to win the yield, and keep your principal withdrawable.

This repo contains:
- Solidity contracts (Foundry) in `contracts/`
- A Next.js frontend in `frontend/`
- Protocol and testnet notes in `PROTOCOL.md` and `TESTNET_TESTING.md`

## Quickstart (local)

### 1) Start a local chain

```bash
anvil
```

### 2) Deploy the local stack

```bash
cd contracts
forge script script/DeployLocal.s.sol:DeployLocalScript --rpc-url http://127.0.0.1:8545 --broadcast
```

The script prints `NEXT_PUBLIC_*` values for the UI.

### 3) Configure + run the frontend

```bash
cd frontend
npm install
cp .env.example .env.local
# paste the `NEXT_PUBLIC_*` values from the deploy output into .env.local
npm run dev
```

Open http://localhost:3000

The repository root provides a convenience script `npm run dev` that proxies into `frontend/`.

## Quickstart (Mantle Sepolia testnet, 5003)

Addresses change on every redeploy.

- For the UI, treat the **deploy script output** (the printed `NEXT_PUBLIC_*` lines) as the source of truth.
- Foundry also writes a JSON receipt under `contracts/broadcast/DeployMantle.s.sol/5003/run-latest.json`.

Important: keep secrets out of the frontend.

- Put RPC + deployer key in `contracts/.env`.
- Put only `NEXT_PUBLIC_*` values in `frontend/.env.local`.

### 1) Deploy

```bash
cd contracts
cp .env.example .env
# edit .env (RPC + PRIVATE_KEY)
set -a && source .env && set +a
forge script script/DeployMantle.s.sol:DeployMantleScript --rpc-url "$MANTLE_SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY" --broadcast
```

### 2) Run the UI

Populate `frontend/.env.local` with the printed `NEXT_PUBLIC_*` values. The frontend is started with:

```bash
cd frontend
npm install
npm run dev
```

Example `frontend/.env.local` (public values only):

```dotenv
NEXT_PUBLIC_CHAIN_ID=5003
NEXT_PUBLIC_RPC_URL=

NEXT_PUBLIC_WELOT_VAULT=0x...
NEXT_PUBLIC_ENTROPY=0x...
NEXT_PUBLIC_FAUCET=0x...

NEXT_PUBLIC_USDC=0x...
NEXT_PUBLIC_SUSDC=0x...
NEXT_PUBLIC_USDT=0x...
NEXT_PUBLIC_SUSDT=0x...
```

## How draws work (high level)

- Deposits are routed into per-token ERC-4626 yield vaults.
- The draw lifecycle is:
  1. `closeEpoch()` (once the epoch ends)
  2. `requestRandomness()` (pays an Entropy fee)
  3. Entropy calls back `entropyCallback(...)`
  4. `finalizeDraw()` selects a winning **pool** and updates per-token reward indices.

Automation is supported via `checkUpkeep(bytes)` / `performUpkeep(bytes)`; see `frontend/scripts/keeper.mjs`.

## Repo layout

- `contracts/` — Foundry project
  - `src/WelotVault.sol` — core contract
  - `script/DeployLocal.s.sol` — local deployment (mocks + faucet)
  - `script/DeployMantle.s.sol` — Mantle mainnet/testnet deployment
  - `script/RunDraw.s.sol` — helper for mock-entropy draws
- `frontend/` — Next.js app (reads `NEXT_PUBLIC_*` config)

## Docs

- `PROTOCOL.md` — protocol/contract behavior (authoritative)
- `TESTNET_TESTING.md` — Mantle Sepolia testing + keeper notes
- `contracts/README.md` — Foundry workflows
- `frontend/README.md` — UI + keeper workflows

## License

UNLICENSED (hackathon/demo). Dependencies are under their own licenses.
