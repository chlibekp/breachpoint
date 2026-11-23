// WebSocket gateway (spec 13.1). Milestone 1 scope: binary framing with the generated
// protocol, version check, guest auth, ping/pong. Matches are attached in milestone 4.
import { type AddressInfo } from "node:net";
import { WebSocketServer, type RawData, type WebSocket } from "ws";
import { decode, encode, PROTOCOL_VERSION, type Message } from "@breachpoint/shared/protocol";

export interface GatewayOptions {
  port: number;
  host?: string;
  /** Returns the current server tick for Pong/AuthOk. */
  serverTick?: () => number;
}

interface Session {
  playerId: number;
  authed: boolean;
}

const MAX_FRAME_BYTES = 4096;

export class Gateway {
  private wss: WebSocketServer | null = null;
  private nextPlayerId = 0;
  private readonly sessions = new Map<WebSocket, Session>();

  constructor(private readonly options: GatewayOptions) {}

  get port(): number {
    return (this.wss?.address() as AddressInfo | undefined)?.port ?? 0;
  }

  get connectionCount(): number {
    return this.sessions.size;
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
    });
  }

  stop(): Promise<void> {
    return new Promise((resolve) => {
      for (const ws of this.sessions.keys()) ws.terminate();
      this.sessions.clear();
      if (this.wss) this.wss.close(() => resolve());
      else resolve();
    });
  }

  private send(ws: WebSocket, msg: Message): void {
    ws.send(encode(msg), { binary: true });
  }

  private onConnection(ws: WebSocket): void {
    const session: Session = { playerId: this.nextPlayerId++ % 256, authed: false };
    this.sessions.set(ws, session);
    ws.on("message", (data, isBinary) => this.onMessage(ws, session, data, isBinary));
    ws.on("close", () => this.sessions.delete(ws));
    ws.on("error", () => ws.terminate());
  }

  private onMessage(ws: WebSocket, session: Session, data: RawData, isBinary: boolean): void {
    if (!isBinary || !(data instanceof Buffer)) {
      this.drop(ws, "binary_only");
      return;
    }
    let msg: Message;
    try {
      msg = decode(new Uint8Array(data.buffer, data.byteOffset, data.byteLength));
    } catch {
      this.drop(ws, "malformed");
      return;
    }
    const tick = this.options.serverTick?.() ?? 0;
    if (!session.authed) {
      if (msg.type !== "Hello") return this.drop(ws, "hello_required");
      if (msg.protocolVersion !== PROTOCOL_VERSION) return this.drop(ws, "protocol_mismatch");
      // Milestone 8 replaces this with JWT validation; for now every client is a guest.
      session.authed = true;
      this.send(ws, {
        type: "AuthOk",
        playerId: session.playerId,
        displayName: `Guest#${(1000 + session.playerId).toString()}`,
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
        break;
      case "Disconnect":
        ws.close(1000, "bye");
        break;
      default:
        // Gameplay messages are routed to match workers from milestone 4 on.
        break;
    }
  }

  private drop(ws: WebSocket, reason: string): void {
    this.send(ws, { type: "Disconnect", reason });
    ws.close(1008, reason);
  }
}
