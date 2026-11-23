import { validateConfigs } from "@breachpoint/shared/config";
import { Gateway } from "./gateway/gateway.ts";
import { MatchManager } from "./match/match-manager.ts";

const issues = validateConfigs();
if (issues.length > 0) {
  for (const i of issues) console.error(`config error ${i.file}: ${i.message}`);
  process.exit(1);
}

const port = Number(process.env["PORT"] ?? 7350);
const map = process.env["MAP"] ?? "solstice";
const fillBots = (process.env["FILL_BOTS"] ?? "1") !== "0";
const phaseScale = process.env["PHASE_SCALE"] ? Number(process.env["PHASE_SCALE"]) : undefined;
const started = performance.now();
let gateway: Gateway | null = null;
const manager = new MatchManager(
  { map, fillBots, maxPlayersPerMatch: 10, ...(phaseScale ? { phaseScale } : {}) },
  (id, bytes) => gateway?.deliver(id, bytes),
);
gateway = new Gateway({
  port,
  router: manager,
  serverTick: () => Math.floor(((performance.now() - started) / 1000) * 64),
});
await gateway.start();
console.log(
  JSON.stringify({ level: "info", msg: "gateway listening", port: gateway.port, map, fillBots }),
);

const shutdown = async (): Promise<void> => {
  await manager.stopAll();
  await gateway?.stop();
  process.exit(0);
};
process.on("SIGINT", () => void shutdown());
process.on("SIGTERM", () => void shutdown());
