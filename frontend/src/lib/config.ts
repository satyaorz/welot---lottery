import type { Address } from "viem";
import { optionalEnv } from "./env";

function asAddress(v: string | undefined): Address | undefined {
  if (!v) return undefined;
  return v as Address;
}

export const CONFIG = {
  vaultAddress: asAddress(optionalEnv("NEXT_PUBLIC_WELOT_VAULT")),
  usdeAddress: asAddress(optionalEnv("NEXT_PUBLIC_USDE")),
  susdeAddress: asAddress(optionalEnv("NEXT_PUBLIC_SUSDE")),
};
