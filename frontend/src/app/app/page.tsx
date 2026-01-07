"use client";

import Link from "next/link";
import Image from "next/image";
import { useEffect, useState, useCallback } from "react";
import { useRouter } from "next/navigation";
import type { Address, EIP1193Provider } from "viem";
import { formatUnits, maxUint256, parseUnits } from "viem";

import { erc20Abi, faucetAbi, mockErc4626FaucetAbi, welotVaultAbi } from "@/lib/abis";
import { getPublicClient, getWalletClient, shortAddr } from "@/lib/clients";
import { CONFIG, getConfiguredTokens, type TokenInfo } from "@/lib/config";
import { getChain } from "@/lib/chains";

type InjectedProvider = EIP1193Provider & {
  request: (args: { method: string; params?: unknown[] | Record<string, unknown> }) => Promise<unknown>;
  providers?: InjectedProvider[];
  isMetaMask?: boolean;
  isRabby?: boolean;
  isCoinbaseWallet?: boolean;
};

function getInjectedProviders(): InjectedProvider[] {
  const eth = (globalThis as unknown as { ethereum?: unknown }).ethereum;
  if (!eth) return [];
  const maybeProvider = eth as Partial<InjectedProvider>;
  const providers = Array.isArray(maybeProvider.providers)
    ? (maybeProvider.providers as InjectedProvider[])
    : [eth as InjectedProvider];

  // Filter out obviously invalid entries
  return providers.filter((p) => typeof (p as InjectedProvider).request === "function");
}

function providerScore(p: InjectedProvider): number {
  // Prefer common wallets first; this avoids buggy/unknown injected providers.
  if (p.isMetaMask) return 100;
  if (p.isRabby) return 90;
  if (p.isCoinbaseWallet) return 80;
  return 10;
}

function getErrorMessage(err: unknown): string {
  if (typeof err === "string") return err;
  if (err && typeof err === "object") {
    const rec = err as Record<string, unknown>;
    const shortMessage = rec["shortMessage"];
    if (typeof shortMessage === "string" && shortMessage.trim()) return shortMessage;
    const message = rec["message"];
    if (typeof message === "string" && message.trim()) return message;
  }
  return String(err);
}

function safeParseUnits(value: string, decimals: number): bigint | null {
  if (!value) return 0n;
  try {
    return parseUnits(value, decimals);
  } catch {
    return null;
  }
}

// ════════════════════════════════════════════════════════════════════════════
// TYPES
// ════════════════════════════════════════════════════════════════════════════

interface TokenState {
  balance: bigint;
  allowance: bigint;
  deposits: bigint;
  claimable: bigint;
  prizePool: bigint;
}

// ════════════════════════════════════════════════════════════════════════════
// COMPONENTS
// ════════════════════════════════════════════════════════════════════════════

function TokenSelector({
  tokens,
  selected,
  onSelect,
}: {
  tokens: TokenInfo[];
  selected: TokenInfo | null;
  onSelect: (token: TokenInfo) => void;
}) {
  return (
    <div className="flex flex-wrap gap-2">
      {tokens.map((token) => (
        <button
          key={token.address}
          onClick={() => onSelect(token)}
          className={`rounded-xl border-2 border-black px-4 py-2 text-sm font-black transition-all ${
            selected?.address === token.address
              ? "bg-zinc-950 text-white shadow-[3px_3px_0_0_#000]"
              : "bg-white text-zinc-950 hover:bg-zinc-100"
          }`}
        >
          {token.symbol}
        </button>
      ))}
    </div>
  );
}

function StatCard({
  icon,
  label,
  value,
  subtext,
  color = "emerald",
}: {
  icon: string;
  label: string;
  value: string;
  subtext?: string;
  color?: "emerald" | "amber" | "pink";
}) {
  const bgColor = {
    emerald: "bg-lime-200",
    amber: "bg-amber-100",
    pink: "bg-pink-100",
  }[color];

  return (
    <div className={`rounded-2xl border-2 border-black ${bgColor} p-6 shadow-[6px_6px_0_0_#000]`}>
      <div className="flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-xl border-2 border-black bg-white">
          <Image src={icon} alt="" width={20} height={20} className="" />
        </div>
        <div className="text-sm font-black text-zinc-950">{label}</div>
      </div>
      <div className="mt-4 text-3xl font-black text-zinc-900">{value}</div>
      {subtext && <div className="mt-1 text-xs font-semibold text-zinc-800">{subtext}</div>}
    </div>
  );
}

function ActionCard({
  title,
  description,
  children,
}: {
  title: string;
  description?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="rounded-2xl border-2 border-black bg-white p-6 shadow-[6px_6px_0_0_#000]">
      <h3 className="text-lg font-black text-zinc-950">{title}</h3>
      {description && <p className="mt-1 text-sm font-semibold text-zinc-700">{description}</p>}
      <div className="mt-5">{children}</div>
    </div>
  );
}

function Input({
  value,
  onChange,
  placeholder,
  suffix,
}: {
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  suffix?: string;
}) {
  return (
    <div className="flex items-center gap-2 rounded-xl border-2 border-black bg-white px-4 py-3 shadow-[3px_3px_0_0_#000]">
      <input
        type="text"
        inputMode="decimal"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        className="w-full bg-transparent text-lg font-black text-zinc-950 outline-none placeholder:text-zinc-400"
      />
      {suffix && <span className="text-sm font-semibold text-zinc-500">{suffix}</span>}
    </div>
  );
}

