import { createPublicClient, createWalletClient, custom, http } from "viem";
import type { Address, EIP1193Provider } from "viem";
import { getChain, mantleMainnet, mantleTestnet, localAnvil } from "./chains";
import { optionalEnv } from "./env";

export function getRpcUrl(): string {
  const envRpc = optionalEnv("NEXT_PUBLIC_RPC_URL");
  if (envRpc) return envRpc;
  
  const chain = getChain();
  return chain.rpcUrls.default.http[0];
}

export function getPublicClient() {
  const chain = getChain();
  return createPublicClient({
    chain,
    transport: http(getRpcUrl()),
  });
}

export function getWalletClient(ethereum: EIP1193Provider) {
  const chain = getChain();
  return createWalletClient({
    chain,
    transport: custom(ethereum),
  });
}

export function shortAddr(addr: Address | undefined): string {
  if (!addr) return "";
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

export function getExplorerUrl(hash: string, type: "tx" | "address" = "tx"): string {
  const chain = getChain();
  const explorer = chain.blockExplorers?.default?.url;
  if (!explorer) return "";
  return `${explorer}/${type}/${hash}`;
}

