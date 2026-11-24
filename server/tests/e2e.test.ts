// End-to-end: real server process (API + gateway + matcher + match worker), HTTP + WebSocket client.
// Requires PostgreSQL + Redis (TEST_DATABASE_URL / TEST_REDIS_URL); skipped otherwise.
import { spawn, type ChildProcess } from "node:child_process";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import WebSocket from "ws";
import pg from "pg";
import { decode, encode, PROTOCOL_VERSION, type Message } from "@breachpoint/shared/protocol";

const DB = process.env["TEST_DATABASE_URL"];
const REDIS = process.env["TEST_REDIS_URL"];
const run = DB && REDIS ? describe : describe.skip;
const API = "http://127.0.0.1:17351";

async function call(
  method: string,
  path: string,
  body?: unknown,
  token?: string,
): Promise<{ status: number; body: Record<string, unknown> }> {
  const res = await fetch(API + path, {
    method,
    headers: {
      "content-type": "application/json",
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
  });
  const text = await res.text();
  return { status: res.status, body: text ? (JSON.parse(text) as Record<string, unknown>) : {} };
}

run("matchmaking end to end", () => {
  let server: ChildProcess;
  beforeAll(async () => {
    const db = new pg.Client({ connectionString: DB });
    await db.connect();
    await db.query("DROP SCHEMA public CASCADE; CREATE SCHEMA public;");
    await db.end();
    server = spawn("npx", ["tsx", "server/src/main.ts"], {
      env: {
        ...process.env,
        PORT: "17350",
        API_PORT: "17351",
        METRICS_PORT: "17352",
        DATABASE_URL: DB,
        REDIS_URL: REDIS,
        MM_FILL_AFTER: "1",
        AGENT_SELECT_SEC: "3",
        PUBLIC_GATEWAY_URL: "ws://127.0.0.1:17350",
        ALLOW_ANON: "0",
      },
      stdio: "pipe",
      // Own process group: npx → tsx → node; killing only npx would leave the server running.
      detached: true,
    });
    for (let i = 0; i < 60; i++) {
      try {
        if ((await call("GET", "/health")).status === 200) return;
      } catch {
        /* not up yet */
      }
      await new Promise((r) => setTimeout(r, 250));
    }
    throw new Error("server did not start");
  }, 30000);
  afterAll(() => {
    if (server.pid) process.kill(-server.pid, "SIGTERM");
  });

  it("register → queue → agent select → ticket → join the match over WebSocket", async () => {
    const reg = await call("POST", "/auth/register", {
      email: "e2e@example.com",
      password: "hunter2hunter2",
      name: "Tester",
    });
    expect(reg.status).toBe(201);
    const token = String(reg.body["accessToken"]);
    expect((await call("POST", "/queue", { mode: "unrated" }, token)).status).toBe(200);
    let status: Record<string, unknown> = {};
    for (let i = 0; i < 40 && status["state"] !== "agent_select"; i++) {
      await new Promise((r) => setTimeout(r, 250));
      status = (await call("GET", "/queue/status", undefined, token)).body;
    }
    expect(status["state"]).toBe("agent_select");
    expect((await call("POST", "/select", { agent: "sable", lock: true }, token)).status).toBe(200);
    for (let i = 0; i < 40 && status["state"] !== "ready"; i++) {
      await new Promise((r) => setTimeout(r, 250));
      status = (await call("GET", "/queue/status", undefined, token)).body;
    }
    expect(status["state"]).toBe("ready");
    const ticket = String(status["ticket"]);
    // Anonymous Hello is refused (ALLOW_ANON=0)…
    // …and the authenticated one joins the ticket's match with the locked agent.
    const ws = new WebSocket(String(status["server"]));
    const seen: Message[] = [];
    await new Promise<void>((resolve, reject) => {
      ws.on("open", () =>
        ws.send(
          encode({ type: "Hello", protocolVersion: PROTOCOL_VERSION, token, platform: "test" }),
        ),
      );
      ws.on("message", (d: Buffer) => {
        const m = decode(new Uint8Array(d));
        seen.push(m);
        if (m.type === "AuthOk") ws.send(encode({ type: "JoinMatch", ticket }));
        if (
          m.type === "MatchState" &&
          m.roster.some((r) => r.name.startsWith("Tester#") && r.agent === "sable")
        )
          resolve();
      });
      ws.on("error", reject);
      setTimeout(
        () =>
          reject(
            new Error(`no MatchState with our agent; saw ${seen.map((s) => s.type).join(",")}`),
          ),
        8000,
      );
    });
    const auth = seen.find((m) => m.type === "AuthOk");
    expect(auth && auth.type === "AuthOk" && auth.displayName.startsWith("Tester#")).toBe(true);
    ws.close();
  }, 30000);
});