function Button({
  children,
  onClick,
  disabled,
  variant = "primary",
  fullWidth,
}: {
  children: React.ReactNode;
  onClick?: () => void;
  disabled?: boolean;
  variant?: "primary" | "secondary" | "ghost";
  fullWidth?: boolean;
}) {
  const base =
    "rounded-xl border-2 border-black px-6 py-3 text-sm font-black shadow-[3px_3px_0_0_#000] disabled:opacity-50 disabled:cursor-not-allowed";
  const variants = {
    primary: "bg-zinc-950 text-zinc-50",
    secondary: "bg-lime-200 text-zinc-950",
    ghost: "bg-white text-zinc-950",
  };

  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className={`${base} ${variants[variant]} ${fullWidth ? "w-full" : ""}`}
    >
      {children}
    </button>
  );
}

// ════════════════════════════════════════════════════════════════════════════
// MAIN PAGE
// ════════════════════════════════════════════════════════════════════════════

export default function AppPage() {
  // Wallet state
  const [connected, setConnected] = useState(false);
  const [address, setAddress] = useState<Address | undefined>(undefined);
  const [walletProvider, setWalletProvider] = useState<InjectedProvider | undefined>(undefined);

  // Available tokens
  const [availableTokens, setAvailableTokens] = useState<TokenInfo[]>([]);
  const [selectedToken, setSelectedToken] = useState<TokenInfo | null>(null);
  
  // Token-specific state
  const [tokenStates, setTokenStates] = useState<Record<string, TokenState>>({});

  // Global state
  const [prizePool, setPrizePool] = useState(0n);
  type PastWinner = {
    epochId: bigint;
    winningPoolId: bigint;
    totalPrizeNormalized: bigint;
    timestamp: bigint;
  };

  const [pastWinners, setPastWinners] = useState<PastWinner[]>([]);
  const [timeUntilDraw, setTimeUntilDraw] = useState(0);
  const [epochStatus, setEpochStatus] = useState(0);
  const [epochEndTime, setEpochEndTime] = useState<number>(0);

  // Pools
  const [selectedPoolId, setSelectedPoolId] = useState<bigint>(1n);
  const [selectedPoolTokenDeposits, setSelectedPoolTokenDeposits] = useState(0n);

  // UI state
  const [depositAmount, setDepositAmount] = useState("");
  const [withdrawAmount, setWithdrawAmount] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");
  const [mounted, setMounted] = useState(false);
  const [showSimCallout, setShowSimCallout] = useState(false);

  useEffect(() => {
    const t = setTimeout(() => setShowSimCallout(true), 800);
    return () => clearTimeout(t);
  }, []);
  const router = useRouter();

  void router;

  const configOk = Boolean(CONFIG.vaultAddress);
  const faucetOk = Boolean(CONFIG.faucetAddress);
  const chain = getChain();
  const isLocalhost = chain.id === 31337;
  const isMantleSepolia = chain.id === 5003;
  const faucetUiEnabled = faucetOk && (isLocalhost || isMantleSepolia);

  // Current token state
  const currentState = selectedToken ? tokenStates[selectedToken.address] : null;
  const depositParsed = selectedToken ? safeParseUnits(depositAmount, selectedToken.decimals) : null;
  const withdrawParsed = selectedToken ? safeParseUnits(withdrawAmount, selectedToken.decimals) : null;

  const insufficientBalance =
    Boolean(selectedToken && currentState) &&
    depositParsed !== null &&
    depositParsed > 0n &&
    currentState!.balance < depositParsed;

  const insufficientDeposits =
    Boolean(selectedToken && currentState) &&
    withdrawParsed !== null &&
    withdrawParsed > 0n &&
    currentState!.deposits < withdrawParsed;

  const needsApproval = currentState && selectedToken
    ? depositParsed !== null && depositParsed > 0n
      ? currentState.allowance < depositParsed
      : false
    : false;

  const formatAmount = useCallback(
    (amount: bigint, decimals: number = 18) => {
      const formatted = formatUnits(amount, decimals);
      const num = parseFloat(formatted);
      if (num === 0) return "0";
      if (num < 0.01) return "<0.01";
      return num.toLocaleString(undefined, { maximumFractionDigits: 2 });
    },
    []
  );

  // Load available tokens from contract
  const loadTokens = useCallback(async () => {
    if (!configOk) {
      // If the main vault address isn't configured yet, fall back to the static
      // token list in `config.ts` so the TokenSelector is still usable in dev.
      const configuredTokens = getConfiguredTokens();
      setAvailableTokens(configuredTokens);
      if (configuredTokens.length > 0 && !selectedToken) {
        setSelectedToken(configuredTokens[0]);
      }
      return;
    }

    try {
      const publicClient = getPublicClient();
      
      // Get number of supported tokens
      const len = await publicClient.readContract({
        address: CONFIG.vaultAddress!,
        abi: welotVaultAbi,
        functionName: "supportedTokensLength",
      });

      const tokens: TokenInfo[] = [];
      for (let i = 0n; i < len; i++) {
        const tokenAddr = await publicClient.readContract({
          address: CONFIG.vaultAddress!,
          abi: welotVaultAbi,
          functionName: "getSupportedToken",
          args: [i],
        });

        const config = await publicClient.readContract({
          address: CONFIG.vaultAddress!,
          abi: welotVaultAbi,
          functionName: "tokenConfigs",
          args: [tokenAddr],
        });

        // Get token symbol
        let symbol = "TOKEN";
        try {
          const symbolResult = await publicClient.readContract({
            address: tokenAddr,
            abi: [{ type: "function", name: "symbol", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] }],
            functionName: "symbol",
          });
          symbol = symbolResult;
        } catch {}

        tokens.push({
          address: tokenAddr,
          symbol,
          name: symbol,
          decimals: config[2], // decimals from tokenConfigs
          icon: `/icons/${symbol.toLowerCase()}.svg`,
          vaultAddress: config[1] as Address, // yieldVault from tokenConfigs
        });
      }

      setAvailableTokens(tokens);
      if (tokens.length > 0 && !selectedToken) {
        setSelectedToken(tokens[0]);
      }
    } catch (err) {
      console.error("Load tokens error:", err);
      // Fallback to configured tokens
      const configuredTokens = getConfiguredTokens();
      setAvailableTokens(configuredTokens);
      if (configuredTokens.length > 0 && !selectedToken) {
        setSelectedToken(configuredTokens[0]);
      }
    }
  }, [configOk, selectedToken]);

  const refresh = useCallback(async () => {
    if (!configOk) return;

    try {
      const publicClient = getPublicClient();

      // Pools are fixed and auto-assigned in the contract.
      // Best-effort: if the method is missing (older deployments), fall back to pool 1.
      let effectivePoolId = selectedPoolId;
      if (address) {
        try {
          const pid = await publicClient.readContract({
            address: CONFIG.vaultAddress!,
            abi: welotVaultAbi,
            functionName: "assignedPoolId",
            args: [address],
          });
          if (typeof pid === "bigint" && pid > 0n) {
            effectivePoolId = pid;
            if (pid !== selectedPoolId) setSelectedPoolId(pid);
          }
        } catch {
          // ignore
        }
      }

      const [pot, epochId, timeLeft] = await Promise.all([
        publicClient.readContract({
          address: CONFIG.vaultAddress!,
          abi: welotVaultAbi,
          functionName: "currentPrizePoolTotal",
        }),
        publicClient.readContract({
          address: CONFIG.vaultAddress!,
          abi: welotVaultAbi,
          functionName: "currentEpochId",
        }),
        publicClient.readContract({
          address: CONFIG.vaultAddress!,
          abi: welotVaultAbi,
          functionName: "getTimeUntilDraw",
        }),
      ]);

      setPrizePool(pot);

      // Get epoch info
      const epoch = await publicClient.readContract({
        address: CONFIG.vaultAddress!,
        abi: welotVaultAbi,
        functionName: "epochs",
        args: [epochId],
      });

      const endTime = Number(epoch[1]);
      setEpochEndTime(endTime);
      setTimeUntilDraw(Math.max(0, Number(timeLeft)));
      setEpochStatus(Number(epoch[2]));

      // Past winners (newest first)
      try {
        const rows = await publicClient.readContract({
          address: CONFIG.vaultAddress!,
          abi: welotVaultAbi,
          functionName: "getPastWinners",
          args: [10n],
        });
        setPastWinners((rows as unknown as PastWinner[]) ?? []);
      } catch {
        // Older deployments may not have this method.
        setPastWinners([]);
      }

      // Per-pool token deposits (pool-local stats)
      if (selectedToken) {
        try {
          const poolTokenTotal = await publicClient.readContract({
            address: CONFIG.vaultAddress!,
            abi: welotVaultAbi,
            functionName: "poolTokenDeposits",
            args: [selectedToken.address, effectivePoolId ?? 1n],
          });
          setSelectedPoolTokenDeposits((poolTokenTotal as bigint | undefined) ?? 0n);
        } catch {
          setSelectedPoolTokenDeposits(0n);
        }
      } else {
        setSelectedPoolTokenDeposits(0n);
      }

      // User-specific data for each token
      if (address && availableTokens.length > 0) {
        const newStates: Record<string, TokenState> = {};
        const poolId = effectivePoolId ?? 1n;

        for (const token of availableTokens) {
          try {
            const [pos, balance, allowance, tokenPrize] = await Promise.all([
              publicClient.readContract({
                address: CONFIG.vaultAddress!,
                abi: welotVaultAbi,
                functionName: "getUserPosition",
                args: [token.address, poolId, address],
              }),
              publicClient.readContract({
                address: token.address,
                abi: erc20Abi,
                functionName: "balanceOf",
                args: [address],
              }),
              publicClient.readContract({
                address: token.address,
                abi: erc20Abi,
                functionName: "allowance",
                args: [address, CONFIG.vaultAddress!],
              }),
              publicClient.readContract({
                address: CONFIG.vaultAddress!,
                abi: welotVaultAbi,
                functionName: "currentPrizePool",
                args: [token.address],
              }),
            ]);

            newStates[token.address] = {
              deposits: pos[0],
              claimable: pos[1],
              balance,
              allowance,
              prizePool: tokenPrize,
            };
          } catch (err) {
            console.error(`Error loading ${token.symbol}:`, err);
          }
        }
        
        setTokenStates(newStates);
      }
    } catch (err) {
      console.error("Refresh error:", err);
    }
  }, [configOk, address, availableTokens, selectedToken, selectedPoolId]);

  const nextDrawUtc = useCallback(() => {
    if (!epochEndTime) return "";
    try {
      return new Date(epochEndTime * 1000).toUTCString();
    } catch {
      return "";
    }
  }, [epochEndTime]);

  // Load tokens on mount
  useEffect(() => {
    void loadTokens();
  }, [loadTokens]);

  // Mark client mounted to avoid SSR/CSR hydration mismatches for env-dependent UI
  useEffect(() => {
    setMounted(true);
  }, []);

  // Timer for countdown
  useEffect(() => {
    if (timeUntilDraw <= 0) return;
    const interval = setInterval(() => {
      setTimeUntilDraw((t) => Math.max(0, t - 1));
    }, 1000);
    return () => clearInterval(interval);
  }, [timeUntilDraw]);

  // Initial load
  useEffect(() => {
    void refresh();
    const interval = setInterval(() => void refresh(), 30000);
    return () => clearInterval(interval);
  }, [refresh]);

  const formatTime = (seconds: number) => {
    const d = Math.floor(seconds / 86400);
    const h = Math.floor((seconds % 86400) / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = seconds % 60;

    if (d > 0) return `${d}d ${h}h`;
    if (h > 0) return `${h}h ${m}m`;
    if (m > 0) return `${m}m ${s}s`;
    return `${s}s`;
  };

  const getEpochStatusText = (status: number) => {
    switch (status) {
      case 0:
        return "Accepting deposits";
      case 1:
        return "Draw closing...";
      case 2:
        return "Selecting winner...";
      case 3:
        return "Winner selected!";
      default:
        return "Active";
    }
  };

  // ══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ══════════════════════════════════════════════════════════════════════════

  async function connectWallet() {
    setError("");
    const providers = getInjectedProviders().sort((a, b) => providerScore(b) - providerScore(a));
    if (providers.length === 0) {
      setError("Please install a wallet like MetaMask");
      return;
    }

    let lastErr: unknown;
    for (const eth of providers) {
      try {
        const result = await eth.request({ method: "eth_requestAccounts" });
        const accounts = Array.isArray(result) ? (result as string[]) : [];
        setAddress(accounts?.[0] as Address | undefined);
        setConnected(Boolean(accounts?.[0]));
        setWalletProvider(eth);
        await refresh();
        return;
      } catch (err: unknown) {
        lastErr = err;
        // Try next provider
      }
    }

    // If all providers failed, surface the last error message.
    console.error("connectWallet error:", lastErr);
    const msg = (lastErr as { message?: string } | undefined)?.message ?? String(lastErr);
    setError(msg || "Failed to connect wallet");
  }

  function disconnectWallet() {
    setConnected(false);
    setAddress(undefined);
    setWalletProvider(undefined);
    setTokenStates({});
  }

  function requireWalletProvider(): InjectedProvider | undefined {
    if (!walletProvider) {
      setError("Wallet not connected");
      return undefined;
    }
    return walletProvider;
  }

  async function approve() {
    if (!connected || !address || !configOk || !selectedToken) return;
    setLoading(true);
    setError("");

    try {
      const eth = requireWalletProvider();
      if (!eth) return;
      const publicClient = getPublicClient();
      const walletClient = getWalletClient(eth);

      const hash = await walletClient.writeContract({
        address: selectedToken.address,
        abi: erc20Abi,
        functionName: "approve",
        args: [CONFIG.vaultAddress!, maxUint256],
        account: address,
      });

      await publicClient.waitForTransactionReceipt({ hash });

      setSuccess(`Approved ${selectedToken.symbol}!`);
      await refresh();
    } catch (err) {
      setError(getErrorMessage(err));
      console.error(err);
    } finally {
      setLoading(false);
    }
  }


  async function deposit() {
    if (!connected || !address || !configOk || !depositAmount || !selectedToken) return;
    setLoading(true);
    setError("");

    try {
      const eth = requireWalletProvider();
      if (!eth) return;
      const publicClient = getPublicClient();
      const walletClient = getWalletClient(eth);
      const amount = depositParsed;
      if (amount === null || amount === 0n) {
        setError("Enter a valid deposit amount");
        return;
      }

      if ((currentState?.balance ?? 0n) < amount) {
        setError(`Insufficient ${selectedToken.symbol} balance. Use Test Mode to claim tokens first.`);
        return;
      }

      const hash = await walletClient.writeContract({
        address: CONFIG.vaultAddress!,
        abi: welotVaultAbi,
        functionName: "deposit",
        args: [selectedToken.address, amount],
        account: address,
      });

      await publicClient.waitForTransactionReceipt({ hash });

      setDepositAmount("");
      setSuccess(`Deposited ${depositAmount} ${selectedToken.symbol}!`);
      await refresh();
    } catch (err) {
      setError(getErrorMessage(err));
      console.error(err);
    } finally {
      setLoading(false);
    }
  }

  async function withdraw() {
    if (!connected || !address || !configOk || !withdrawAmount || !selectedToken) return;
    setLoading(true);
    setError("");

    try {
      const eth = requireWalletProvider();
      if (!eth) return;
      const publicClient = getPublicClient();
      const walletClient = getWalletClient(eth);
      const amount = withdrawParsed;
      if (amount === null || amount === 0n) {
        setError("Enter a valid withdraw amount");
        return;
      }

      if ((currentState?.deposits ?? 0n) < amount) {
        setError(`Insufficient deposited ${selectedToken.symbol} to withdraw that amount.`);
        return;
      }

      const hash = await walletClient.writeContract({
        address: CONFIG.vaultAddress!,
        abi: welotVaultAbi,
        functionName: "withdraw",
        args: [selectedToken.address, amount],
        account: address,
      });

      await publicClient.waitForTransactionReceipt({ hash });

      setWithdrawAmount("");
      setSuccess(`Withdrew ${withdrawAmount} ${selectedToken.symbol}!`);
      await refresh();
    } catch (err) {
      setError(getErrorMessage(err));
      console.error(err);
    } finally {
      setLoading(false);
    }
  }

  async function claim() {
    if (!connected || !address || !configOk || !selectedToken) return;
    setLoading(true);
    setError("");

    try {
      const eth = requireWalletProvider();
      if (!eth) return;
      const publicClient = getPublicClient();
      const walletClient = getWalletClient(eth);

      const hash = await walletClient.writeContract({
        address: CONFIG.vaultAddress!,
        abi: welotVaultAbi,
        functionName: "claimPrize",
        args: [selectedToken.address],
        account: address,
      });

      await publicClient.waitForTransactionReceipt({ hash });

      setSuccess("Prize claimed!");
      await refresh();
    } catch (err) {
      setError(getErrorMessage(err));
      console.error(err);
    } finally {
      setLoading(false);
    }
  }

  async function mintTestTokens() {
    if (!connected || !address || !faucetOk || !selectedToken) return;
    setLoading(true);
    setError("");

    try {
      const eth = requireWalletProvider();
      if (!eth) return;
      const publicClient = getPublicClient();
      const walletClient = getWalletClient(eth);

      const hash = await walletClient.writeContract({
        address: CONFIG.faucetAddress!,
        abi: faucetAbi,
        functionName: "claim",
        args: [selectedToken.address],
        account: address,
      });

      await publicClient.waitForTransactionReceipt({ hash });

      setSuccess(`Claimed 1000 ${selectedToken.symbol}!`);
      await refresh();
    } catch (err) {
      setError(getErrorMessage(err));
      console.error(err);
    } finally {
      setLoading(false);
    }
  }

  async function mintAllTestTokens() {
    if (!connected || !address || !faucetOk) return;
    setLoading(true);
    setError("");

    try {
      const eth = requireWalletProvider();
      if (!eth) return;
      const publicClient = getPublicClient();
      const walletClient = getWalletClient(eth);

      const hash = await walletClient.writeContract({
        address: CONFIG.faucetAddress!,
        abi: faucetAbi,
        functionName: "claimAll",
        account: address,
      });

      await publicClient.waitForTransactionReceipt({ hash });

      setSuccess("Claimed all available test tokens!");
      await refresh();
    } catch (err) {
      setError(getErrorMessage(err));
      console.error(err);
    } finally {
      setLoading(false);
    }
  }

  async function simulateYield() {
    if (!connected || !address || !selectedToken?.vaultAddress) return;
    setLoading(true);
    setError("");

    try {
      const eth = requireWalletProvider();
      if (!eth) return;
      const publicClient = getPublicClient();
      const walletClient = getWalletClient(eth);
      const amount = parseUnits("50", selectedToken.decimals);

      // Local mock: mint yield directly into the vault so prize pool increases without
      // requiring the user to donate tokens.
      const yieldHash = await walletClient.writeContract({
        address: selectedToken.vaultAddress,
        abi: mockErc4626FaucetAbi,
        functionName: "simulateYield",
        args: [amount],
        account: address,
      });

      await publicClient.waitForTransactionReceipt({ hash: yieldHash });

      setSuccess(`Simulated 50 ${selectedToken.symbol} yield!`);
      await refresh();
    } catch (err) {
      setError(getErrorMessage(err));
      console.error(err);
    } finally {
      setLoading(false);
    }
  }

  // Clear messages after delay
  useEffect(() => {
    if (success) {
      const t = setTimeout(() => setSuccess(""), 3000);
      return () => clearTimeout(t);
    }
  }, [success]);

  useEffect(() => {
    if (error) {
      const t = setTimeout(() => setError(""), 5000);
      return () => clearTimeout(t);
    }
  }, [error]);

  // ══════════════════════════════════════════════════════════════════════════
  // RENDER
  // ══════════════════════════════════════════════════════════════════════════

  return (
    <div className="min-h-dvh bg-grid bg-grid-tight text-zinc-950">

      <main className="relative mx-auto w-full max-w-6xl px-6 pt-6 pb-10">
        {/* Compact top bar: logo left, wallet controls right */}
        <div className="mb-6 flex items-center justify-between relative">
          <div className="flex items-center gap-3">
            <Link href="/" className="flex items-center">
              <div className="we-card rounded-2xl border-2 border-black bg-white p-2 shadow-[4px_4px_0_0_#000]">
                <Image src="/brand/logo.png" alt="welot" width={60} height={60} priority />
              </div>
            </Link>

          </div>
          <div className="flex items-center gap-3">
            <div className="relative inline-block">
              <Link
                href="/simulation"
                className={`sim-link rounded-xl border-2 border-black bg-amber-100 px-3 py-1.5 text-xs font-black shadow-[2px_2px_0_0_#000] hover:bg-amber-200 transition-colors`}
              >
                🧪 Simulation <span className="sim-dot ml-2 inline-block" aria-hidden></span>
              </Link>

              {showSimCallout && (
                <div className="sim-callout absolute right-0 top-full mt-2 z-30">
                  <div className="we-card rounded-2xl border-2 border-black bg-white p-3 shadow-[6px_6px_0_0_#000] w-80">
                    <div className="flex items-start gap-3">
                      <div className="text-2xl">🧪</div>
                      <div>
                        <div className="font-black">Try the Simulation</div>
                        <div className="text-sm text-zinc-700 mt-1">Visualize draws, tickets, and prize evolution — safe demo mode.</div>
                        <div className="mt-3 flex gap-2">
                          <button
                            onClick={() => {
                              setShowSimCallout(false);
                              router.push('/simulation');
                            }}
                            className="btn rounded-xl border-2 border-black bg-amber-100 px-3 py-1.5 text-xs font-black shadow-[2px_2px_0_0_#000]"
                          >
                            Open Simulation
                          </button>
                          <button onClick={() => setShowSimCallout(false)} className="rounded-xl border px-3 py-1 text-xs">Got it</button>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              )}
            </div>

            {connected && address ? (
              <div className="flex items-center gap-3">
                <div className="rounded-2xl border-2 border-black bg-amber-100 px-4 py-2 text-sm font-black">
                  {shortAddr(address)}
                </div>
                <button
                  onClick={disconnectWallet}
                  className="rounded-2xl border-2 border-black bg-white px-4 py-2 text-sm font-black shadow-[3px_3px_0_0_#000]"
                >
                  Disconnect
                </button>
              </div>
            ) : (
              <button
                onClick={connectWallet}
                className="rounded-2xl border-2 border-black bg-zinc-950 px-6 py-2.5 text-sm font-black text-zinc-50 shadow-[3px_3px_0_0_#000]"
              >
                Connect Wallet
              </button>
            )}
          </div>

          

        </div>
        {/* Y2K shapes (decor only) */}
        <div aria-hidden className="pointer-events-none absolute -top-6 -left-64 z-0 hidden lg:block">
          <Image
            src="/shapes/y2k/shape-68.png"
            alt=""
            width={170}
            height={170}
            className="y2k-cyan we-floaty opacity-40 rotate-6"
          />
        </div>
        <div aria-hidden className="pointer-events-none absolute top-16 -right-64 z-0 hidden lg:block">
          <Image
            src="/shapes/y2k/shape-12.png"
            alt=""
            width={150}
            height={150}
            className="y2k-pink opacity-35 -rotate-12"
          />
        </div>

        <div className="relative z-10">
        {/* Notifications */}
        {error && (
          <div className="mb-6 rounded-2xl border-2 border-black bg-red-100 px-4 py-3 text-sm font-black text-red-900 shadow-[4px_4px_0_0_#000]">
            {error}
          </div>
        )}
        {success && (
          <div className="mb-6 rounded-2xl border-2 border-black bg-lime-200 px-4 py-3 text-sm font-black text-zinc-950 shadow-[4px_4px_0_0_#000]">
            {success}
          </div>
        )}

        {mounted && !configOk && (
          <div className="mb-6 rounded-2xl border-2 border-black bg-amber-100 px-4 py-3 text-sm font-black text-zinc-950 shadow-[4px_4px_0_0_#000]">
            Contract addresses not configured. Deploy contracts and set NEXT_PUBLIC_WELOT_VAULT in .env.local
          </div>
        )}

        {/* Token Selector */}
        {mounted && availableTokens.length > 0 && (
          <div className="mb-6">
            <div className="text-sm font-black text-zinc-950 mb-2">Select Token</div>
            <TokenSelector tokens={availableTokens} selected={selectedToken} onSelect={setSelectedToken} />
          </div>
        )}

        {/* Auto-assigned Pool */}
        {mounted && configOk && (
          <div className="mb-6">
            <div className="mb-2 flex items-center justify-between">
              <div className="text-sm font-black text-zinc-950">Your Pool</div>
              <div className="rounded-xl border-2 border-black bg-amber-100 px-4 py-3 text-xs font-black text-zinc-950 shadow-[3px_3px_0_0_#000]">
                Auto-assigned
              </div>
            </div>
            <div className="rounded-xl border-2 border-black bg-white px-4 py-3 text-sm font-black text-zinc-950 shadow-[3px_3px_0_0_#000]">
              Pool #{selectedPoolId.toString()}
            </div>
          </div>
        )}

        {/* Prize Pool Hero */}
        <div className="we-card relative overflow-hidden rounded-3xl border-2 border-black bg-lime-200 shadow-[10px_10px_0_0_#000]">
          <div aria-hidden className="pointer-events-none absolute -bottom-10 -left-10 z-0 hidden md:block">
            <Image
              src="/shapes/y2k/shape-57.png"
              alt=""
              width={180}
              height={180}
              className="y2k-purple opacity-25 rotate-12"
            />
          </div>
          <div className="relative z-10 p-9">
          <div className="flex flex-col gap-6 md:flex-row md:items-center md:justify-between">
            <div>
              <div className="text-sm font-black text-zinc-950">Total Prize Pool</div>
                  <div className="mt-2 text-5xl font-black text-zinc-950 font-pixel">${formatAmount(prizePool)}</div>
              <div className="mt-2 text-sm font-semibold text-zinc-800">
                {getEpochStatusText(epochStatus)}
                {epochEndTime ? ` • Next draw: ${nextDrawUtc()}` : ""}
              </div>
            </div>
            <div className="rounded-2xl border-2 border-black bg-white px-6 py-4 shadow-[6px_6px_0_0_#000]">
              <div className="text-sm font-black text-zinc-950">Next Draw</div>
                  <div className="mt-1 text-3xl font-black text-zinc-950 font-pixel">
                {timeUntilDraw > 0 ? formatTime(timeUntilDraw) : "Soon!"}
              </div>
            </div>
          </div>
          </div>
        </div>

        {/* Stats */}
        <div className="mt-8 grid gap-6 md:grid-cols-3">
          <StatCard
            icon="/icons/moneybag.svg"
            label="Your Deposits"
            value={`${formatAmount(currentState?.deposits ?? 0n, selectedToken?.decimals ?? 18)} ${selectedToken?.symbol ?? ''}`}
            subtext="Your principal (always withdrawable)"
            color="emerald"
          />
          <StatCard
            icon="/icons/ticket.svg"
            label="Selected Pool"
            value={`#${selectedPoolId.toString()}`}
            subtext="Winning is pool-based, time-weighted"
            color="amber"
          />
          <StatCard
            icon="/icons/trophy.svg"
            label="Winnings"
            value={`${formatAmount(currentState?.claimable ?? 0n, selectedToken?.decimals ?? 18)} ${selectedToken?.symbol ?? ''}`}
            subtext={(currentState?.claimable ?? 0n) > 0n ? "Ready to claim!" : "Win the next draw"}
            color="pink"
          />
        </div>

        {/* Actions */}
        <div className="mt-10 grid gap-6 lg:grid-cols-2">
          {/* Deposit */}
          <ActionCard title="Deposit" description={`Add ${selectedToken?.symbol ?? 'tokens'} to get lottery tickets`}>
            <div className="space-y-4">
              <div>
                <div className="mb-2 flex items-center justify-between text-sm">
                  <span className="text-zinc-500">Amount</span>
                  <span className="text-zinc-600">
                    Balance: <span className="font-semibold">{formatAmount(currentState?.balance ?? 0n, selectedToken?.decimals ?? 18)} {selectedToken?.symbol ?? ''}</span>
                  </span>
                </div>
                <Input
                  value={depositAmount}
                  onChange={setDepositAmount}
                  placeholder="0.00"
                  suffix={selectedToken?.symbol ?? 'TOKEN'}
                />
              </div>
              <div className="flex gap-3">
                {needsApproval ? (
                  <Button onClick={approve} disabled={loading || !connected} fullWidth>
                    {loading ? "Approving..." : `Approve ${selectedToken?.symbol ?? ''}`}
                  </Button>
                ) : (
                  <Button
                    onClick={deposit}
                    disabled={
                      loading ||
                      !connected ||
                      !depositAmount ||
                      depositParsed === null ||
                      depositParsed === 0n ||
                      insufficientBalance
                    }
                    fullWidth
                  >
                    {loading ? "Depositing..." : "Deposit"}
                  </Button>
                )}
              </div>
            </div>
          </ActionCard>

          {/* Withdraw */}
          <ActionCard title="Withdraw" description="Get your money back anytime">
            <div className="space-y-4">
              <div>
                <div className="mb-2 flex items-center justify-between text-sm">
                  <span className="text-zinc-500">Amount</span>
                  <span className="text-zinc-600">
                    Deposited: <span className="font-semibold">{formatAmount(currentState?.deposits ?? 0n, selectedToken?.decimals ?? 18)} {selectedToken?.symbol ?? ''}</span>
                  </span>
                </div>
                <Input
                  value={withdrawAmount}
                  onChange={setWithdrawAmount}
                  placeholder="0.00"
                  suffix={selectedToken?.symbol ?? 'TOKEN'}
                />
              </div>
              <Button
                onClick={withdraw}
                disabled={
                  loading ||
                  !connected ||
                  !withdrawAmount ||
                  withdrawParsed === null ||
                  withdrawParsed === 0n ||
                  insufficientDeposits
                }
                fullWidth
              >
                {loading ? "Withdrawing..." : "Withdraw"}
              </Button>
            </div>
          </ActionCard>
        </div>

        {/* Claim Prize */}
        {(currentState?.claimable ?? 0n) > 0n && (
          <div className="mt-6">
            <ActionCard title="🎉 You won!" description={`Claim your ${selectedToken?.symbol ?? ''} prize winnings`}>
              <div className="flex items-center justify-between">
                <div className="text-2xl font-black text-pink-600">{formatAmount(currentState?.claimable ?? 0n, selectedToken?.decimals ?? 18)} {selectedToken?.symbol ?? ''}</div>
                <Button onClick={claim} disabled={loading}>
                  {loading ? "Claiming..." : "Claim Prize"}
                </Button>
              </div>
            </ActionCard>
          </div>
        )}

        {/* Test Controls (only for localhost) */}
        {mounted && faucetUiEnabled && (
          <div className="mt-10 rounded-3xl border-2 border-black bg-white p-6 shadow-[8px_8px_0_0_#000]">
            <div className="text-sm font-black text-zinc-950">Test Mode (testnet/dev)</div>
            <div className="mt-2 text-xs font-semibold text-zinc-700">
              Use the faucet to mint test tokens and simulate yield.
            </div>
            <div className="mt-4 flex flex-wrap gap-3">
              <Button variant="secondary" onClick={mintTestTokens} disabled={loading || !connected || !selectedToken}>
                Claim 1000 {selectedToken?.symbol ?? 'Tokens'}
              </Button>
              <Button variant="secondary" onClick={mintAllTestTokens} disabled={loading || !connected}>
                Claim All Tokens
              </Button>
              <Button variant="secondary" onClick={simulateYield} disabled={loading || !connected}>
                Simulate Yield (+50)
              </Button>
              <Button variant="ghost" onClick={() => void refresh()}>
                Refresh Data
              </Button>
            </div>
          </div>
        )}

        {/* Info */}
        <div className="mt-16 grid gap-6 md:grid-cols-2">
          <div className="we-card rounded-3xl border-2 border-black bg-white p-8 shadow-[6px_6px_0_0_#000]">
            <h3 className="font-display mag-underline text-3xl text-zinc-950">How winning works</h3>
            <ul className="mt-4 space-y-3 text-sm font-semibold text-zinc-800">
              <li className="flex gap-3">
                <span className="text-zinc-950">•</span>
                A winning pool is selected each draw (time-weighted by deposits)
              </li>
              <li className="flex gap-3">
                <span className="text-zinc-950">•</span>
                Weekly draws happen Friday 12:00 UTC
              </li>
              <li className="flex gap-3">
                <span className="text-zinc-950">•</span>
                If your pool wins, yield prizes are split pro-rata within that pool
              </li>
              <li className="flex gap-3">
                <span className="text-zinc-950">•</span>
                Your deposits are never at risk
              </li>
            </ul>
          </div>
          <div className="we-card rounded-3xl border-2 border-black bg-white p-8 shadow-[6px_6px_0_0_#000]">
            <h3 className="font-display mag-underline text-3xl text-zinc-950">Pool Stats (Pool #{selectedPoolId.toString()} • {selectedToken?.symbol ?? 'Token'})</h3>
            <div className="mt-4 space-y-3 text-sm font-semibold">
              <div className="flex items-center justify-between">
                <span className="text-zinc-800">Pool Deposits</span>
                <span className="font-black text-zinc-950">{formatAmount(selectedPoolTokenDeposits, selectedToken?.decimals ?? 18)} {selectedToken?.symbol ?? ''}</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-zinc-800">Prize Pool</span>
                <span className="font-black text-zinc-950">{formatAmount(currentState?.prizePool ?? 0n, selectedToken?.decimals ?? 18)} {selectedToken?.symbol ?? ''}</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-zinc-800">Your Share</span>
                <span className="font-black text-zinc-950">
                  {selectedPoolTokenDeposits > 0n
                    ? (() => {
                        const d = currentState?.deposits ?? 0n;
                        const bps = (d * 10_000n) / selectedPoolTokenDeposits;
                        const pctInt = bps / 100n;
                        const pctFrac = bps % 100n;
                        return `${pctInt}.${pctFrac.toString().padStart(2, "0")}%`;
                      })()
                    : "0%"}
                </span>
              </div>
            </div>
          </div>
        </div>

        {/* Past Winners */}
        <div className="mt-10 we-card rounded-3xl border-2 border-black bg-white p-8 shadow-[6px_6px_0_0_#000]">
          <h3 className="font-display mag-underline text-3xl text-zinc-950">Past Winners (on-chain)</h3>
          {pastWinners.length === 0 ? (
            <div className="mt-4 text-sm font-semibold text-zinc-700">No past winners yet (or still loading).</div>
          ) : (
            <div className="mt-4 space-y-2 text-sm font-semibold">
              {pastWinners.map((w) => (
                <div key={String(w.epochId)} className="flex items-center justify-between rounded-2xl border-2 border-black bg-zinc-50 px-4 py-3">
                  <div>
                    <div className="font-black text-zinc-950">Epoch #{w.epochId.toString()}</div>
                    <div className="text-xs text-zinc-700">Pool #{w.winningPoolId.toString()}</div>
                  </div>
                  <div className="font-black text-green-700">${formatAmount(w.totalPrizeNormalized, 18)}</div>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Footer */}
        <footer className="mt-16 border-t-2 border-black pt-8 text-center text-xs font-semibold text-zinc-800">
          Built during Mantle Global Hackathon ❤️
        </footer>
        </div>
      </main>
    </div>
  );
}
