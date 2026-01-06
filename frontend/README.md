# welot - No-Loss Savings Lottery

A modern DeFi savings lottery where you deposit stablecoins, earn lottery tickets, and can win yield prizes — while your principal stays safe.

## Quick Start

### 1. Start local blockchain

```bash
anvil
```

### 2. Deploy contracts

```bash
cd contracts
forge script script/DeployLocal.s.sol:DeployLocalScript --rpc-url http://127.0.0.1:8545 --broadcast
```

Copy the printed `NEXT_PUBLIC_*` env vars.

### 3. Configure frontend

```bash
cd frontend
cp .env.example .env.local
# Paste the env vars from step 2
```

### 4. Run frontend

```bash
npm run dev
```

Open http://localhost:3000

## Features

- **No-loss design**: Only yield goes to prizes; your deposits are always safe
- **Simple UX**: Deposit → Get tickets → Win prizes → Withdraw anytime
- **Weekly draws**: Automated prize distribution every week
- **Chainlink Automation**: Decentralized draw execution
- **OpenZeppelin security**: Built with battle-tested contracts

## Test Mode

On localhost, the app shows test controls to:
- Mint test tokens
- Simulate yield accumulation

## Icons

Icons from Twemoji (CC-BY 4.0), stored locally in `/public/icons/`.
