// Match allocator (spec §14.1, simplified): keeps worker-hosted matches with free slots and routes
// player frames to them. One process hosts many matches; scale out by running more processes.
import { Worker } from "node:worker_threads";
import type { FromWorker, ToWorker } from "./worker.ts";

export interface MatchHandle {
  id: string;
  map: string;
  worker: Worker;
  players: Set<number>;
}

export interface ManagerOptions {
  map: string;
  fillBots: boolean;
  maxPlayersPerMatch: number;
  roundsToWin?: number;
  phaseScale?: number;
}

export class MatchManager {
  readonly matches = new Map<string, MatchHandle>();
  private readonly byPlayer = new Map<number, MatchHandle>();
  private nextId = 1;

  constructor(
    private readonly opts: ManagerOptions,
    private readonly deliver: (playerId: number, bytes: Uint8Array) => void,
  ) {}

  join(playerId: number, name: string, agent: string): MatchHandle {
    let handle = [...this.matches.values()].find(
      (m) => m.players.size < this.opts.maxPlayersPerMatch,
    );
    if (!handle) handle = this.create();
    handle.players.add(playerId);
    this.byPlayer.set(playerId, handle);
    this.post(handle, { cmd: "join", playerId, name, agent });
    return handle;
  }

  leave(playerId: number): void {
    const h = this.byPlayer.get(playerId);
    if (!h) return;
    h.players.delete(playerId);
    this.byPlayer.delete(playerId);
    this.post(h, { cmd: "leave", playerId });
  }

  frame(playerId: number, bytes: Uint8Array): void {
    const h = this.byPlayer.get(playerId);
    if (!h) return;
    const ab = bytes.buffer.slice(
      bytes.byteOffset,
      bytes.byteOffset + bytes.byteLength,
    ) as ArrayBuffer;
    h.worker.postMessage({ cmd: "frame", playerId, bytes: ab } satisfies ToWorker, [ab]);
  }

  ping(playerId: number, ms: number): void {
    const h = this.byPlayer.get(playerId);
    if (h) this.post(h, { cmd: "ping", playerId, ms });
  }

  async stopAll(): Promise<void> {
    await Promise.all([...this.matches.values()].map((m) => m.worker.terminate()));
    this.matches.clear();
  }

  private create(): MatchHandle {
    const id = `m-${(this.nextId++).toString().padStart(4, "0")}`;
    const worker = new Worker(new URL("./worker.ts", import.meta.url), {
      workerData: {
        matchId: id,
        map: this.opts.map,
        seed: Math.floor(Math.random() * 2 ** 31),
        fillBots: this.opts.fillBots,
        roundsToWin: this.opts.roundsToWin,
        phaseScale: this.opts.phaseScale,
      },
      execArgv: ["--import", "tsx"],
    });
    const handle: MatchHandle = { id, map: this.opts.map, worker, players: new Set() };
    worker.on("message", (m: FromWorker) => {
      if (m.type === "frame") this.deliver(m.playerId, new Uint8Array(m.bytes));
    });
    worker.on("error", (e) =>
      console.error(
        JSON.stringify({
          level: "error",
          msg: "match worker crashed",
          match: id,
          error: String(e),
        }),
      ),
    );
    this.matches.set(id, handle);
    return handle;
  }

  private post(h: MatchHandle, m: ToWorker): void {
    h.worker.postMessage(m);
  }
}
