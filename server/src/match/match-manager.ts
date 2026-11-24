// Match allocator (spec §14.1, simplified): keeps worker-hosted matches with free slots and routes
// player frames to them. One process hosts many matches; scale out by running more processes.
import { Worker } from "node:worker_threads";
import type { FromWorker, ToWorker } from "./worker.ts";
import { metrics } from "../services/metrics.ts";

export interface MatchHandle {
  id: string;
  map: string;
  mode: string;
  worker: Worker;
  players: Set<number>;
}

export interface TicketInfo {
  matchId: string;
  accountId: string;
  name: string;
  agent: string;
  team: number;
  mode: string;
}

export interface ManagerOptions {
  /** Validates a signed join ticket (matchmaking); null = not a ticket. */
  verifyTicket?: (ticket: string) => TicketInfo | null;
  onResult?: (result: unknown) => void;
  map: string;
  fillBots: boolean;
  maxPlayersPerMatch: number;
  roundsToWin?: number;
  phaseScale?: number;
  /** Where match workers write .bpr replays; omit to disable recording. */
  replayDir?: string;
}

export class MatchManager {
  readonly matches = new Map<string, MatchHandle>();
  private readonly byPlayer = new Map<number, MatchHandle>();
  private nextId = 1;

  constructor(
    private readonly opts: ManagerOptions,
    private readonly deliver: (playerId: number, bytes: Uint8Array) => void,
  ) {}

  /** Quick play (agent name as ticket) or a signed matchmaking ticket for a specific match. */
  join(playerId: number, name: string, ticketOrAgent: string): MatchHandle {
    const t = this.opts.verifyTicket?.(ticketOrAgent) ?? null;
    let handle: MatchHandle | undefined;
    if (t) {
      handle = this.matches.get(t.matchId) ?? this.create(t.matchId, t.mode);
    } else {
      handle = [...this.matches.values()].find(
        (m) => m.mode === "quick" && m.players.size < this.opts.maxPlayersPerMatch,
      );
      if (!handle) handle = this.create();
    }
    handle.players.add(playerId);
    this.byPlayer.set(playerId, handle);
    this.post(handle, {
      cmd: "join",
      playerId,
      name: t ? t.name : name,
      agent: t ? t.agent : ticketOrAgent || "kestrel",
      team: t?.team ?? -1,
      accountId: t?.accountId ?? "",
    });
    return handle;
  }

  /** Pre-creates a match for a finished agent select (spec §14.1 match allocator). */
  createMatch(id: string, mode: string, map: string): void {
    if (!this.matches.has(id)) this.create(id, mode, map);
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

  private readonly playerCounts = new Map<string, { humans: number; bots: number }>();

  private onMetrics(id: string, m: Extract<FromWorker, { type: "metrics" }>): void {
    metrics.tickSeconds.merge(m.tick.counts, m.tick.sum, m.tick.count);
    metrics.lateTicks.inc(m.lateTicks);
    metrics.inputsReceived.inc(m.inputs);
    metrics.inputsMissing.inc(m.missing);
    this.playerCounts.set(id, { humans: m.humans, bots: m.bots });
    this.publishGauges();
  }

  private publishGauges(): void {
    let humans = 0;
    let bots = 0;
    for (const c of this.playerCounts.values()) {
      humans += c.humans;
      bots += c.bots;
    }
    metrics.players.set(humans, { kind: "human" });
    metrics.players.set(bots, { kind: "bot" });
    metrics.matches.set(this.matches.size);
  }

  /** Frees a finished match: forget its players and terminate the worker. */
  private release(h: MatchHandle): void {
    for (const id of h.players) this.byPlayer.delete(id);
    h.players.clear();
    this.matches.delete(h.id);
    this.playerCounts.delete(h.id);
    this.publishGauges();
    void h.worker.terminate();
  }

  async stopAll(): Promise<void> {
    await Promise.all([...this.matches.values()].map((m) => m.worker.terminate()));
    this.matches.clear();
  }

  private create(fixedId?: string, mode = "quick", mapOverride?: string): MatchHandle {
    // Unique across restarts: match ids key the matches table and replay files.
    const id =
      fixedId ?? `m-${Date.now().toString(36)}-${(this.nextId++).toString().padStart(4, "0")}`;
    const map = mapOverride ?? this.opts.map;
    const worker = new Worker(new URL("./worker.ts", import.meta.url), {
      workerData: {
        matchId: id,
        map,
        mode,
        seed: Math.floor(Math.random() * 2 ** 31),
        fillBots: this.opts.fillBots,
        roundsToWin: this.opts.roundsToWin,
        phaseScale: this.opts.phaseScale,
        replayDir: this.opts.replayDir,
      },
      execArgv: ["--import", "tsx"],
    });
    const handle: MatchHandle = {
      id,
      map,
      mode,
      worker,
      players: new Set(),
    };
    worker.on("message", (m: FromWorker) => {
      if (m.type === "frame") this.deliver(m.playerId, new Uint8Array(m.bytes));
      else if (m.type === "result") this.opts.onResult?.(m.result);
      else if (m.type === "ended") this.release(handle);
      else if (m.type === "metrics") this.onMetrics(handle.id, m);
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
