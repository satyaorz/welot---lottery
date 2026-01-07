import {
  createPublicClient,
  createWalletClient,
  defineChain,
  decodeAbiParameters,
  http,
  parseAbi,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

const REQUIRED_ENVS = ["RPC_URL", "CHAIN_ID", "WELOT_VAULT", "PRIVATE_KEY"];
for (const key of REQUIRED_ENVS) {
  if (!process.env[key]) {
    console.error(`Missing env var: ${key}`);
    process.exit(1);
  }
}

const RPC_URL = process.env.RPC_URL;
const CHAIN_ID = Number(process.env.CHAIN_ID);
const WELOT_VAULT = process.env.WELOT_VAULT;
const PRIVATE_KEY = process.env.PRIVATE_KEY;

const POLL_INTERVAL_MS = Number(process.env.POLL_INTERVAL_MS ?? "30000");
const ONCE = process.env.ONCE === "1";
const MAX_STEPS_PER_RUN = Number(process.env.MAX_STEPS_PER_RUN ?? "5");

const chain = defineChain({
  id: CHAIN_ID,
  name: `chain-${CHAIN_ID}`,
  nativeCurrency: { name: "Native", symbol: "NATIVE", decimals: 18 },
  rpcUrls: {
    default: { http: [RPC_URL] },
    public: { http: [RPC_URL] },
  },
});

const abi = parseAbi([
  "function checkUpkeep(bytes) view returns (bool upkeepNeeded, bytes performData)",
  "function performUpkeep(bytes performData)",
  "function automationForwarder() view returns (address)",
  "function currentEpochId() view returns (uint256)",
  "function epochStatus() view returns (uint8)",
  "function entropy() view returns (address)",
]);

const entropyAbi = parseAbi(["function getFeeV2() view returns (uint256)"]);

const account = privateKeyToAccount(PRIVATE_KEY);

const publicClient = createPublicClient({
  chain,
  transport: http(RPC_URL),
});

const walletClient = createWalletClient({
  account,
  chain,
  transport: http(RPC_URL),
});

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function topUpVaultIfNeeded() {
  const entropyAddr = await publicClient.readContract({
    address: WELOT_VAULT,
    abi,
    functionName: "entropy",
  });

  const fee = await publicClient.readContract({
    address: entropyAddr,
    abi: entropyAbi,
    functionName: "getFeeV2",
  });

  const bal = await publicClient.getBalance({ address: WELOT_VAULT });
  if (bal >= fee) return false;

  const topUp = fee - bal;
  console.log(`[keeper] topping up vault balance by ${topUp.toString()}`);
  const tx = await walletClient.sendTransaction({
    to: WELOT_VAULT,
    value: topUp,
  });
  await publicClient.waitForTransactionReceipt({ hash: tx });
  return true;
}

async function tick() {
  for (let step = 0; step < MAX_STEPS_PER_RUN; step++) {
    const epochId = await publicClient.readContract({
      address: WELOT_VAULT,
      abi,
      functionName: "currentEpochId",
    });

    const status = await publicClient.readContract({
      address: WELOT_VAULT,
      abi,
      functionName: "epochStatus",
    });

    const forwarder = await publicClient.readContract({
      address: WELOT_VAULT,
      abi,
      functionName: "automationForwarder",
    });

    // If `automationForwarder` is set, the contract will revert unless
    // `msg.sender` matches it. Warn early to avoid wasting gas.
    if (forwarder && forwarder !== "0x0000000000000000000000000000000000000000") {
      const fwd = String(forwarder).toLowerCase();
      const me = String(account.address).toLowerCase();
      if (fwd !== me) {
        console.error(
          `[keeper] ERROR: automationForwarder=${forwarder} blocks keeper EOA=${account.address}. ` +
            `Either unset it or set it to the keeper address.`
        );
        return;
      }
    }

    const [upkeepNeeded, performData] = await publicClient.readContract({
      address: WELOT_VAULT,
      abi,
      functionName: "checkUpkeep",
      args: ["0x"],
    });

    console.log(
      `[keeper] step=${step + 1}/${MAX_STEPS_PER_RUN} epoch=${epochId.toString()} ` +
        `status=${status.toString()} upkeepNeeded=${upkeepNeeded} automationForwarder=${forwarder} performData=${performData}`
    );

    // Contract intentionally returns upkeepNeeded=false when the epoch is Closed
    // but the vault isn't funded enough to pay Entropy's fee. In that case we can
    // top up proactively, then try again.
    if (!upkeepNeeded) {
      if (Number(status) === 1) {
        try {
          const didTopUp = await topUpVaultIfNeeded();
          if (didTopUp) continue;
        } catch (err) {
          console.error("[keeper] top-up check failed:", err);
        }
      }
      return;
    }

    // If the next action is "request randomness" (action=2), ensure the vault
    // has enough native balance to pay Entropy's fee. The contract checks its
    // own balance (not msg.value), so we top it up proactively.
    try {
      const [action] = decodeAbiParameters([{ type: "uint8" }], performData);
      if (Number(action) === 2) {
        await topUpVaultIfNeeded();
      }
    } catch {
      // Best-effort; if decoding fails, proceed.
    }

    const txHash = await walletClient.writeContract({
      address: WELOT_VAULT,
      abi,
      functionName: "performUpkeep",
      args: [performData],
    });

    console.log(`[keeper] sent performUpkeep tx=${txHash}`);

    const receipt = await publicClient.waitForTransactionReceipt({
      hash: txHash,
    });

    console.log(
      `[keeper] confirmed tx=${txHash} status=${receipt.status} block=${receipt.blockNumber}`
    );
  }

  console.warn(
    `[keeper] reached MAX_STEPS_PER_RUN=${MAX_STEPS_PER_RUN}; stopping to avoid infinite loop`
  );
}

async function main() {
  console.log(`[keeper] account=${account.address}`);
  console.log(`[keeper] vault=${WELOT_VAULT}`);
  console.log(`[keeper] rpc=${RPC_URL}`);
  console.log(`[keeper] chainId=${CHAIN_ID}`);
  console.log(
    `[keeper] pollIntervalMs=${POLL_INTERVAL_MS} once=${ONCE} maxStepsPerRun=${MAX_STEPS_PER_RUN}`
  );

  while (true) {
    try {
      await tick();
    } catch (err) {
      console.error("[keeper] error:", err);
    }

    if (ONCE) break;
    await sleep(POLL_INTERVAL_MS);
  }
}

main().catch((err) => {
  console.error("[keeper] fatal:", err);
  process.exit(1);
});
