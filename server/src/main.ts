// BREACHPOINT server entry: WebSocket gateway + match workers, and (when DATABASE_URL and
// REDIS_URL are set) the HTTP API with auth, parties, matchmaking, agent select and stats.
// In production these can run as separate processes (docker-compose services); locally one is enough.
import { loadRawConfig, validateConfigs } from "@breachpoint/shared/config";
import { Redis } from "ioredis";
import { Gateway } from "./gateway/gateway.ts";
import { MatchManager } from "./match/match-manager.ts";
import { pruneReplays } from "./match/replay.ts";
import { metrics } from "./services/metrics.ts";
import { buildApi } from "./services/api.ts";
import { AuthService } from "./services/auth.ts";
import { connect, migrate } from "./services/db.ts";
import { SocialService } from "./services/social.ts";
import { StatsService, type MatchResult } from "./services/stats.ts";
import { OAuthService, providersFromEnv } from "./services/oauth.ts";

const issues = validateConfigs();
if (issues.length > 0) {
  for (const i of issues) console.error(`config error ${i.file}: ${i.message}`);
  process.exit(1);
}

const env = (k: string, d = ""): string => process.env[k] ?? d;
const port = Number(env("PORT", "7350"));
const apiPort = Number(env("API_PORT", "7351"));
const metricsPort = Number(env("METRICS_PORT", "9464"));
// MAP: comma-separated rotation; the first map hosts anonymous quick-join matches.
const maps = env("MAP", "solstice,neon")
  .split(",")
  .map((m) => m.trim())
  .filter(Boolean);
const map = maps[0] ?? "solstice";
const fillBots = env("FILL_BOTS", "1") !== "0";
const phaseScale = env("PHASE_SCALE") ? Number(env("PHASE_SCALE")) : undefined;
const secret = env("JWT_SECRET", "dev-only-secret-change-me");
const ticketSecret = env("TICKET_SECRET", `${secret}:tickets`);
const publicGateway = env("PUBLIC_GATEWAY_URL", `ws://127.0.0.1:${port}`);
const replayDir = env("REPLAY_DIR", "replays");
const log = (o: object): void => console.log(JSON.stringify({ level: "info", ...o }));
// Replays are kept 14 days for report review (spec §14.3).
const prune = (): void => {
  const removed = pruneReplays(replayDir);
  if (removed) log({ msg: "replays pruned", removed });
};
prune();
setInterval(prune, 3_600_000).unref();

let social: SocialService | null = null;
let stats: StatsService | null = null;
let auth: AuthService | null = null;
let gateway: Gateway | null = null;

const manager = new MatchManager(
  {
    map,
    fillBots,
    maxPlayersPerMatch: 10,
    replayDir,
    ...(phaseScale ? { phaseScale } : {}),
    verifyTicket: (t) => social?.verifyTicket(t) ?? null,
    onResult: (r) => {
      stats
        ?.record(r as MatchResult)
        .catch((e: unknown) =>
          console.error(
            JSON.stringify({ level: "error", msg: "stats record failed", error: String(e) }),
          ),
        );
    },
  },
  (id, bytes) => gateway?.deliver(id, bytes),
);

if (env("DATABASE_URL") && env("REDIS_URL")) {
  const db = connect(env("DATABASE_URL"));
  const applied = await migrate(db);
  if (applied.length) log({ msg: "migrations applied", applied });
  const redis = new Redis(env("REDIS_URL"));
  auth = new AuthService(db, secret);
  stats = new StatsService(db);
  const agents = (loadRawConfig("agents") as { agents: { id: string }[] }).agents.map((a) => a.id);
  social = new SocialService(redis, {
    ticketSecret,
    agents,
    maps,
    fillAfterSec: Number(env("MM_FILL_AFTER", "15")),
    minCompetitive: Number(env("MM_MIN_COMPETITIVE", "10")),
    agentSelectSec: Number(env("AGENT_SELECT_SEC", "80")),
    onReady: (lobby) => manager.createMatch(lobby.id, lobby.mode, lobby.map),
  });
  social.start();
  await buildApi(
    auth,
    social,
    stats,
    publicGateway,
    replayDir,
    new OAuthService(
      redis,
      auth,
      providersFromEnv(process.env),
      env("OAUTH_REDIRECT_BASE", `http://127.0.0.1:${apiPort}`),
    ),
  ).listen(apiPort);
  log({ msg: "api listening", port: apiPort });
}

gateway = new Gateway({
  port,
  router: manager,
  serverTick: () => 0,
  // Access tokens from the API; guests without a token are allowed for quick play in dev.
  authenticate: (token) => {
    if (!token)
      return env("ALLOW_ANON", "1") === "1"
        ? `Guest#${Math.floor(Math.random() * 9000 + 1000)}`
        : null;
    return auth?.verifyAccess(token)?.name ?? null;
  },
});
await gateway.start();
log({ msg: "gateway listening", port: gateway.port, maps, fillBots });
// Prometheus scrape endpoint (spec §14.5). Keep it on an internal network; it is not public API.
if (metricsPort > 0) {
  await metrics.listen(metricsPort);
  log({ msg: "metrics listening", port: metricsPort });
}

const shutdown = async (): Promise<void> => {
  social?.stop();
  await manager.stopAll();
  await gateway?.stop();
  process.exit(0);
};
process.on("SIGINT", () => void shutdown());
process.on("SIGTERM", () => void shutdown());
