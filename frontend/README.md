# WeLot - No-Loss Savings Lottery

A modern DeFi savings lottery on Mantle Network. Deposit stablecoins, earn lottery tickets, and win yield prizes — while your principal stays completely safe.

## Quick Start

### 1. Start local blockchain

```bash
anvil
```

### 2. Deploy contracts

```bash
cd contracts
forge script script/DeployLocal.s.sol:DeployLocalScript \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast
```

The deploy script prints `NEXT_PUBLIC_*` environment variables for the frontend. The frontend configuration is populated from those values.

Frontend setup (example):

```bash
cd frontend
cp .env.example .env.local
# Populate .env.local with the `NEXT_PUBLIC_*` values from the deploy output
npm install
npm run dev
```

The frontend is served at http://localhost:3000 when the dev server is running.

## Features

- **No-loss design**: Only yield goes to prizes; your deposits are always safe
- **Multi-token support**: Deposit USDC, USDT, or any configured stablecoin
- **Token selector**: Choose which token pool to participate in
- **Weekly draws**: Automated prize distribution every Friday at noon UTC
- **Automation**: Keeper-based draw execution (cron/relayer, Gelato, Defender, etc.)

## Keeper (Mantle)

An off-chain keeper is included. The keeper polls `checkUpkeep` and submits `performUpkeep(performData)` when on-chain conditions require action.

Keeper environment (required):

```bash
RPC_URL=
CHAIN_ID=5003
WELOT_VAULT=0x3A43e42cE9Fa6318C167C506112de9082BdDF703
PRIVATE_KEY=<keeper_private_key>    # provided via shell env or CI secret
```

The keeper implements two operational safeguards:

- The vault must hold sufficient native balance to pay Entropy fees. When the epoch is `Closed` but the vault balance is insufficient, `checkUpkeep` returns `upkeepNeeded=false` to avoid revert loops; the repository keeper may top up the vault and retry.
- If the owner configures `automationForwarder`, only the forwarder address may call `performUpkeep`; the keeper aborts if the configured forwarder differs from the keeper EOA.

Draw execution proceeds in three steps: close epoch → request randomness → finalize after the entropy callback.

## Mantle Sepolia (5003) deployment

Deploy using `contracts/script/DeployMantle.s.sol` and copy the printed `NEXT_PUBLIC_*` values into `frontend/.env.local`.

Addresses can change between redeploys; the deploy script output is the source of truth.

## Environment Variables

Create `.env.local` with these variables (output from deploy script):

```env
# Chain
NEXT_PUBLIC_CHAIN_ID=31337

# Core contracts
NEXT_PUBLIC_WELOT_VAULT=0x...
NEXT_PUBLIC_ENTROPY=0x...
NEXT_PUBLIC_FAUCET=0x...

# Tokens (addresses)
NEXT_PUBLIC_USDC=0x...
NEXT_PUBLIC_SUSDC=0x...
NEXT_PUBLIC_USDT=0x...
NEXT_PUBLIC_SUSDT=0x...
```

Current Mantle Sepolia deployment (present):

```dotenv
NEXT_PUBLIC_CHAIN_ID=5003
NEXT_PUBLIC_RPC_URL=

NEXT_PUBLIC_WELOT_VAULT=0x3A43e42cE9Fa6318C167C506112de9082BdDF703
NEXT_PUBLIC_ENTROPY=0x98046Bd286715D3B0BC227Dd7a956b83D8978603
NEXT_PUBLIC_FAUCET=0x3182189E8aA11778e9761679a77215eF3deB4b19

NEXT_PUBLIC_USDC=0xFD2a64348c829Da9e9CE3f688910909ecF6F384A
NEXT_PUBLIC_SUSDC=0x9fc2a8a2F28478f7575bF13E854f61699439EF70
NEXT_PUBLIC_USDT=0x53779f445FBCFB52A9bA5aC246969d2D2902b710
NEXT_PUBLIC_SUSDT=0x384F87AC9e01ab2bF061474771f1B06b4922F38d
```

# Mock Lendle Infrastructure

```dotenv
LENDLE_POOL=0x11C1719c30b17cba9eAbe6E79572FA4828064F38
aUSDC=0x5EE9536B1E6a95CF3a845Ebe23D5D7fd367a6E7C
aUSDT=0x09F0B77157177F1B7CF51B15C05C66fa6BD0e59b
```

Do not put private keys in `frontend/.env.local`. Keeper keys must be provided via shell env vars or CI/GitHub Actions secrets.

## Test Mode

When running on localhost (chainId 31337), the app shows test controls:

- **Claim [Token]**: Get 1000 test tokens from the faucet
- **Claim All Tokens**: Get all supported test tokens at once
- **Simulate Yield**: Add +50 yield to the current token's vault
- **Refresh Data**: Manually refresh all on-chain data

## Project Structure

```
frontend/
├── src/
│   ├── app/
│   │   ├── app/
│   │   │   └── page.tsx      # Main lottery UI
│   │   ├── layout.tsx        # Root layout
│   │   └── globals.css       # Global styles
│   └── lib/
│       ├── abis.ts           # Contract ABIs
│       ├── chains.ts         # Chain configurations
│       ├── clients.ts        # Viem clients
│       ├── config.ts         # Environment config
│       └── env.ts            # Env variable handling
├── public/
│   ├── brand/                # Logo assets
│   ├── icons/                # Twemoji icons
│   └── shapes/               # Decorative assets
└── assets/                   # Design assets
```

## Technologies

- **Next.js 16** - React framework
- **Tailwind CSS** - Styling
- **Viem** - Ethereum interactions
- **TypeScript** - Type safety

## Built

built during mantle gloabal hackathon :heart:

## License

UNLICENSED (hackathon/demo)
