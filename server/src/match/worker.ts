// worker_threads entry: one match per worker (spec §13.1). The gateway forwards raw client frames;
// the worker decodes, simulates and posts encoded frames back (ArrayBuffers are transferred).
import { parentPort, workerData } from "node:worker_threads";
import { decode, encode, type Message } from "@breachpoint/shared/protocol";
import { Match, type MatchOptions } from "./match.ts";

export type ToWorker =
  | { cmd: "join"; playerId: number; name: string; agent: string }
  | { cmd: "leave"; playerId: number }
  | { cmd: "frame"; playerId: number; bytes: ArrayBuffer }
  | { cmd: "ping"; playerId: number; ms: number }
  | { cmd: "stats" }
  | { cmd: "stop" };

export type FromWorker =
  | { type: "frame"; playerId: number; bytes: ArrayBuffer }
  | { type: "stats"; tick: number; players: number; maxTickMs: number; lastTickMs: number }
  | { type: "stopped" };

const match = new Match(workerData as MatchOptions);
const port = parentPort!;
match.setTransport((playerId: number, msg: Message) => {
  let bytes: Uint8Array;
  try {
    bytes = encode(msg);
  } catch (e) {
    console.error(
      JSON.stringify({ level: "error", msg: "encode failed", type: msg.type, error: String(e) }),
    );
    return;
  }
  const ab = bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength,
  ) as ArrayBuffer;
  port.postMessage({ type: "frame", playerId, bytes: ab } satisfies FromWorker, [ab]);
});
match.start();

port.on("message", (m: ToWorker) => {
  switch (m.cmd) {
    case "join":
      match.addPlayer(m.playerId, m.name, m.agent);
      break;
    case "leave":
      match.removePlayer(m.playerId);
      break;
    case "ping": {
      const p = match.players.get(m.playerId);
      if (p) p.pingMs = m.ms;
      break;
    }
    case "frame": {
      let msg: Message;
      try {
        msg = decode(new Uint8Array(m.bytes));
      } catch {
        return;
      }
      if (msg.type === "Input") match.receiveInput(m.playerId, msg.cmds);
      else if (msg.type === "BuyRequest") match.buy(m.playerId, msg.item);
      break;
    }
    case "stats":
      port.postMessage({
        type: "stats",
        tick: match.tick,
        players: match.players.size,
        maxTickMs: match.loop.stats.maxTickMs,
        lastTickMs: match.loop.stats.lastTickMs,
      } satisfies FromWorker);
      break;
    case "stop":
      match.stop();
      port.postMessage({ type: "stopped" } satisfies FromWorker);
      break;
  }
});
