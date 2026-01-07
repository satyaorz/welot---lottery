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

Copy the printed `NEXT_PUBLIC_*` env vars from the output.

### 3. Configure frontend

```bash
cd frontend
cp .env.example .env.local
# Paste the env vars from step 2
```

### 4. Install dependencies & run

```bash
npm install
npm run dev
```

Open http://localhost:3000

## Features

- **No-loss design**: Only yield goes to prizes; your deposits are always safe
- **Multi-token support**: Deposit USDe, USDC, mETH, or any configured token
- **Token selector**: Choose which token pool to participate in
- **Weekly draws**: Automated prize distribution every Friday at noon UTC
- **Automation**: Keeper-based draw execution (cron/relayer, Gelato, Defender, etc.)

## Keeper (Mantle)

This repo includes an off-chain keeper that calls `checkUpkeep` and then submits `performUpkeep(performData)` when needed.

```bash
cd frontend

export RPC_URL=https://rpc.sepolia.mantle.xyz
export CHAIN_ID=5003
export WELOT_VAULT=0xYourVault
export PRIVATE_KEY=0xyour_keeper_private_key

npm run keeper
```

The contract aligns 2-hour epochs to UTC even-hour boundaries (00:00, 02:00, 04:00, ...). The keeper can poll frequently (e.g. every 30s) and will only send a tx when `upkeepNeeded=true`.
- **Pyth Entropy**: Verifiable on-chain randomness for fair winner selection
- **Real-time stats**: See pool totals, your tickets, and claimable prizes

## Mantle Sepolia (5003) Deployment

Deployed on Mantle Sepolia testnet (chainId `5003`). For local dev or hosting (e.g. Vercel), set:

```env
NEXT_PUBLIC_RPC_URL=https://rpc.sepolia.mantle.xyz
NEXT_PUBLIC_CHAIN_ID=5003

# Core
NEXT_PUBLIC_WELOT_VAULT=0x8601C4932173571ee941fa0a26dE2379E351b164
NEXT_PUBLIC_ENTROPY=0x98046Bd286715D3B0BC227Dd7a956b83D8978603
NEXT_PUBLIC_FAUCET=0x8b4AFcf270A4727F377eCf8a167073B87ECa7658

# Tokens
NEXT_PUBLIC_USDE=0x271b8d3cdc2F5aD3Cc569ECe3cFDEA79EDC806E5
NEXT_PUBLIC_SUSDE=0x3F95B8124E51380Fbabc57ad3FbF32FD6669cDA8
NEXT_PUBLIC_USDC=0xc3f30eA136ac7f398Cdc1fc3877DAfcF9E5B517C
NEXT_PUBLIC_SUSDC=0xA35b6412E7e216e3EA032bb9e543bEFa5cD19152
NEXT_PUBLIC_METH=0x4Cf52d4cfb118F04e2A76808422b2573Cf3051Cc
NEXT_PUBLIC_SMETH=0x2b13239c4683d22F127ba7Af5B06Cb41d84f67Ad
```

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
NEXT_PUBLIC_USDE=0x...
NEXT_PUBLIC_SUSDE=0x...
NEXT_PUBLIC_USDC=0x...
NEXT_PUBLIC_SUSDC=0x...
NEXT_PUBLIC_METH=0x...
NEXT_PUBLIC_SMETH=0x...
```

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

- **Next.js 15** - React framework
- **Tailwind CSS** - Styling
- **Viem** - Ethereum interactions
- **TypeScript** - Type safety

## Icons

Icons from [Twemoji](https://twemoji.twitter.com/) (CC-BY 4.0), stored locally in `/public/icons/`.

## License

MIT
