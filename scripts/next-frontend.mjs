import { spawn } from "node:child_process";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.dirname(scriptDir);
const frontendDir = path.join(repoRoot, "frontend");
const nextBin = path.join(frontendDir, "node_modules", ".bin", "next");

const [command, ...restArgs] = process.argv.slice(2);
if (!command) {
  console.error("Usage: node scripts/next-frontend.mjs <dev|build|start> [...args]");
  process.exit(2);
}

const child = spawn(nextBin, [command, ".", ...restArgs], {
  cwd: frontendDir,
  stdio: "inherit",
  env: {
    ...process.env,
    INIT_CWD: frontendDir,
    PWD: frontendDir,
    npm_config_local_prefix: frontendDir,
  },
});

child.on("exit", (code, signal) => {
  if (signal) process.kill(process.pid, signal);
  process.exit(code ?? 1);
});
