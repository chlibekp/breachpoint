import { validateConfigs } from "@breachpoint/shared/config";
import { Gateway } from "./gateway/gateway.ts";
import { Match } from "./match/match.ts";

const issues = validateConfigs();
if (issues.length > 0) {
  for (const i of issues) console.error(`config error ${i.file}: ${i.message}`);
  process.exit(1);
}

const port = Number(process.env["PORT"] ?? 7350);
// Milestone 1: a single in-process lobby match so Pong carries a live 64 Hz server tick.
const lobby = new Match({ matchId: "lobby", map: "range", seed: 1 });
lobby.start();
const gateway = new Gateway({ port, serverTick: () => lobby.tick });
await gateway.start();
console.log(JSON.stringify({ level: "info", msg: "gateway listening", port: gateway.port }));

const shutdown = async (): Promise<void> => {
  lobby.stop();
  await gateway.stop();
  process.exit(0);
};
process.on("SIGINT", () => void shutdown());
process.on("SIGTERM", () => void shutdown());
