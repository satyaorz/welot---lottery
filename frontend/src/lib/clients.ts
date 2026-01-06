import { createPublicClient, createWalletClient, custom, http } from "viem";
import type { Address, EIP1193Provider } from "viem";
import { localAnvil } from "./chains";
import { optionalEnv } from "./env";

export function getRpcUrl(): string {
  return optionalEnv("NEXT_PUBLIC_RPC_URL") ?? localAnvil.rpcUrls.default.http[0];
}

export function getPublicClient() {
  return createPublicClient({
    chain: localAnvil,
    transport: http(getRpcUrl()),
  });
}

export function getWalletClient(ethereum: EIP1193Provider) {
  return createWalletClient({
    chain: localAnvil,
    transport: custom(ethereum),
  });
}

export function shortAddr(addr: Address | undefined): string {
  if (!addr) return "";
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}
