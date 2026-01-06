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

// Supported tokens configuration
export const TOKENS: Record<string, TokenInfo> = {
  USDE: {
    address: asAddress(optionalEnv("NEXT_PUBLIC_USDE")) ?? ("0x" as Address),
    symbol: "USDe",
    name: "USDe",
    decimals: 18,
    icon: "/icons/usde.svg",
    vaultAddress: asAddress(optionalEnv("NEXT_PUBLIC_SUSDE")),
  },
  USDC: {
    address: asAddress(optionalEnv("NEXT_PUBLIC_USDC")) ?? ("0x" as Address),
    symbol: "USDC",
    name: "USD Coin",
    decimals: 6,
    icon: "/icons/usdc.svg",
    vaultAddress: asAddress(optionalEnv("NEXT_PUBLIC_SUSDC")),
  },
  METH: {
    address: asAddress(optionalEnv("NEXT_PUBLIC_METH")) ?? ("0x" as Address),
    symbol: "mETH",
    name: "Mantle ETH",
    decimals: 18,
    icon: "/icons/meth.svg",
    vaultAddress: asAddress(optionalEnv("NEXT_PUBLIC_SMETH")),
  },
};

// Main config
export const CONFIG = {
  vaultAddress: asAddress(optionalEnv("NEXT_PUBLIC_WELOT_VAULT")),
  entropyAddress: asAddress(optionalEnv("NEXT_PUBLIC_ENTROPY")),
  faucetAddress: asAddress(optionalEnv("NEXT_PUBLIC_FAUCET")),
  
  // Legacy support (for old deployments)
  legacyFaucetAddress: asAddress(optionalEnv("NEXT_PUBLIC_USDE_FAUCET")),
  
  // Token addresses
  usdeAddress: asAddress(optionalEnv("NEXT_PUBLIC_USDE")),
  susdeAddress: asAddress(optionalEnv("NEXT_PUBLIC_SUSDE")),
};

// Get all configured tokens (those with valid addresses)
export function getConfiguredTokens(): TokenInfo[] {
  return Object.values(TOKENS).filter(
    (t) => t.address && t.address !== "0x"
  );
}

// Mantle mainnet token addresses (for reference)
export const MANTLE_MAINNET_TOKENS = {
  USDE: "0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34" as Address,
  SUSDE: "0x211Cc4DD073734dA055fbF44a2b4667d5E5fE5d2" as Address,
  METH: "0xcDA86A272531e8640cD7F1a92c01839911B90bb0" as Address,
  USDC: "0x09Bc4E0D864854c6aFB6eB9A9cdF58aC190D0dF9" as Address,
  USDT: "0x201EBa5CC46D216Ce6DC03F6a759e8E766e956aE" as Address,
  WETH: "0xdEAddEaDdeadDEadDEADDEAddEADDEAddead1111" as Address,
};

