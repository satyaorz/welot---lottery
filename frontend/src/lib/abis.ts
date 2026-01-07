// WelotVault ABI - Multi-token no-loss lottery
export const welotVaultAbi = [
  // ═══════════════════════════════════════════════════════════════════
  // ADMIN FUNCTIONS
  // ═══════════════════════════════════════════════════════════════════
  {
    type: "function",
    name: "addSupportedToken",
    stateMutability: "nonpayable",
    inputs: [
      { name: "token", type: "address" },
      { name: "yieldVault", type: "address" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "createPool",
    stateMutability: "nonpayable",
    inputs: [],
    outputs: [{ name: "poolId", type: "uint256" }],
  },

  // ═══════════════════════════════════════════════════════════════════
  // USER FUNCTIONS
  // ═══════════════════════════════════════════════════════════════════
  {
    type: "function",
    name: "deposit",
    stateMutability: "nonpayable",
    inputs: [
      { name: "token", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "depositTo",
    stateMutability: "nonpayable",
    inputs: [
      { name: "token", type: "address" },
      { name: "amount", type: "uint256" },
      { name: "poolId", type: "uint256" },
      { name: "recipient", type: "address" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "withdraw",
    stateMutability: "nonpayable",
    inputs: [
      { name: "token", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "withdrawFrom",
    stateMutability: "nonpayable",
    inputs: [
      { name: "token", type: "address" },
      { name: "amount", type: "uint256" },
      { name: "poolId", type: "uint256" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "claimPrize",
    stateMutability: "nonpayable",
    inputs: [{ name: "token", type: "address" }],
    outputs: [{ name: "prize", type: "uint256" }],
  },
  {
    type: "function",
    name: "claimPrizeFrom",
    stateMutability: "nonpayable",
    inputs: [
      { name: "token", type: "address" },
      { name: "poolId", type: "uint256" },
    ],
    outputs: [{ name: "prize", type: "uint256" }],
  },

  // ═══════════════════════════════════════════════════════════════════
  // VIEW FUNCTIONS
  // ═══════════════════════════════════════════════════════════════════
  {
    type: "function",
    name: "currentPrizePool",
    stateMutability: "view",
    inputs: [{ name: "token", type: "address" }],
    outputs: [{ name: "prize", type: "uint256" }],
  },
  {
    type: "function",
    name: "currentPrizePoolTotal",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "total", type: "uint256" }],
  },
  {
    type: "function",
    name: "totalAssets",
    stateMutability: "view",
    inputs: [{ name: "token", type: "address" }],
    outputs: [{ name: "assets", type: "uint256" }],
  },
  {
    type: "function",
    name: "totalDepositsNormalized",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "total", type: "uint256" }],
  },
  {
    type: "function",
    name: "tokenConfigs",
    stateMutability: "view",
    inputs: [{ name: "token", type: "address" }],
    outputs: [
      { name: "enabled", type: "bool" },
      { name: "yieldVault", type: "address" },
      { name: "decimals", type: "uint8" },
      { name: "totalDeposits", type: "uint256" },
      { name: "totalUnclaimedPrizes", type: "uint256" },
    ],
  },
  {
    type: "function",
    name: "supportedTokensLength",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "len", type: "uint256" }],
  },
  {
    type: "function",
    name: "getSupportedToken",
    stateMutability: "view",
    inputs: [{ name: "index", type: "uint256" }],
    outputs: [{ name: "token", type: "address" }],
  },
  {
    type: "function",
    name: "currentEpochId",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "epochId", type: "uint256" }],
  },
  {
    type: "function",
    name: "epochs",
    stateMutability: "view",
    inputs: [{ name: "epochId", type: "uint256" }],
    outputs: [
      { name: "start", type: "uint64" },
      { name: "end", type: "uint64" },
      { name: "status", type: "uint8" },
      { name: "entropySequence", type: "uint64" },
      { name: "randomness", type: "bytes32" },
      { name: "prize", type: "uint256" },
      { name: "winningPoolId", type: "uint256" },
    ],
  },
  {
    type: "function",
    name: "getTimeUntilDraw",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "seconds", type: "uint256" }],
  },
  {
    type: "function",
    name: "getNextFridayNoon",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "timestamp", type: "uint64" }],
  },
  {
    type: "function",
    name: "poolIdsLength",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "len", type: "uint256" }],
  },
  {
    type: "function",
    name: "poolIds",
    stateMutability: "view",
    inputs: [{ name: "index", type: "uint256" }],
    outputs: [{ name: "poolId", type: "uint256" }],
  },
  {
    type: "function",
    name: "pools",
    stateMutability: "view",
    inputs: [{ name: "poolId", type: "uint256" }],
    outputs: [
      { name: "exists", type: "bool" },
      { name: "creator", type: "address" },
      { name: "totalDeposits", type: "uint256" },
      { name: "rewardIndex", type: "uint256" },
      { name: "cumulative", type: "uint256" },
      { name: "lastTimestamp", type: "uint64" },
      { name: "lastBalance", type: "uint256" },
    ],
  },
  {
    type: "function",
    name: "getUserPosition",
    stateMutability: "view",
    inputs: [
      { name: "token", type: "address" },
      { name: "poolId", type: "uint256" },
      { name: "user", type: "address" },
    ],
    outputs: [
      { name: "deposited", type: "uint256" },
      { name: "claimable", type: "uint256" },
    ],
  },

  // Past winners (ring buffer)
  {
    type: "function",
    name: "getPastWinners",
    stateMutability: "view",
    inputs: [{ name: "limit", type: "uint256" }],
    outputs: [
      {
        name: "",
        type: "tuple[]",
        components: [
          { name: "epochId", type: "uint256" },
          { name: "timestamp", type: "uint64" },
          { name: "winningPoolId", type: "uint256" },
          { name: "poolCreator", type: "address" },
          { name: "totalPrizeNormalized", type: "uint256" },
        ],
      },
    ],
  },
  {
    type: "function",
    name: "epochTokenPrize",
    stateMutability: "view",
    inputs: [
      { name: "epochId", type: "uint256" },
      { name: "token", type: "address" },
    ],
    outputs: [{ name: "prize", type: "uint256" }],
  },

  // ═══════════════════════════════════════════════════════════════════
  // DRAW FUNCTIONS (can be called manually or by automation)
  // ═══════════════════════════════════════════════════════════════════
  {
    type: "function",
    name: "closeEpoch",
    stateMutability: "nonpayable",
    inputs: [],
    outputs: [],
  },
  {
    type: "function",
    name: "requestRandomness",
    stateMutability: "payable",
    inputs: [],
    outputs: [],
  },
  {
    type: "function",
    name: "finalizeDraw",
    stateMutability: "nonpayable",
    inputs: [],
    outputs: [],
  },

  // ═══════════════════════════════════════════════════════════════════
  // EVENTS
  // ═══════════════════════════════════════════════════════════════════
  {
    type: "event",
    name: "TokenAdded",
    inputs: [
      { name: "token", type: "address", indexed: true },
      { name: "yieldVault", type: "address", indexed: true },
    ],
  },
  {
    type: "event",
    name: "Deposited",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "token", type: "address", indexed: true },
      { name: "poolId", type: "uint256", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "Withdrawn",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "token", type: "address", indexed: true },
      { name: "poolId", type: "uint256", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "WinnerSelected",
    inputs: [
      { name: "epochId", type: "uint256", indexed: true },
      { name: "winningPoolId", type: "uint256", indexed: true },
      { name: "prize", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "PastWinnerRecorded",
    inputs: [
      { name: "epochId", type: "uint256", indexed: true },
      { name: "winningPoolId", type: "uint256", indexed: true },
      { name: "poolCreator", type: "address", indexed: true },
      { name: "totalPrizeNormalized", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "TokenPrizeRecorded",
    inputs: [
      { name: "epochId", type: "uint256", indexed: true },
      { name: "token", type: "address", indexed: true },
      { name: "prize", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "PrizeClaimed",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "token", type: "address", indexed: true },
      { name: "poolId", type: "uint256", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
] as const;

export const erc20Abi = [
  {
    type: "function",
    name: "approve",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "ok", type: "bool" }],
  },
  {
    type: "function",
    name: "allowance",
    stateMutability: "view",
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    outputs: [{ name: "amount", type: "uint256" }],
  },
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{ name: "owner", type: "address" }],
    outputs: [{ name: "amount", type: "uint256" }],
  },
  {
    type: "function",
    name: "decimals",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "decimals", type: "uint8" }],
  },
] as const;

export const mockErc20FaucetAbi = [
  {
    type: "function",
    name: "mint",
    stateMutability: "nonpayable",
    inputs: [
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [],
  },
] as const;

// Multi-token faucet ABI
export const faucetAbi = [
  {
    type: "function",
    name: "claim",
    stateMutability: "nonpayable",
    inputs: [{ name: "token", type: "address" }],
    outputs: [],
  },
  {
    type: "function",
    name: "claimAll",
    stateMutability: "nonpayable",
    inputs: [],
    outputs: [],
  },
  {
    type: "function",
    name: "canClaim",
    stateMutability: "view",
    inputs: [
      { name: "user", type: "address" },
      { name: "token", type: "address" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "getTokens",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address[]" }],
  },
] as const;

export const mockErc4626FaucetAbi = [
  {
    type: "function",
    name: "donateYield",
    stateMutability: "nonpayable",
    inputs: [{ name: "assets", type: "uint256" }],
    outputs: [],
  },
  {
    type: "function",
    name: "simulateYield",
    stateMutability: "nonpayable",
    inputs: [{ name: "assets", type: "uint256" }],
    outputs: [],
  },
] as const;
