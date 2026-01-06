"use client";

import Link from "next/link";
import Image from "next/image";
import { useEffect, useState, useCallback } from "react";
import type { Address, EIP1193Provider } from "viem";
import { formatUnits, maxUint256, parseUnits } from "viem";

import { erc20Abi, mockErc20FaucetAbi, mockErc4626FaucetAbi, welotVaultAbi } from "@/lib/abis";
import { getPublicClient, getWalletClient, shortAddr } from "@/lib/clients";
import { CONFIG } from "@/lib/config";

// ════════════════════════════════════════════════════════════════════════════
// COMPONENTS
// ════════════════════════════════════════════════════════════════════════════

function Header({
  connected,
  address,
  onConnect,
  onDisconnect,
}: {
  connected: boolean;
  address?: Address;
  onConnect: () => void;
  onDisconnect: () => void;
}) {
  return (
    <header className="border-b-2 border-black bg-white">
      <div className="mx-auto flex w-full max-w-6xl items-center justify-between px-6 py-5">
        <Link href="/" className="flex items-center gap-3">
          <div className="we-card rounded-2xl border-2 border-black bg-white p-3 shadow-[4px_4px_0_0_#000]">
            <Image src="/brand/logo.png" alt="welot" width={120} height={52} priority />
          </div>
        </Link>

        <div className="flex items-center gap-3">
          {connected && address ? (
            <div className="flex items-center gap-3">
              <div className="rounded-2xl border-2 border-black bg-amber-100 px-4 py-2 text-sm font-black">
                {shortAddr(address)}
              </div>
              <button
                onClick={onDisconnect}
                className="rounded-2xl border-2 border-black bg-white px-4 py-2 text-sm font-black shadow-[3px_3px_0_0_#000]"
              >
                Disconnect
              </button>
            </div>
          ) : (
            <button
              onClick={onConnect}
              className="rounded-2xl border-2 border-black bg-zinc-950 px-6 py-2.5 text-sm font-black text-zinc-50 shadow-[3px_3px_0_0_#000]"
            >
              Connect Wallet
            </button>
          )}
        </div>
      </div>
    </header>
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

  // Contract state
  const [decimals, setDecimals] = useState(18);
  const [balance, setBalance] = useState(0n);
  const [allowance, setAllowance] = useState(0n);
  const [deposits, setDeposits] = useState(0n);
  const [claimable, setClaimable] = useState(0n);
  const [totalDeposits, setTotalDeposits] = useState(0n);
  const [prizePool, setPrizePool] = useState(0n);
  const [timeUntilDraw, setTimeUntilDraw] = useState(0);
  const [epochStatus, setEpochStatus] = useState(0);

  // UI state
  const [depositAmount, setDepositAmount] = useState("");
  const [withdrawAmount, setWithdrawAmount] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");

  const configOk = Boolean(CONFIG.vaultAddress && CONFIG.usdeAddress);
  const faucetOk = Boolean(CONFIG.usdeAddress && CONFIG.susdeAddress);
  const needsApproval = allowance < parseUnits(depositAmount || "0", decimals);

  const formatAmount = useCallback(
    (amount: bigint) => {
      const formatted = formatUnits(amount, decimals);
      const num = parseFloat(formatted);
      if (num === 0) return "0";
      if (num < 0.01) return "<0.01";
      return num.toLocaleString(undefined, { maximumFractionDigits: 2 });
    },
    [decimals]
  );

  const refresh = useCallback(async () => {
    if (!configOk) return;

    try {
      const publicClient = getPublicClient();

      const [dec, pot, total, epochId] = await Promise.all([
        publicClient.readContract({
          address: CONFIG.usdeAddress!,
          abi: erc20Abi,
          functionName: "decimals",
        }),
        publicClient.readContract({
          address: CONFIG.vaultAddress!,
          abi: welotVaultAbi,
          functionName: "prizePot",
        }),
        publicClient.readContract({
          address: CONFIG.vaultAddress!,
          abi: welotVaultAbi,
          functionName: "totalPrincipal",
        }),
        publicClient.readContract({
          address: CONFIG.vaultAddress!,
          abi: welotVaultAbi,
          functionName: "currentEpochId",
        }),
      ]);

      setDecimals(Number(dec));
      setPrizePool(pot);
      setTotalDeposits(total);

      // Get epoch info
      const epoch = await publicClient.readContract({
        address: CONFIG.vaultAddress!,
        abi: welotVaultAbi,
        functionName: "epochs",
        args: [epochId],
      });

      const endTime = Number(epoch[1]);
      const now = Math.floor(Date.now() / 1000);
      setTimeUntilDraw(Math.max(0, endTime - now));
      setEpochStatus(Number(epoch[2]));

      // User-specific data
      if (address) {
        // Get first pool ID
        const len = await publicClient.readContract({
          address: CONFIG.vaultAddress!,
          abi: welotVaultAbi,
          functionName: "podIdsLength",
        });

        if (Number(len) > 0) {
          const poolId = await publicClient.readContract({
            address: CONFIG.vaultAddress!,
            abi: welotVaultAbi,
            functionName: "podIds",
            args: [0n],
          });

          const [pos, bal, allow] = await Promise.all([
            publicClient.readContract({
              address: CONFIG.vaultAddress!,
              abi: welotVaultAbi,
              functionName: "getUserPosition",
              args: [poolId, address],
            }),
            publicClient.readContract({
              address: CONFIG.usdeAddress!,
              abi: erc20Abi,
              functionName: "balanceOf",
              args: [address],
            }),
            publicClient.readContract({
              address: CONFIG.usdeAddress!,
              abi: erc20Abi,
              functionName: "allowance",
              args: [address, CONFIG.vaultAddress!],
            }),
          ]);

          setDeposits(pos[0]);
          setClaimable(pos[1]);
          setBalance(bal);
          setAllowance(allow);
        }
      }
    } catch (err) {
      console.error("Refresh error:", err);
    }
  }, [configOk, address]);

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
    let eth = (globalThis as { ethereum?: EIP1193Provider | any }).ethereum;
    if (!eth) {
      setError("Please install a wallet like MetaMask");
      return;
    }

    // If multiple injected providers exist (other extensions), prefer MetaMask if available
    try {
      if ((eth as any).providers && Array.isArray((eth as any).providers)) {
        const providers: any[] = (eth as any).providers;
        const mm = providers.find((p) => p.isMetaMask) || providers[0];
        eth = mm;
      }

      const accounts: string[] = await eth.request({ method: "eth_requestAccounts" });
      setAddress(accounts?.[0] as Address | undefined);
      setConnected(Boolean(accounts?.[0]));
      await refresh();
    } catch (err: any) {
      console.error("connectWallet error:", err);
      const msg = err?.message ?? String(err);
      setError(msg || "Failed to connect wallet");
    }
  }

  function disconnectWallet() {
    setConnected(false);
    setAddress(undefined);
    setDeposits(0n);
    setClaimable(0n);
    setBalance(0n);
    setAllowance(0n);
  }

  async function approve() {
    if (!connected || !address || !configOk) return;
    setLoading(true);
    setError("");

    try {
      const eth = (globalThis as { ethereum?: EIP1193Provider }).ethereum!;
      const walletClient = getWalletClient(eth);

      await walletClient.writeContract({
        address: CONFIG.usdeAddress!,
        abi: erc20Abi,
        functionName: "approve",
        args: [CONFIG.vaultAddress!, maxUint256],
        account: address,
      });

      setSuccess("Approved!");
      await refresh();
    } catch (err) {
      setError("Approval failed");
      console.error(err);
    } finally {
      setLoading(false);
    }
  }

  async function deposit() {
    if (!connected || !address || !configOk || !depositAmount) return;
    setLoading(true);
    setError("");

    try {
      const eth = (globalThis as { ethereum?: EIP1193Provider }).ethereum!;
      const walletClient = getWalletClient(eth);
      const amount = parseUnits(depositAmount, decimals);

      // Get first pool
      const publicClient = getPublicClient();
      const poolId = await publicClient.readContract({
        address: CONFIG.vaultAddress!,
        abi: welotVaultAbi,
        functionName: "podIds",
        args: [0n],
      });

      await walletClient.writeContract({
        address: CONFIG.vaultAddress!,
        abi: welotVaultAbi,
        functionName: "deposit",
        args: [amount, poolId],
        account: address,
      });

      setDepositAmount("");
      setSuccess("Deposit successful!");
      await refresh();
    } catch (err) {
      setError("Deposit failed");
      console.error(err);
    } finally {
      setLoading(false);
    }
  }

  async function withdraw() {
    if (!connected || !address || !configOk || !withdrawAmount) return;
    setLoading(true);
    setError("");

    try {
      const eth = (globalThis as { ethereum?: EIP1193Provider }).ethereum!;
      const walletClient = getWalletClient(eth);
      const amount = parseUnits(withdrawAmount, decimals);

      const publicClient = getPublicClient();
      const poolId = await publicClient.readContract({
        address: CONFIG.vaultAddress!,
        abi: welotVaultAbi,
        functionName: "podIds",
        args: [0n],
      });

      await walletClient.writeContract({
        address: CONFIG.vaultAddress!,
        abi: welotVaultAbi,
        functionName: "withdraw",
        args: [amount, poolId],
        account: address,
      });

      setWithdrawAmount("");
      setSuccess("Withdrawal successful!");
      await refresh();
    } catch (err) {
      setError("Withdrawal failed");
      console.error(err);
    } finally {
      setLoading(false);
    }
  }

  async function claim() {
    if (!connected || !address || !configOk) return;
    setLoading(true);
    setError("");

    try {
      const eth = (globalThis as { ethereum?: EIP1193Provider }).ethereum!;
      const walletClient = getWalletClient(eth);

      const publicClient = getPublicClient();
      const poolId = await publicClient.readContract({
        address: CONFIG.vaultAddress!,
        abi: welotVaultAbi,
        functionName: "podIds",
        args: [0n],
      });

      await walletClient.writeContract({
        address: CONFIG.vaultAddress!,
        abi: welotVaultAbi,
        functionName: "claimPrize",
        args: [poolId, address],
        account: address,
      });

      setSuccess("Prize claimed!");
      await refresh();
    } catch (err) {
      setError("Claim failed");
      console.error(err);
    } finally {
      setLoading(false);
    }
  }

  async function mintTestTokens() {
    if (!connected || !address || !faucetOk) return;
    setLoading(true);
    setError("");

    try {
      const eth = (globalThis as { ethereum?: EIP1193Provider }).ethereum!;
      const walletClient = getWalletClient(eth);

      await walletClient.writeContract({
        address: CONFIG.usdeAddress!,
        abi: mockErc20FaucetAbi,
        functionName: "mint",
        args: [address, parseUnits("1000", decimals)],
        account: address,
      });

      setSuccess("Minted 1000 test tokens!");
      await refresh();
    } catch (err) {
      setError("Mint failed");
      console.error(err);
    } finally {
      setLoading(false);
    }
  }

  async function simulateYield() {
    if (!connected || !address || !faucetOk) return;
    setLoading(true);
    setError("");

    try {
      const eth = (globalThis as { ethereum?: EIP1193Provider }).ethereum!;
      const walletClient = getWalletClient(eth);
      const amount = parseUnits("50", decimals);

      // Mint, approve, donate
      await walletClient.writeContract({
        address: CONFIG.usdeAddress!,
        abi: mockErc20FaucetAbi,
        functionName: "mint",
        args: [address, amount],
        account: address,
      });

      await walletClient.writeContract({
        address: CONFIG.usdeAddress!,
        abi: erc20Abi,
        functionName: "approve",
        args: [CONFIG.susdeAddress!, amount],
        account: address,
      });

      await walletClient.writeContract({
        address: CONFIG.susdeAddress!,
        abi: mockErc4626FaucetAbi,
        functionName: "donateYield",
        args: [amount],
        account: address,
      });

      setSuccess("Simulated 50 yield!");
      await refresh();
    } catch (err) {
      setError("Yield simulation failed");
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
        <div className="mb-6 flex items-center justify-between">
          <div>
            <a href="/" className="flex items-center">
              <div className="we-card rounded-2xl border-2 border-black bg-white p-2 shadow-[4px_4px_0_0_#000]">
                <Image src="/brand/logo.png" alt="welot" width={60} height={60} priority />
              </div>
            </a>
          </div>
          <div>
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

        {!configOk && (
          <div className="mb-6 rounded-2xl border-2 border-black bg-amber-100 px-4 py-3 text-sm font-black text-zinc-950 shadow-[4px_4px_0_0_#000]">
            Contract addresses not configured. Set NEXT_PUBLIC_WELOT_VAULT and NEXT_PUBLIC_USDE in .env.local
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
              <div className="text-sm font-black text-zinc-950">Current Prize Pool</div>
                  <div className="mt-2 text-5xl font-black text-zinc-950 font-pixel">${formatAmount(prizePool)}</div>
              <div className="mt-2 text-sm font-semibold text-zinc-800">
                {getEpochStatusText(epochStatus)}
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
            value={`$${formatAmount(deposits)}`}
            subtext="Your principal (always withdrawable)"
            color="emerald"
          />
          <StatCard
            icon="/icons/ticket.svg"
            label="Your Tickets"
            value={formatAmount(deposits)}
            subtext="1 ticket per $1 deposited"
            color="amber"
          />
          <StatCard
            icon="/icons/trophy.svg"
            label="Winnings"
            value={`$${formatAmount(claimable)}`}
            subtext={claimable > 0n ? "Ready to claim!" : "Win the next draw"}
            color="pink"
          />
        </div>

        {/* Actions */}
        <div className="mt-10 grid gap-6 lg:grid-cols-2">
          {/* Deposit */}
          <ActionCard title="Deposit" description="Add funds to get lottery tickets">
            <div className="space-y-4">
              <div>
                <div className="mb-2 flex items-center justify-between text-sm">
                  <span className="text-zinc-500">Amount</span>
                  <span className="text-zinc-600">
                    Balance: <span className="font-semibold">{formatAmount(balance)}</span>
                  </span>
                </div>
                <Input
                  value={depositAmount}
                  onChange={setDepositAmount}
                  placeholder="0.00"
                  suffix="USDE"
                />
              </div>
              <div className="flex gap-3">
                {needsApproval ? (
                  <Button onClick={approve} disabled={loading || !connected} fullWidth>
                    {loading ? "Approving..." : "Approve"}
                  </Button>
                ) : (
                  <Button onClick={deposit} disabled={loading || !connected || !depositAmount} fullWidth>
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
                    Deposited: <span className="font-semibold">{formatAmount(deposits)}</span>
                  </span>
                </div>
                <Input
                  value={withdrawAmount}
                  onChange={setWithdrawAmount}
                  placeholder="0.00"
                  suffix="USDE"
                />
              </div>
              <Button onClick={withdraw} disabled={loading || !connected || !withdrawAmount} fullWidth>
                {loading ? "Withdrawing..." : "Withdraw"}
              </Button>
            </div>
          </ActionCard>
        </div>

        {/* Claim Prize */}
        {claimable > 0n && (
          <div className="mt-6">
            <ActionCard title="🎉 You won!" description="Claim your prize winnings">
              <div className="flex items-center justify-between">
                <div className="text-2xl font-black text-pink-600">${formatAmount(claimable)}</div>
                <Button onClick={claim} disabled={loading}>
                  {loading ? "Claiming..." : "Claim Prize"}
                </Button>
              </div>
            </ActionCard>
          </div>
        )}

        {/* Test Controls (only for localhost) */}
        {faucetOk && (
          <div className="mt-10 rounded-3xl border-2 border-black bg-white p-6 shadow-[8px_8px_0_0_#000]">
            <div className="text-sm font-black text-zinc-950">Test Mode (localhost only)</div>
            <div className="mt-2 text-xs font-semibold text-zinc-700">
              These controls help you test the app locally.
            </div>
            <div className="mt-4 flex flex-wrap gap-3">
              <Button variant="secondary" onClick={mintTestTokens} disabled={loading || !connected}>
                Mint 1000 Test Tokens
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
                Each $1 deposited = 1 lottery ticket
              </li>
              <li className="flex gap-3">
                <span className="text-zinc-950">•</span>
                Weekly draws pick winners based on tickets
              </li>
              <li className="flex gap-3">
                <span className="text-zinc-950">•</span>
                Winners receive the entire yield prize pool
              </li>
              <li className="flex gap-3">
                <span className="text-zinc-950">•</span>
                Your deposits are never at risk
              </li>
            </ul>
          </div>
          <div className="we-card rounded-3xl border-2 border-black bg-white p-8 shadow-[6px_6px_0_0_#000]">
            <h3 className="font-display mag-underline text-3xl text-zinc-950">Pool Stats</h3>
            <div className="mt-4 space-y-3 text-sm font-semibold">
              <div className="flex items-center justify-between">
                <span className="text-zinc-800">Total Deposits</span>
                <span className="font-black text-zinc-950">${formatAmount(totalDeposits)}</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-zinc-800">Prize Pool</span>
                <span className="font-black text-zinc-950">${formatAmount(prizePool)}</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-zinc-800">Your Share</span>
                <span className="font-black text-zinc-950">
                  {totalDeposits > 0n
                    ? `${((Number(deposits) / Number(totalDeposits)) * 100).toFixed(2)}%`
                    : "0%"}
                </span>
              </div>
            </div>
          </div>
        </div>

        {/* Footer */}
        <footer className="mt-16 border-t-2 border-black pt-8 text-center text-xs font-semibold text-zinc-800">
          Icons: Twemoji (CC-BY 4.0) • Brand art: provided EPS assets
        </footer>
        </div>
      </main>
    </div>
  );
}
