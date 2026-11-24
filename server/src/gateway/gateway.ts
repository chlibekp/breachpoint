// WebSocket gateway (spec §13.1): binary frames with the generated protocol, version check, guest
// auth (JWT in milestone 8), ping/pong, and routing of in-match traffic to match workers.
import { type AddressInfo } from "node:net";
import { WebSocketServer, type RawData, type WebSocket } from "ws";
import { decode, encode, PROTOCOL_VERSION, type Message } from "@breachpoint/shared/protocol";
import { metrics } from "../services/metrics.ts";

export interface MatchRouter {
  join(playerId: number, name: string, agent: string): unknown;
  leave(playerId: number): void;
  frame(playerId: number, bytes: Uint8Array): void;
  ping(playerId: number, ms: number): void;
}

export interface GatewayOptions {
  port: number;
  host?: string;
  serverTick?: () => number;
  router?: MatchRouter;
  /** Validates a session token (milestone 8 accounts). Returns a display name or null. */
  authenticate?: (token: string) => string | null;
}

interface Session {
  playerId: number;
  authed: boolean;
  inMatch: boolean;
  name: string;
  pingSentAt: number;
  rttMs: number;
  /** Rate limiting (spec §14.3): frames in the current 1 s window. */
  frames: number;
  windowStart: number;
}

const MAX_FRAME_BYTES = 4096;
const MAX_FRAMES_PER_SECOND = 200;

export class Gateway {
  private wss: WebSocketServer | null = null;
  private nextPlayerId = 1;
  private readonly sessions = new Map<WebSocket, Session>();
  private readonly byId = new Map<number, WebSocket>();
  private pingTimer: NodeJS.Timeout | null = null;

  constructor(private readonly options: GatewayOptions) {}

  get port(): number {
    return (this.wss?.address() as AddressInfo | undefined)?.port ?? 0;
  }

  get connectionCount(): number {
    return this.sessions.size;
  }

  /** Delivers an encoded server frame to a player (used by the match router). */
  deliver(playerId: number, bytes: Uint8Array): void {
    const ws = this.byId.get(playerId);
    if (ws && ws.readyState === ws.OPEN) {
      ws.send(bytes, { binary: true });
      metrics.bytesOut.inc(bytes.byteLength);
    }
  }

  start(): Promise<void> {
    return new Promise((resolve) => {
      this.wss = new WebSocketServer({
        port: this.options.port,
        host: this.options.host ?? "0.0.0.0",
        maxPayload: MAX_FRAME_BYTES,
        perMessageDeflate: false,
      });
      this.wss.on("connection", (ws) => this.onConnection(ws));
      this.wss.on("listening", () => resolve());
      this.pingTimer = setInterval(() => {
        for (const [ws, s] of this.sessions) {
          s.pingSentAt = performance.now();
          ws.ping();
        }
      }, 1000);
    });
  }

  stop(): Promise<void> {
    if (this.pingTimer) clearInterval(this.pingTimer);
    return new Promise((resolve) => {
      for (const ws of this.sessions.keys()) ws.terminate();
      this.sessions.clear();
      if (this.wss) this.wss.close(() => resolve());
      else resolve();
    });
  }

  private send(ws: WebSocket, msg: Message): void {
    const bytes = encode(msg);
    ws.send(bytes, { binary: true });
    metrics.bytesOut.inc(bytes.byteLength);
  }

  private onConnection(ws: WebSocket): void {
    const id = this.nextPlayerId;
    this.nextPlayerId = (this.nextPlayerId % 199) + 1; // 1..199 (200+ reserved for bots)
    const session: Session = {
      playerId: id,
      authed: false,
      inMatch: false,
      name: "",
      pingSentAt: 0,
      rttMs: 0,
      frames: 0,
      windowStart: performance.now(),
    };
    this.sessions.set(ws, session);
    metrics.connections.set(this.sessions.size);
    this.byId.set(id, ws);
    ws.on("message", (data, isBinary) => this.onMessage(ws, session, data, isBinary));
    ws.on("pong", () => {
      session.rttMs = performance.now() - session.pingSentAt;
      if (session.inMatch) this.options.router?.ping(session.playerId, session.rttMs);
    });
    ws.on("close", () => {
      if (session.inMatch) this.options.router?.leave(session.playerId);
      this.sessions.delete(ws);
      metrics.connections.set(this.sessions.size);
      if (this.byId.get(id) === ws) this.byId.delete(id);
    });
    ws.on("error", () => ws.terminate());
  }

  private onMessage(ws: WebSocket, session: Session, data: RawData, isBinary: boolean): void {
    if (!isBinary || !(data instanceof Buffer)) return this.drop(ws, "binary_only");
    const now = performance.now();
    if (now - session.windowStart > 1000) {
      session.windowStart = now;
      session.frames = 0;
    }
    metrics.bytesIn.inc(data.byteLength);
    if (++session.frames > MAX_FRAMES_PER_SECOND) return this.drop(ws, "rate_limited");
    const bytes = new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
    let msg: Message;
    try {
      msg = decode(bytes);
    } catch {
      return this.drop(ws, "malformed");
    }
    const tick = this.options.serverTick?.() ?? 0;
    if (!session.authed) {
      if (msg.type !== "Hello") return this.drop(ws, "hello_required");
      if (msg.protocolVersion !== PROTOCOL_VERSION) return this.drop(ws, "protocol_mismatch");
      const name = this.options.authenticate
        ? this.options.authenticate(msg.token)
        : `Guest#${(1000 + session.playerId).toString()}`;
      if (name === null) return this.drop(ws, "auth_failed");
      session.authed = true;
      session.name = name;
      this.send(ws, {
        type: "AuthOk",
        playerId: session.playerId,
        displayName: name,
        serverTick: tick,
      });
      return;
    }
    switch (msg.type) {
      case "Ping":
        this.send(ws, {
          type: "Pong",
          nonce: msg.nonce,
          clientTimeMs: msg.clientTimeMs,
          serverTick: tick,
        });
        return;
      case "Disconnect":
        ws.close(1000, "bye");
        return;
      case "JoinMatch":
        if (!session.inMatch && this.options.router) {
          session.inMatch = true;
          // Ticket format (milestone 8 signs it): "<agent>" for quick play.
          this.options.router.join(session.playerId, session.name, msg.ticket || "kestrel");
        }
        return;
      default:
        if (session.inMatch) this.options.router?.frame(session.playerId, bytes);
    }
  }

  private drop(ws: WebSocket, reason: string): void {
    metrics.framesDropped.inc(1, { reason });
    this.send(ws, { type: "Disconnect", reason });
    ws.close(1008, reason);
  }
}
