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

Tip: from the repo root you can also run `npm run dev` (it proxies into `frontend/`).

## Quickstart (Mantle Sepolia testnet, 5003)

### Deployed addresses (Mantle Sepolia, 5003)

These are the most recent addresses from `contracts/broadcast/DeployMantle.s.sol/5003/run-latest.json`.
If you redeploy, treat the deploy output as the new source of truth.

```dotenv
NEXT_PUBLIC_CHAIN_ID=5003
NEXT_PUBLIC_WELOT_VAULT=0x8601C4932173571ee941fa0a26dE2379E351b164
NEXT_PUBLIC_ENTROPY=0x98046Bd286715D3B0BC227Dd7a956b83D8978603
NEXT_PUBLIC_FAUCET=0x8b4AFcf270A4727F377eCf8a167073B87ECa7658
ENTROPY_ADDRESS=0x98046Bd286715D3B0BC227Dd7a956b83D8978603

# Tokens
NEXT_PUBLIC_USDE=0x271b8d3cdc2F5aD3Cc569ECe3cFDEA79EDC806E5
NEXT_PUBLIC_SUSDE=0x3F95B8124E51380Fbabc57ad3FbF32FD6669cDA8
NEXT_PUBLIC_USDC=0xc3f30eA136ac7f398Cdc1fc3877DAfcF9E5B517C
NEXT_PUBLIC_SUSDC=0xA35b6412E7e216e3EA032bb9e543bEFa5cD19152
NEXT_PUBLIC_METH=0x4Cf52d4cfb118F04e2A76808422b2573Cf3051Cc
NEXT_PUBLIC_SMETH=0x2b13239c4683d22F127ba7Af5B06Cb41d84f67Ad
```

`ENTROPY_ADDRESS` is used by the keeper script; the frontend uses `NEXT_PUBLIC_ENTROPY`.

### 1) Deploy

```bash
cd contracts
cp .env.example .env
# edit .env (RPC + PRIVATE_KEY)
set -a && source .env && set +a
forge script script/DeployMantle.s.sol:DeployMantleScript --rpc-url "$MANTLE_SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY" --broadcast
```

### 2) Run the UI

Copy the printed `NEXT_PUBLIC_*` values into `frontend/.env.local`, then:

```bash
cd frontend
npm install
npm run dev
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
