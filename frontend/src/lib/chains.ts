import type { Chain } from "viem";

// Mantle Mainnet
export const mantleMainnet: Chain = {
  id: 5000,
  name: "Mantle",
  nativeCurrency: { name: "MNT", symbol: "MNT", decimals: 18 },
  rpcUrls: {
    default: { http: ["https://rpc.mantle.xyz"] },
    public: { http: ["https://rpc.mantle.xyz"] },
  },
  blockExplorers: {
    default: { name: "Mantlescan", url: "https://mantlescan.xyz" },
  },
};

// Mantle Sepolia Testnet
export const mantleTestnet: Chain = {
  id: 5003,
  name: "Mantle Sepolia",
  nativeCurrency: { name: "MNT", symbol: "MNT", decimals: 18 },
  rpcUrls: {
    default: { http: ["https://rpc.sepolia.mantle.xyz"] },
    public: { http: ["https://rpc.sepolia.mantle.xyz"] },
  },
  blockExplorers: {
    default: { name: "Mantlescan", url: "https://sepolia.mantlescan.xyz" },
  },
  testnet: true,
};

// Local Anvil for development
export const localAnvil: Chain = {
  id: 31337,
  name: "Anvil",
  nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: ["http://127.0.0.1:8545"] },
    public: { http: ["http://127.0.0.1:8545"] },
  },
};

// Get chain from env or default to local
export function getChain(): Chain {
  const chainId = process.env.NEXT_PUBLIC_CHAIN_ID;
  if (chainId === "5000") return mantleMainnet;
  if (chainId === "5003") return mantleTestnet;
  return localAnvil;
}

// All supported chains
export const supportedChains = [mantleMainnet, mantleTestnet, localAnvil];
