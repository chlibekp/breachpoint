import { afterAll, beforeAll, describe, expect, it } from "vitest";
import WebSocket from "ws";
import { decode, encode, PROTOCOL_VERSION, type Message } from "@breachpoint/shared/protocol";
import { Gateway } from "../src/gateway/gateway.ts";

let gw: Gateway;

beforeAll(async () => {
  gw = new Gateway({ port: 0, host: "127.0.0.1", serverTick: () => 4242 });
  await gw.start();
});
afterAll(async () => {
  await gw.stop();
});

function connect(): Promise<{ ws: WebSocket; next: () => Promise<Message> }> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://127.0.0.1:${gw.port.toString()}`);
    const queue: Message[] = [];
    const waiters: ((m: Message) => void)[] = [];
    ws.on("message", (data: Buffer) => {
      const m = decode(new Uint8Array(data));
      const w = waiters.shift();
      if (w) w(m);
      else queue.push(m);
    });
    ws.on("open", () =>
      resolve({
        ws,
        next: () => new Promise((r) => (queue.length > 0 ? r(queue.shift()!) : waiters.push(r))),
      }),
    );
    ws.on("error", reject);
  });
}

describe("Gateway", () => {
  it("authenticates a guest and answers pings with the server tick", async () => {
    const { ws, next } = await connect();
    ws.send(
      encode({ type: "Hello", protocolVersion: PROTOCOL_VERSION, token: "", platform: "test" }),
    );
    const auth = await next();
    expect(auth.type).toBe("AuthOk");
    ws.send(encode({ type: "Ping", nonce: 9, clientTimeMs: 12.5 }));
    const pong = await next();
    expect(pong).toEqual({ type: "Pong", nonce: 9, clientTimeMs: 12.5, serverTick: 4242 });
    ws.close();
  });

  it("rejects a protocol version mismatch", async () => {
    const { ws, next } = await connect();
    ws.send(
      encode({ type: "Hello", protocolVersion: PROTOCOL_VERSION + 1, token: "", platform: "test" }),
    );
    expect(await next()).toEqual({ type: "Disconnect", reason: "protocol_mismatch" });
  });

  it("requires Hello before anything else", async () => {
    const { ws, next } = await connect();
    ws.send(encode({ type: "Ping", nonce: 1, clientTimeMs: 0 }));
    expect(await next()).toEqual({ type: "Disconnect", reason: "hello_required" });
  });
});
