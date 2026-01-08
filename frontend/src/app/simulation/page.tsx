"use client";

import Link from "next/link";
import { useEffect, useState, useCallback, useRef } from "react";
// Note: simulation-only page — no on-chain reads here

// ════════════════════════════════════════════════════════════════════════════
// TYPES & CONSTANTS
// ════════════════════════════════════════════════════════════════════════════

interface SimUser {
  id: string;
  name: string;
  avatar: string;
  deposits: Record<string, number>;
  claimable: Record<string, number>;
  poolId: number;
  isYou: boolean;
}

interface SimToken {
  symbol: string;
  name: string;
  icon: string;
  color: string;
  totalDeposits: number;
  prizePool: number;
  apy: number;
}

interface SimPool {
  id: number;
  deposits: Record<string, number>; // per-token deposits in this pool
  // Time-weighted cumulative balance used for pool winner weighting
  cumulativeWeight: number;
}

interface SimEpoch {
  id: number;
  start: Date;
  end: Date;
  status: "open" | "closed" | "randomnessRequested" | "randomnessReady" | "finalized";
  winner: SimUser | null;
  prize: number;
  winningToken: string | null;
  randomness: number | null;
}

interface LogEntry {
  id: string;
  time: Date;
  type: "deposit" | "withdraw" | "yield" | "draw" | "claim" | "system" | "winner";
  message: string;
  user?: string;
}

const RANDOM_NAMES = [
  "Alice", "Bob", "Charlie", "Diana", "Eve", "Frank", "Grace", "Henry",
  "Ivy", "Jack", "Kate", "Leo", "Mia", "Noah", "Olivia", "Peter",
  "Quinn", "Rose", "Sam", "Tina", "Uma", "Victor", "Wendy", "Xavier",
  "Yara", "Zach", "Luna", "Max", "Bella", "Oscar", "Ruby", "Felix"
];

const AVATARS = ["🦊", "🐼", "🦁", "🐯", "🐸", "🦉", "🐙", "🦋", "🐳", "🦄", "🐲", "🦚"];

const INITIAL_TOKENS: SimToken[] = [
  { symbol: "USDC", name: "USD Coin", icon: "💲", color: "bg-blue-100", totalDeposits: 0, prizePool: 0, apy: 12 },
  { symbol: "USDT", name: "Tether USD", icon: "💵", color: "bg-green-100", totalDeposits: 0, prizePool: 0, apy: 5 },
];

// ════════════════════════════════════════════════════════════════════════════
// HELPERS
// ════════════════════════════════════════════════════════════════════════════

function randomId(): string {
  return Math.random().toString(36).slice(2, 10);
}

function randomName(): string {
  return RANDOM_NAMES[Math.floor(Math.random() * RANDOM_NAMES.length)];
}

function randomAvatar(): string {
  return AVATARS[Math.floor(Math.random() * AVATARS.length)];
}

function formatNumber(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(2)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(2)}K`;
  return n.toFixed(2);
}

function formatMoney(n: number): string {
  if (!Number.isFinite(n)) return "0.00";
  const abs = Math.abs(n);
  if (abs === 0) return "0.00";
  if (abs < 0.01) return n.toFixed(6);
  if (abs < 1) return n.toFixed(4);
  return formatNumber(n);
}

function formatTime(date: Date): string {
  return date.toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit", second: "2-digit" });
}

function formatSimDateTimeUTC(date: Date): string {
  const pad2 = (n: number) => String(n).padStart(2, "0");
  return `${date.getUTCFullYear()}-${pad2(date.getUTCMonth() + 1)}-${pad2(date.getUTCDate())} ${pad2(date.getUTCHours())}:${pad2(date.getUTCMinutes())}:${pad2(date.getUTCSeconds())} UTC`;
}

function getNextFriday(from: Date): Date {
  const d = new Date(from);
  const day = d.getDay();
  const daysUntilFriday = (5 - day + 7) % 7 || 7;
  d.setDate(d.getDate() + daysUntilFriday);
  d.setHours(12, 0, 0, 0);
  return d;
}

// ════════════════════════════════════════════════════════════════════════════
// COMPONENTS
// ════════════════════════════════════════════════════════════════════════════

function Card({ title, children, color = "white", className = "" }: {
  title?: string;
  children: React.ReactNode;
  color?: "white" | "lime" | "amber" | "pink" | "blue" | "purple";
  className?: string;
}) {
  const bgMap = {
    white: "bg-white",
    lime: "bg-lime-200",
    amber: "bg-amber-100",
    pink: "bg-pink-100",
    blue: "bg-sky-100",
    purple: "bg-purple-100",
  };

  return (
    <div className={`rounded-2xl border-2 border-black ${bgMap[color]} p-4 shadow-[4px_4px_0_0_#000] ${className}`}>
      {title && <h3 className="text-lg font-black text-zinc-950 mb-3">{title}</h3>}
      {children}
    </div>
  );
}

