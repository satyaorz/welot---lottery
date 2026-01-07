#!/usr/bin/env node
/* eslint-disable @typescript-eslint/no-require-imports */
const { createPublicClient, createWalletClient, http, parseAbi } = require('viem');
const { privateKeyToAccount } = require('viem/accounts');

async function main() {
  const RPC_URL = process.env.RPC_URL || "https://rpc.testnet.mantle.xyz";
  const PRIVATE_KEY = process.env.PRIVATE_KEY;
  const ENTROPY = process.env.ENTROPY_ADDRESS || process.env.NEXT_PUBLIC_ENTROPY;

  if (!PRIVATE_KEY) {
    console.error('Missing PRIVATE_KEY in env');
    process.exit(1);
  }
  if (!ENTROPY) {
    console.error('Missing ENTROPY_ADDRESS or NEXT_PUBLIC_ENTROPY in env');
    process.exit(1);
  }

  const publicClient = createPublicClient({ transport: http(RPC_URL) });
  const account = privateKeyToAccount(PRIVATE_KEY);
  const wallet = createWalletClient({ account, transport: http(RPC_URL) });

  const abi = parseAbi([
    'function getFeeV2() view returns (uint256)',
    'function requestV2() payable returns (uint64)'
  ]);

  console.log('Entropy contract:', ENTROPY);
  console.log('RPC:', RPC_URL);

  const fee = await publicClient.readContract({ address: ENTROPY, abi, functionName: 'getFeeV2' });
  console.log('Entropy fee (wei):', fee.toString());

  console.log('Sending requestV2() with fee...');
  const txHash = await wallet.writeContract({
    address: ENTROPY,
    abi,
    functionName: 'requestV2',
    value: BigInt(fee),
  });

  console.log('txHash:', txHash);

  console.log('Waiting for receipt...');
  const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
  console.log('Receipt:', receipt);

  console.log('Done. If the entropy provider auto-fulfills, you should see a callback on the consumer contract. If using a mock entropy, call fulfill(seq, randomBytes) manually.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
