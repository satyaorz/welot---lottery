export function requiredEnv(name: string): string {
  const v = optionalEnv(name);
  if (!v) {
    throw new Error(`Missing env var: ${name}`);
  }
  return v;
}

// IMPORTANT (Next.js): client bundles only inline env vars when referenced as
// `process.env.NEXT_PUBLIC_*` (static property access). Bracket access like
// `process.env[name]` will not be inlined, and will be undefined in the browser.
//
// Keep this list in sync with the env vars the app uses.
const NEXT_PUBLIC_ENV: Record<string, string | undefined> = {
  NEXT_PUBLIC_RPC_URL: process.env.NEXT_PUBLIC_RPC_URL,
  NEXT_PUBLIC_CHAIN_ID: process.env.NEXT_PUBLIC_CHAIN_ID,

  NEXT_PUBLIC_WELOT_VAULT: process.env.NEXT_PUBLIC_WELOT_VAULT,
  NEXT_PUBLIC_ENTROPY: process.env.NEXT_PUBLIC_ENTROPY,
  NEXT_PUBLIC_FAUCET: process.env.NEXT_PUBLIC_FAUCET,
  NEXT_PUBLIC_USDE_FAUCET: process.env.NEXT_PUBLIC_USDE_FAUCET,

  NEXT_PUBLIC_USDE: process.env.NEXT_PUBLIC_USDE,
  NEXT_PUBLIC_SUSDE: process.env.NEXT_PUBLIC_SUSDE,
  NEXT_PUBLIC_USDC: process.env.NEXT_PUBLIC_USDC,
  NEXT_PUBLIC_SUSDC: process.env.NEXT_PUBLIC_SUSDC,
  NEXT_PUBLIC_METH: process.env.NEXT_PUBLIC_METH,
  NEXT_PUBLIC_SMETH: process.env.NEXT_PUBLIC_SMETH,
};

export function optionalEnv(name: string): string | undefined {
  // Prefer build-time injected env vars.
  const v = NEXT_PUBLIC_ENV[name];
  if (v) return v;

  // If running on the server and Next didn't load .env.local for some reason,
  // try to read it directly from the frontend folder. This helps local dev
  // when the server was started before the file was created.
  if (typeof window === "undefined") {
    try {
      // Use dynamic require via eval to avoid bundlers statically resolving
      // the `fs` module for client bundles.
      const req = eval("require") as (id: string) => unknown;
      const fs = req("fs") as {
        existsSync: (p: string) => boolean;
        readFileSync: (p: string, enc: "utf8") => string;
      };
      const path = req("path") as {
        resolve: (...segments: string[]) => string;
      };
      const p = path.resolve(process.cwd(), ".env.local");
      if (fs.existsSync(p)) {
        const content = fs.readFileSync(p, "utf8");
        for (const line of content.split(/\r?\n/)) {
          const m = line.match(/^\s*([^#=\s]+)\s*=\s*(.*)\s*$/);
          if (!m) continue;
          const key = m[1];
          let val = m[2] || "";
          // strip optional quotes
          if (val.startsWith('"') && val.endsWith('"')) val = val.slice(1, -1);
          if (key === name) return val;
        }
      }
    } catch {
      // ignore and fallthrough
    }
  }

  return undefined;
}
