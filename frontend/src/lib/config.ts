import type { Address } from "viem";
import { optionalEnv } from "./env";

function asAddress(v: string | undefined): Address | undefined {
  if (!v) return undefined;
  return v as Address;
}

// Token info type
export interface TokenInfo {
  address: Address;
  symbol: string;
  name: string;
  decimals: number;
  icon: string;
  vaultAddress?: Address;
}

// Supported tokens configuration (USDC and USDT only - Lendle yield sources)
export const TOKENS: Record<string, TokenInfo> = {
  USDC: {
    address: asAddress(optionalEnv("NEXT_PUBLIC_USDC")) ?? ("0x" as Address),
    symbol: "USDC",
    name: "USD Coin",
    decimals: 6,
    icon: "/icons/usdc.svg",
    vaultAddress: asAddress(optionalEnv("NEXT_PUBLIC_SUSDC")),
  },
  USDT: {
    address: asAddress(optionalEnv("NEXT_PUBLIC_USDT")) ?? ("0x" as Address),
    symbol: "USDT",
    name: "Tether USD",
    decimals: 6,
    icon: "/icons/usdt.svg",
    vaultAddress: asAddress(optionalEnv("NEXT_PUBLIC_SUSDT")),
  },
};

// Main config
export const CONFIG = {
  vaultAddress: asAddress(optionalEnv("NEXT_PUBLIC_WELOT_VAULT")),
  entropyAddress: asAddress(optionalEnv("NEXT_PUBLIC_ENTROPY")),
  faucetAddress: asAddress(optionalEnv("NEXT_PUBLIC_FAUCET")),
};

// Get all configured tokens (those with valid addresses)
export function getConfiguredTokens(): TokenInfo[] {
  return Object.values(TOKENS).filter(
    (t) => t.address && t.address !== "0x"
  );
}

// Mantle mainnet token addresses (for reference)
export const MANTLE_MAINNET_TOKENS = {
  USDC: "0x09Bc4E0D864854c6aFB6eB9A9cdF58aC190D0dF9" as Address,
  USDT: "0x201EBa5CC46D216Ce6DC03F6a759e8E766e956aE" as Address,
  LENDLE_POOL: "0xCFa5aE7c2CE8Fadc6426C1ff872cA45378Fb7cF3" as Address,
};