function Button({ children, onClick, disabled, variant = "primary", size = "md" }: {
  children: React.ReactNode;
  onClick?: () => void;
  disabled?: boolean;
  variant?: "primary" | "secondary" | "danger" | "ghost";
  size?: "xs" | "sm" | "md";
}) {
  const base = `rounded-xl border-2 border-black font-black shadow-[3px_3px_0_0_#000] disabled:opacity-50 disabled:cursor-not-allowed transition-all hover:translate-x-[1px] hover:translate-y-[1px] hover:shadow-[2px_2px_0_0_#000] active:translate-x-[2px] active:translate-y-[2px] active:shadow-[1px_1px_0_0_#000]`;
  const sizes = { xs: "px-2 py-1 text-[10px]", sm: "px-3 py-1.5 text-xs", md: "px-4 py-2 text-sm" };
  const variants = {
    primary: "bg-zinc-950 text-zinc-50",
    secondary: "bg-lime-300 text-zinc-950",
    danger: "bg-red-400 text-white",
    ghost: "bg-white text-zinc-950",
  };

  return (
    <button onClick={onClick} disabled={disabled} className={`${base} ${sizes[size]} ${variants[variant]}`}>
      {children}
    </button>
  );
}

function UserRow({ user, tokens, onDeposit, onWithdraw, onClaim }: {
  user: SimUser;
  tokens: SimToken[];
  onDeposit: (userId: string, token: string, amount: number) => void;
  onWithdraw: (userId: string, token: string, amount: number) => void;
  onClaim: (userId: string, token: string) => void;
}) {
  const totalDeposits = Object.values(user.deposits).reduce((a, b) => a + b, 0);

  return (
    <div className={`rounded-xl border-2 border-black p-3 ${user.isYou ? "bg-lime-100" : "bg-white"} shadow-[2px_2px_0_0_#000]`}>
      <div className="flex items-center justify-between mb-2">
        <div className="flex items-center gap-2">
          <span className="text-2xl">{user.avatar}</span>
          <div>
            <div className="font-black text-sm">{user.name} {user.isYou && <span className="text-lime-600">(You)</span>}</div>
            <div className="text-[10px] text-zinc-500 font-mono">{user.id} • Pool #{user.poolId}</div>
          </div>
        </div>
        <div className="text-right">
          <div className="text-xs text-zinc-600">Total Deposited</div>
          <div className="font-black">${formatNumber(totalDeposits)}</div>
        </div>
      </div>
      
      <div className="grid grid-cols-3 gap-2 mt-2">
        {tokens.map((token) => {
          const deposited = user.deposits[token.symbol] || 0;
          const claimable = user.claimable[token.symbol] || 0;
          return (
            <div key={token.symbol} className={`rounded-lg ${token.color} p-2 text-xs`}>
              <div className="font-bold flex items-center gap-1">
                <span>{token.icon}</span> {token.symbol}
              </div>
              <div className="text-zinc-600">Deposited: ${formatNumber(deposited)}</div>
              {claimable > 0 && (
                <div className="text-green-600 font-bold">🎁 ${formatNumber(claimable)}</div>
              )}
              <div className="flex gap-1 mt-1">
                <Button size="xs" variant="ghost" onClick={() => onDeposit(user.id, token.symbol, 100)}>+100</Button>
                <Button size="xs" variant="ghost" onClick={() => onWithdraw(user.id, token.symbol, 50)} disabled={deposited < 50}>-50</Button>
                {claimable > 0 && (
                  <Button size="xs" variant="secondary" onClick={() => onClaim(user.id, token.symbol)}>Claim</Button>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function EpochStatus({ epoch, simTime }: { epoch: SimEpoch; simTime: Date }) {
  const timeLeft = Math.max(0, Math.floor((epoch.end.getTime() - simTime.getTime()) / 1000));
  const hours = Math.floor(timeLeft / 3600);
  const minutes = Math.floor((timeLeft % 3600) / 60);
  const seconds = timeLeft % 60;

  const statusColors = {
    open: "bg-green-400",
    closed: "bg-yellow-400",
    randomnessRequested: "bg-orange-400",
    randomnessReady: "bg-sky-400",
    finalized: "bg-blue-400",
  };

  const statusText = {
    open: "🟢 OPEN - Accepting Deposits",
    closed: "🟡 CLOSED - Ready to Request Randomness",
    randomnessRequested: "🟠 RANDOMNESS REQUESTED - Waiting for Callback...",
    randomnessReady: "🔵 RANDOMNESS READY - Finalize Draw",
    finalized: "✅ FINALIZED - Winner Selected!",
  };

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <div>
          <div className="text-sm text-zinc-600">Epoch #{epoch.id}</div>
          <div className={`inline-block rounded-lg px-3 py-1 text-sm font-black ${statusColors[epoch.status]} border border-black`}>
            {statusText[epoch.status]}
          </div>
        </div>
        {epoch.status === "open" && (
          <div className="text-right">
            <div className="text-xs text-zinc-600">Time Until Draw</div>
            <div className="text-2xl font-black font-mono">
              {String(hours).padStart(2, "0")}:{String(minutes).padStart(2, "0")}:{String(seconds).padStart(2, "0")}
            </div>
          </div>
        )}
      </div>

      {epoch.winner && (
        <div className="rounded-xl bg-gradient-to-r from-amber-200 to-yellow-200 border-2 border-black p-4 shadow-[3px_3px_0_0_#000]">
          <div className="text-center">
            <div className="text-4xl mb-2">🏆</div>
            <div className="text-sm text-zinc-600">Winner</div>
            <div className="text-xl font-black">{epoch.winner.avatar} {epoch.winner.name}</div>
            <div className="text-2xl font-black text-green-600">${formatNumber(epoch.prize)} {epoch.winningToken}</div>
          </div>
        </div>
      )}

      <div className="grid grid-cols-2 gap-2 text-xs">
        <div className="bg-zinc-100 rounded-lg p-2">
          <div className="text-zinc-600">Start</div>
          <div className="font-bold">{epoch.start.toLocaleString()}</div>
        </div>
        <div className="bg-zinc-100 rounded-lg p-2">
          <div className="text-zinc-600">End (Draw)</div>
          <div className="font-bold">{epoch.end.toLocaleString()}</div>
        </div>
      </div>
    </div>
  );
}

function ActivityLog({ logs }: { logs: LogEntry[] }) {
  const logRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (logRef.current) {
      logRef.current.scrollTop = 0;
    }
  }, [logs]);

  const typeColors = {
    deposit: "text-green-400",
    withdraw: "text-red-400",
    yield: "text-yellow-400",
    draw: "text-purple-400",
    claim: "text-cyan-400",
    system: "text-zinc-400",
    winner: "text-amber-300",
  };

  const typeIcons = {
    deposit: "📥",
    withdraw: "📤",
    yield: "📈",
    draw: "🎲",
    claim: "🎁",
    system: "⚙️",
    winner: "🏆",
  };

  return (
    <div ref={logRef} className="h-64 overflow-y-auto bg-zinc-900 rounded-xl p-3 font-mono text-xs space-y-1">
      {logs.length === 0 ? (
        <div className="text-zinc-500">Waiting for activity...</div>
      ) : (
        logs.map((log) => (
          <div key={log.id} className="flex gap-2">
            <span className="text-zinc-500">[{formatTime(log.time)}]</span>
            <span>{typeIcons[log.type]}</span>
            <span className={typeColors[log.type]}>{log.message}</span>
          </div>
        ))
      )}
    </div>
  );
}

// ════════════════════════════════════════════════════════════════════════════
// MAIN PAGE
// ════════════════════════════════════════════════════════════════════════════

export default function SimulationPage() {
  // Simulation state
  // Start with a deterministic placeholder time to avoid SSR/CSR mismatches.
  const [simTime, setSimTime] = useState(() => new Date(0));
  const [timeSpeed, setTimeSpeed] = useState(1); // 1 = real-time, 60 = 1 min/sec, 3600 = 1 hour/sec
  const [isRunning, setIsRunning] = useState(true);
  const [autoActions, setAutoActions] = useState(true);

  // Users - deterministic initial list to avoid hydration mismatch
  // Fixed pool size of 5 for the simulation protocol
  const POOL_COUNT = 5;

  const [users, setUsers] = useState<SimUser[]>(() =>
    Array.from({ length: 8 }, (_, i) => ({
      id: `user-${i}`,
      name: RANDOM_NAMES[i % RANDOM_NAMES.length],
      avatar: AVATARS[i % AVATARS.length],
      deposits: {},
      claimable: {},
      poolId: i % POOL_COUNT,
      isYou: i === 0,
    }))
  );

  // Pools: fixed-size array representing protocol pools
  const [pools, setPools] = useState<SimPool[]>(() =>
    Array.from({ length: POOL_COUNT }, (_, i) => ({ id: i, deposits: {}, cumulativeWeight: 0 }))
  );

  // Tokens & Epochs
  const [tokens, setTokens] = useState<SimToken[]>(INITIAL_TOKENS);
  
  // Epoch starts empty on the server; initialize on client mount to avoid mismatches
  const [epoch, setEpoch] = useState<SimEpoch | null>(null);
  const [epochHistory, setEpochHistory] = useState<SimEpoch[]>([]);

  // Logs start empty (will be populated on client mount)
  const [logs, setLogs] = useState<LogEntry[]>([]);

  // Guide state
  const [showGuide, setShowGuide] = useState(true);

  const addLog = useCallback((type: LogEntry["type"], message: string, user?: string) => {
    setLogs((prev) => [
      { id: randomId(), time: new Date(), type, message, user },
      ...prev.slice(0, 99),
    ]);
  }, []);

  // Track mount state with ref (doesn't trigger re-render)
  const hasMounted = useRef(false);

  // Populate dynamic values on client mount only (avoids SSR/CSR differences)
  useEffect(() => {
    if (hasMounted.current) return;
    hasMounted.current = true;
    
    const now = new Date();
    const nextDraw = getNextFriday(now);
    
    // Defer state updates slightly to avoid setState-in-effect lint rule
    setTimeout(() => {
      setSimTime(now);
      setEpoch({
        id: 1,
        start: now,
        end: nextDraw,
        status: "open",
        winner: null,
        prize: 0,
        winningToken: null,
        randomness: null,
      });
      setLogs([
        { id: randomId(), time: now, type: "system", message: "🎮 Simulation started! This is a web2 demo - no real transactions." },
        { id: randomId(), time: now, type: "system", message: `Next draw scheduled for ${nextDraw.toLocaleString()}` },
      ]);
    }, 0);
  }, []);

  // Accrue yield helper (seconds is number of elapsed seconds)
  // Protocol model: yield accrues globally per token; the draw allocates that prize to a winning pool.
  const accrueYield = useCallback((seconds: number) => {
    if (seconds <= 0) return;
    setTokens((prev) =>
      prev.map((token) => {
        if (token.totalDeposits === 0) return token;
        const yieldGenerated = (token.totalDeposits * (token.apy / 100) * seconds) / 31536000;
        return { ...token, prizePool: token.prizePool + yieldGenerated };
      })
    );
  }, []);

  // Time-weighted pool weighting (approx): integrate pool total deposits over time
  const accruePoolWeights = useCallback((seconds: number) => {
    if (seconds <= 0) return;
    setPools((prev) =>
      prev.map((p) => {
        const balance = Object.values(p.deposits).reduce((a, b) => a + b, 0);
        return { ...p, cumulativeWeight: p.cumulativeWeight + balance * seconds };
      })
    );
  }, []);

  // Time simulation tick
  useEffect(() => {
    if (!isRunning) return;

    const interval = setInterval(() => {
      // Advance simulated time
      setSimTime((prev) => new Date(prev.getTime() + timeSpeed * 1000));
      // Accrue yield according to the advanced time (timeSpeed seconds)
      accrueYield(timeSpeed);
      // Accrue pool weights for pool winner selection
      accruePoolWeights(timeSpeed);
    }, 1000);

    return () => clearInterval(interval);
  }, [isRunning, timeSpeed, accrueYield, accruePoolWeights]);

  // Random bot actions
  useEffect(() => {
    if (!isRunning || !autoActions) return;

    const interval = setInterval(() => {
      setUsers((prevUsers) => {
        if (prevUsers.length < 2) return prevUsers;

        // Random action by random non-you user
        const botUsers = prevUsers.filter((u) => !u.isYou);
        if (botUsers.length === 0) return prevUsers;

        const botUser = botUsers[Math.floor(Math.random() * botUsers.length)];
        const token = tokens[Math.floor(Math.random() * tokens.length)];
        const action = Math.random();

        if (action < 0.7) {
          // 70% chance: deposit
          const amount = Math.floor(Math.random() * 500) + 50;
          addLog("deposit", `${botUser.name} deposited $${amount} ${token.symbol}`, botUser.id);
          
          setTokens((t) => t.map((tk) => (tk.symbol === token.symbol ? { ...tk, totalDeposits: tk.totalDeposits + amount } : tk)));

          // update pool totals
          setPools((prev) =>
            prev.map((p) =>
              p.id === botUser.poolId
                ? { ...p, deposits: { ...p.deposits, [token.symbol]: (p.deposits[token.symbol] || 0) + amount } }
                : p
            )
          );

          return prevUsers.map((u) =>
            u.id === botUser.id
              ? { ...u, deposits: { ...u.deposits, [token.symbol]: (u.deposits[token.symbol] || 0) + amount } }
              : u
          );
        } else if (action < 0.9) {
          // 20% chance: withdraw
          const deposited = botUser.deposits[token.symbol] || 0;
          if (deposited < 10) return prevUsers;
          const amount = Math.min(deposited, Math.floor(Math.random() * 200) + 10);
          addLog("withdraw", `${botUser.name} withdrew $${amount} ${token.symbol}`, botUser.id);
          
          setTokens((t) => t.map((tk) => (tk.symbol === token.symbol ? { ...tk, totalDeposits: Math.max(0, tk.totalDeposits - amount) } : tk)));

          // reduce from pool totals
          setPools((prev) =>
            prev.map((p) =>
              p.id === botUser.poolId
                ? { ...p, deposits: { ...p.deposits, [token.symbol]: Math.max(0, (p.deposits[token.symbol] || 0) - amount) } }
                : p
            )
          );

          return prevUsers.map((u) =>
            u.id === botUser.id
              ? { ...u, deposits: { ...u.deposits, [token.symbol]: deposited - amount } }
              : u
          );
        }

        return prevUsers;
      });
    }, 3000 / Math.max(1, Math.sqrt(timeSpeed))); // Faster actions when time is sped up

    return () => clearInterval(interval);
  }, [isRunning, autoActions, timeSpeed, tokens, addLog]);

  // Draw functions using refs to avoid circular dependency
  const closeEpochRef = useRef<() => void>(() => {});
  const requestRandomnessRef = useRef<() => void>(() => {});
  const finalizeDrawRef = useRef<() => void>(() => {});
  const startNewEpochRef = useRef<() => void>(() => {});

  // Keep refs updated with latest state (must be in useEffect, not render)
  useEffect(() => {
    closeEpochRef.current = () => {
      if (!epoch) return;
      if (epoch.status !== "open") return;

      addLog("draw", "Epoch closed. Keeper step: closeEpoch()");
      setEpoch((e) => (e ? { ...e, status: "closed" } : null));
    };

    requestRandomnessRef.current = () => {
      if (!epoch) return;
      if (epoch.status !== "closed") return;

      addLog("draw", "Keeper step: requestRandomness() via Pyth Entropy 🎲");
      setEpoch((e) => (e ? { ...e, status: "randomnessRequested" } : null));

      // Simulate async entropy callback
      setTimeout(() => {
        const r = Math.random();
        addLog("draw", "Entropy callback received ✅");
        setEpoch((e) => (e ? { ...e, status: "randomnessReady", randomness: r } : null));
      }, 1200);
    };

    finalizeDrawRef.current = () => {
      if (!epoch) return;
      if (epoch.status !== "randomnessReady") return;

      // Finalize draw: select winning pool + allocate prizes
      setTimeout(() => {
        // Select winning pool (protocol selects a pool, not a single user)
        const eligiblePools = pools
          .map((p) => ({
            pool: p,
            totalDeposits: Object.values(p.deposits).reduce((a, b) => a + b, 0),
          }))
          .filter((p) => p.totalDeposits > 0);

        if (eligiblePools.length === 0) {
          addLog("system", "No eligible deposits in any pool. Starting new epoch.");
          startNewEpochRef.current();
          return;
        }

        // Weight pools by time-weighted cumulative weight; fall back to current balance if all weights are 0
        const totalCumulative = eligiblePools.reduce((a, b) => a + (b.pool.cumulativeWeight || 0), 0);
        const totalWeight = totalCumulative > 0
          ? totalCumulative
          : eligiblePools.reduce((a, b) => a + b.totalDeposits, 0);

        // Use epoch randomness if available; fallback to Math.random
        const rand01 = epoch.randomness ?? Math.random();
        let random = rand01 * totalWeight;
        let winningPoolId = eligiblePools[0].pool.id;
        for (const p of eligiblePools) {
          const w = totalCumulative > 0 ? (p.pool.cumulativeWeight || 0) : p.totalDeposits;
          random -= w;
          if (random <= 0) {
            winningPoolId = p.pool.id;
            break;
          }
        }

        // Allocate prizes: for each token, allocate the *global* prize pool to depositors of that token inside the winning pool.
        const winningPool = pools.find((p) => p.id === winningPoolId);

        const allocatableByToken = new Map<string, { prize: number; poolTokenDeposits: number }>();
        for (const t of tokens) {
          const poolTokenDeposits = winningPool?.deposits[t.symbol] || 0;
          if (t.prizePool > 0 && poolTokenDeposits > 0) {
            allocatableByToken.set(t.symbol, { prize: t.prizePool, poolTokenDeposits });
          }
        }

        let totalPrizeAllocated = 0;
        let winningToken: string | null = null;
        let maxTokenPrize = 0;
        for (const [symbol, a] of allocatableByToken.entries()) {
          totalPrizeAllocated += a.prize;
          if (a.prize > maxTokenPrize) {
            maxTokenPrize = a.prize;
            winningToken = symbol;
          }
        }

        // Update users claimable amounts (pro-rata within winning pool, per token)
        if (allocatableByToken.size > 0) {
          setUsers((prev) =>
            prev.map((u) => {
              if (u.poolId !== winningPoolId) return u;
              const newClaimable = { ...u.claimable };
              for (const [symbol, a] of allocatableByToken.entries()) {
                const userDep = u.deposits[symbol] || 0;
                if (userDep <= 0) continue;
                const share = a.prize * (userDep / a.poolTokenDeposits);
                newClaimable[symbol] = (newClaimable[symbol] || 0) + share;
              }
              return { ...u, claimable: newClaimable };
            })
          );
        }

        // Reduce token prize pools only for tokens that were allocatable in the winning pool
        if (allocatableByToken.size > 0) {
          setTokens((prev) =>
            prev.map((t) => (allocatableByToken.has(t.symbol) ? { ...t, prizePool: 0 } : t))
          );
        }

        addLog(
          "winner",
          allocatableByToken.size === 0
            ? `🏆 Pool #${winningPoolId} won, but had no deposits in prize-bearing tokens — prizes carry forward.`
            : `🏆 Pool #${winningPoolId} won $${formatNumber(totalPrizeAllocated)} in prizes!`
        );

        // Update epoch (store pool as a pseudo-winner for display)
        const poolWinner: SimUser = {
          id: `pool-${winningPoolId}`,
          name: `Pool #${winningPoolId}`,
          avatar: "🏊",
          deposits: {},
          claimable: {},
          poolId: winningPoolId,
          isYou: false,
        };

        setEpoch((e) =>
          e
            ? {
                ...e,
                status: "finalized",
                winner: poolWinner,
                prize: totalPrizeAllocated,
                winningToken,
              }
            : null
        );

        // Start new epoch after delay
        setTimeout(() => {
          startNewEpochRef.current();
        }, 5000);
      }, 250);
    };

    startNewEpochRef.current = () => {
      if (epoch) {
        setEpochHistory((prev) => [epoch, ...prev.slice(0, 9)]);
      }

      // Reset time-weighted pool weights for the new epoch (protocol weights are epoch-scoped)
      setPools((prev) => prev.map((p) => ({ ...p, cumulativeWeight: 0 })));

      const nextDraw = getNextFriday(simTime);
      const newEpoch: SimEpoch = {
        id: (epoch?.id || 0) + 1,
        start: simTime,
        end: nextDraw,
        status: "open",
        winner: null,
        prize: 0,
        winningToken: null,
        randomness: null,
      };

      setEpoch(newEpoch);
      addLog("system", `New epoch #${newEpoch.id} started! Draw at ${nextDraw.toLocaleString()}`);
    };
  }, [epoch, users, tokens, pools, simTime, addLog]);

  // Check for draw time
  useEffect(() => {
    if (!epoch || epoch.status !== "open") return;

    if (simTime >= epoch.end) {
      closeEpochRef.current();
      // Auto-advance keeper steps for the simulation
      setTimeout(() => requestRandomnessRef.current(), 300);
      setTimeout(() => finalizeDrawRef.current(), 2000);
    }
  }, [simTime, epoch]);

  // Simulation-only: leaderboard and past winners are derived from in-memory pools/epochHistory

  // Actions
  const handleDeposit = (userId: string, tokenSymbol: string, amount: number) => {
    const user = users.find((u) => u.id === userId);
    if (!user) return;

    setUsers((prev) =>
      prev.map((u) =>
        u.id === userId
          ? { ...u, deposits: { ...u.deposits, [tokenSymbol]: (u.deposits[tokenSymbol] || 0) + amount } }
          : u
      )
    );

    setTokens((prev) =>
      prev.map((t) => (t.symbol === tokenSymbol ? { ...t, totalDeposits: t.totalDeposits + amount } : t))
    );

    // update pool totals for this user's assigned pool
    setPools((prev) =>
      prev.map((p) =>
        p.id === user.poolId ? { ...p, deposits: { ...p.deposits, [tokenSymbol]: (p.deposits[tokenSymbol] || 0) + amount } } : p
      )
    );

    addLog("deposit", `${user.name} deposited $${amount} ${tokenSymbol}`, userId);
  };

  const handleWithdraw = (userId: string, tokenSymbol: string, amount: number) => {
    const user = users.find((u) => u.id === userId);
    if (!user) return;

    const current = user.deposits[tokenSymbol] || 0;
    if (current < amount) return;

    setUsers((prev) =>
      prev.map((u) =>
        u.id === userId
          ? { ...u, deposits: { ...u.deposits, [tokenSymbol]: current - amount } }
          : u
      )
    );

    setTokens((prev) =>
      prev.map((t) => (t.symbol === tokenSymbol ? { ...t, totalDeposits: Math.max(0, t.totalDeposits - amount) } : t))
    );

    // reduce pool totals for user's pool
    setPools((prev) =>
      prev.map((p) =>
        p.id === user.poolId ? { ...p, deposits: { ...p.deposits, [tokenSymbol]: Math.max(0, (p.deposits[tokenSymbol] || 0) - amount) } } : p
      )
    );

    addLog("withdraw", `${user.name} withdrew $${amount} ${tokenSymbol}`, userId);
  };

  const handleClaim = (userId: string, tokenSymbol: string) => {
    const user = users.find((u) => u.id === userId);
    if (!user) return;

    const claimable = user.claimable[tokenSymbol] || 0;
    if (claimable === 0) return;

    setUsers((prev) =>
      prev.map((u) => (u.id === userId ? { ...u, claimable: { ...u.claimable, [tokenSymbol]: 0 } } : u))
    );

    addLog("claim", `${user.name} claimed $${formatNumber(claimable)} ${tokenSymbol} prize! 🎉`, userId);
  };

  const addRandomUser = () => {
    const newUser: SimUser = {
      id: randomId(),
      name: randomName(),
      avatar: randomAvatar(),
      deposits: {},
      claimable: {},
      poolId: users.length % POOL_COUNT,
      isYou: false,
    };
    setUsers((prev) => [...prev, newUser]);
    addLog("system", `${newUser.avatar} ${newUser.name} joined the lottery!`);
  };

  const warpTime = (seconds: number) => {
    // Compute new time from current simTime to ensure we can synchronously check epoch boundaries
    const newTime = new Date(simTime.getTime() + seconds * 1000);
    setSimTime(newTime);

    // Accrue yield for the jumped period
    accrueYield(seconds);
    // Accrue pool weights for the jumped period
    accruePoolWeights(seconds);

    addLog("system", `⏩ Time warped forward ${seconds >= 3600 ? `${seconds / 3600}h` : seconds >= 60 ? `${seconds / 60}m` : `${seconds}s`}`);

    // If we've moved past the epoch end, trigger the draw immediately
    if (epoch && epoch.status === "open" && newTime >= epoch.end) {
      // small timeout to allow state updates to flush
      setTimeout(() => {
        closeEpochRef.current();
        setTimeout(() => requestRandomnessRef.current(), 300);
        setTimeout(() => finalizeDrawRef.current(), 2000);
      }, 50);
    }
  };

  const triggerManualDraw = () => {
    if (!epoch) return;
    // Manual keeper step: advance one stage in the lifecycle
    if (epoch.status === "open") {
      addLog("system", "Manual keeper: closeEpoch()");
      closeEpochRef.current();
      return;
    }
    if (epoch.status === "closed") {
      addLog("system", "Manual keeper: requestRandomness()");
      requestRandomnessRef.current();
      return;
    }
    if (epoch.status === "randomnessReady") {
      addLog("system", "Manual keeper: finalizeDraw()");
      finalizeDrawRef.current();
      return;
    }
  };

  const totalPrizePool = tokens.reduce((a, b) => a + b.prizePool, 0);
  const totalDeposits = tokens.reduce((a, b) => a + b.totalDeposits, 0);

  return (
    <div className="min-h-dvh bg-gradient-to-br from-amber-50 via-white to-lime-50 text-zinc-950">
      <main className="mx-auto w-full max-w-7xl px-4 py-6">
        {/* Header */}
        <div className="mb-6 flex items-center justify-between flex-wrap gap-4">
          <div className="flex items-center gap-4">
            <Link href="/app" className="rounded-xl border-2 border-black bg-white px-4 py-2 text-sm font-black shadow-[3px_3px_0_0_#000] hover:bg-zinc-100">
              ← Back to App
            </Link>
            <h1 className="text-2xl font-black">🎮 Lottery Simulator</h1>
            <span className="rounded-lg bg-purple-200 border border-purple-400 px-2 py-1 text-xs font-bold animate-pulse">
              Web2 Demo
            </span>
          </div>
          <div className="flex items-center gap-2">
            <Button variant={showGuide ? "secondary" : "ghost"} size="sm" onClick={() => setShowGuide(!showGuide)}>
              {showGuide ? "Hide" : "Show"} Guide
            </Button>
          </div>
        </div>

        {/* Guide */}
        {showGuide && (
          <Card color="blue" className="mb-6">
            <div className="flex items-start gap-4">
              <div className="text-4xl">📚</div>
              <div className="flex-1">
                <h3 className="font-black text-lg mb-2">How This Simulation Works</h3>
                <div className="grid md:grid-cols-3 gap-4 text-sm">
                  <div>
                    <div className="font-bold mb-1">🎯 The Lottery</div>
                    <p className="text-zinc-600">Users deposit tokens → deposits go into their assigned pool → yield accrues globally → a winning pool is selected and prizes are distributed pro-rata inside that pool.</p>
                  </div>
                  <div>
                    <div className="font-bold mb-1">⏱️ Time Controls</div>
                    <p className="text-zinc-600">Speed up time to see yield accumulate. Warp to Friday noon to trigger the draw instantly.</p>
                  </div>
                  <div>
                    <div className="font-bold mb-1">🤖 Bot Users</div>
                    <p className="text-zinc-600">Other users automatically deposit/withdraw. More deposits = higher chance of winning!</p>
                  </div>
                </div>
              </div>
              <button onClick={() => setShowGuide(false)} className="text-zinc-400 hover:text-zinc-600">✕</button>
            </div>
          </Card>
        )}

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* LEFT: Users & Tokens */}
          <div className="lg:col-span-2 space-y-4">
            {/* Prize Pool Banner */}
            <Card color="lime">
              <div className="flex items-center justify-between flex-wrap gap-4">
                <div>
                  <div className="text-sm font-bold text-zinc-600">💰 Total Prize Pool</div>
                  <div className="text-4xl font-black">${formatMoney(totalPrizePool)}</div>
                  <div className="text-xs text-zinc-500">From ${formatNumber(totalDeposits)} total deposits</div>
                </div>
                <div className="flex gap-2">
                  {tokens.map((token) => (
                    <div key={token.symbol} className={`rounded-xl ${token.color} border border-black px-3 py-2 text-center`}>
                      <div className="text-lg">{token.icon}</div>
                      <div className="text-xs font-bold">{token.symbol}</div>
                      <div className="text-xs text-green-600">${formatMoney(token.prizePool)}</div>
                      <div className="text-[10px] text-zinc-500">{token.apy}% APY</div>
                    </div>
                  ))}
                </div>
              </div>
            </Card>

            {/* Users List */}
            <Card title={`👥 Participants (${users.length})`}>
              <div className="space-y-3 max-h-[400px] overflow-y-auto">
                {users.map((user) => (
                  <UserRow
                    key={user.id}
                    user={user}
                    tokens={tokens}
                    onDeposit={handleDeposit}
                    onWithdraw={handleWithdraw}
                    onClaim={handleClaim}
                  />
                ))}
              </div>
              <div className="mt-3 pt-3 border-t border-zinc-200">
                <Button variant="ghost" size="sm" onClick={addRandomUser}>
                  ➕ Add Random User
                </Button>
              </div>
            </Card>

            {/* Activity Log */}
            <Card title="📜 Activity Log">
              <ActivityLog logs={logs} />
            </Card>
          </div>

          {/* RIGHT: Controls & Epoch */}
          <div className="space-y-4">
            {/* Time Controls */}
            <Card title="⏱️ Time Controls" color="amber">
              <div className="space-y-4">
                <div className="flex items-center justify-between">
                  <div className="text-sm text-zinc-600">Simulation Time</div>
                  <div className="font-mono font-bold">{formatSimDateTimeUTC(simTime)}</div>
                </div>

                <div className="flex items-center gap-2">
                  <Button variant={isRunning ? "danger" : "secondary"} size="sm" onClick={() => setIsRunning(!isRunning)}>
                    {isRunning ? "⏸ Pause" : "▶ Play"}
                  </Button>
                  <select
                    value={timeSpeed}
                    onChange={(e) => setTimeSpeed(Number(e.target.value))}
                    className="rounded-lg border-2 border-black px-2 py-1 text-sm font-bold"
                  >
                    <option value={1}>1× (Real-time)</option>
                    <option value={60}>60× (1 min/sec)</option>
                    <option value={3600}>3600× (1 hr/sec)</option>
                    <option value={86400}>86400× (1 day/sec)</option>
                  </select>
                </div>

                <div className="flex flex-wrap gap-2">
                  <Button variant="ghost" size="sm" onClick={() => warpTime(3600)}>+1 Hour</Button>
                  <Button variant="ghost" size="sm" onClick={() => warpTime(86400)}>+1 Day</Button>
                  <Button variant="secondary" size="sm" onClick={() => {
                    const fridayNoon = getNextFriday(simTime);
                    const diff = Math.ceil((fridayNoon.getTime() - simTime.getTime()) / 1000);
                    warpTime(diff + 1);
                  }}>
                    🚀 Warp to Friday Noon
                  </Button>
                </div>
              </div>
            </Card>

            {/* Current Epoch */}
            <Card title="🎲 Current Epoch" color="purple">
              {epoch ? (
                <EpochStatus epoch={epoch} simTime={simTime} />
              ) : (
                <div className="text-zinc-500">Loading...</div>
              )}
              <div className="mt-4 pt-4 border-t border-black/10">
                <Button 
                  variant="primary" 
                  size="sm" 
                  onClick={triggerManualDraw}
                  disabled={!(epoch?.status === "open" || epoch?.status === "closed" || epoch?.status === "randomnessReady")}
                >
                  🎰 Run Keeper Step
                </Button>
              </div>
            </Card>

            {/* Bot Controls */}
            <Card title="🤖 Bot Settings">
              <div className="space-y-3">
                <label className="flex items-center gap-2">
                  <input
                    type="checkbox"
                    checked={autoActions}
                    onChange={(e) => setAutoActions(e.target.checked)}
                    className="w-4 h-4"
                  />
                  <span className="text-sm font-bold">Auto bot deposits/withdrawals</span>
                </label>
                <div className="text-xs text-zinc-500">
                  When enabled, bot users will randomly deposit and withdraw tokens to simulate real activity.
                </div>
              </div>
            </Card>

            {/* Leaderboard (simulated pools) */}
            <Card title="🏆 Leaderboard (simulated)">
              {pools.length === 0 ? (
                <div className="text-zinc-500 text-sm">No pools available</div>
              ) : (
                <div className="space-y-2 text-sm">
                  {pools
                    .map((p) => ({
                      id: p.id,
                      total: Object.values(p.deposits).reduce((a, b) => a + b, 0),
                    }))
                    .sort((a, b) => b.total - a.total)
                    .slice(0, 5)
                    .map((p) => (
                      <div key={p.id} className="flex justify-between items-center">
                        <div>
                          <div className="font-bold">Pool #{p.id}</div>
                        </div>
                        <div className="text-right">
                          <div className="font-black text-sm">${formatNumber(p.total)}</div>
                        </div>
                      </div>
                    ))}
                </div>
              )}
            </Card>

            {/* Past winners (simulated from epoch history) */}
            <Card title="📜 Past Winners (simulated)">
              {epochHistory.filter((e) => e.winner).length === 0 ? (
                <div className="text-zinc-500 text-sm">No winners yet in this simulation</div>
              ) : (
                <div className="space-y-2 max-h-48 overflow-y-auto text-sm">
                  {epochHistory
                    .filter((e) => e.winner)
                    .slice(0, 10)
                    .map((e) => (
                      <div key={e.id} className="rounded-lg bg-zinc-100 p-2">
                        <div className="flex justify-between">
                          <div className="font-bold">Epoch #{e.id}</div>
                          <div className="text-green-600 font-black">${formatNumber(e.prize)}</div>
                        </div>
                        <div className="text-zinc-600 text-xs">Winner: {e.winner?.avatar} {e.winner?.name} (Pool #{e.winner?.poolId})</div>
                      </div>
                    ))}
                </div>
              )}
            </Card>

            {/* Epoch History */}
            {epochHistory.length > 0 && (
              <Card title="📊 Past Epochs">
                <div className="space-y-2 max-h-48 overflow-y-auto">
                  {epochHistory.map((e) => (
                    <div key={e.id} className="rounded-lg bg-zinc-100 p-2 text-xs">
                      <div className="flex justify-between">
                        <span className="font-bold">Epoch #{e.id}</span>
                        {e.winner && <span className="text-green-600">${formatNumber(e.prize)}</span>}
                      </div>
                      {e.winner && (
                        <div className="text-zinc-600">
                          Winner: {e.winner.avatar} {e.winner.name}
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              </Card>
            )}

            {/* Stats */}
            <Card title="📈 Stats">
              <div className="space-y-2 text-sm">
                <div className="flex justify-between">
                  <span className="text-zinc-600">Total Users</span>
                  <span className="font-bold">{users.length}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-zinc-600">Active Depositors</span>
                  <span className="font-bold">{users.filter((u) => Object.values(u.deposits).some((d) => d > 0)).length}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-zinc-600">Total Deposits</span>
                  <span className="font-bold">${formatNumber(totalDeposits)}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-zinc-600">Prize Pool</span>
                  <span className="font-bold text-green-600">${formatMoney(totalPrizePool)}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-zinc-600">Epochs Completed</span>
                  <span className="font-bold">{epochHistory.length}</span>
                </div>
              </div>
            </Card>
          </div>
        </div>
      </main>
    </div>
  );
}
