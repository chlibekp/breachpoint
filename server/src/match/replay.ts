// Match replays (spec §14.4). Every match is recorded as the ordered stream of protocol messages a
// full-visibility spectator would receive: an unculled Snapshot every REPLAY_EVERY ticks plus every
// broadcast event (kills, round ends, charge, ability FX…), in the same binary codec the client
// already speaks, gzip-compressed while the match runs (no whole-match buffering).
//
// File (.bpr, gzip): "BPR1" | u32 headerLen | header JSON | frames…
//   frame = u32 tick | u16 len | <len bytes: one encoded protocol message>
// Inputs are validated and folded into the snapshots on the server; recording snapshots (rather than
// re-simulating inputs) keeps the viewer independent of sim-version drift. See docs/DECISIONS.md.
import { createWriteStream, mkdirSync, readdirSync, statSync, unlinkSync } from "node:fs";
import { join } from "node:path";
import { createGzip, gunzipSync, type Gzip } from "node:zlib";
import { decode, encode, type Message } from "@breachpoint/shared/protocol";

export const REPLAY_MAGIC = "BPR1";
/** Record a snapshot every 3rd tick (21.3 Hz): smooth with interpolation, ~1/3 the size. */
export const REPLAY_EVERY = 3;
export const REPLAY_RETENTION_DAYS = 14;

export interface ReplayHeader {
  matchId: string;
  map: string;
  mode: string;
  tickRate: number;
  snapshotEvery: number;
  startedAt: string;
}

export class ReplayRecorder {
  private readonly gz: Gzip;
  private readonly done: Promise<void>;
  private closed = false;
  frames = 0;

  constructor(
    readonly path: string,
    header: ReplayHeader,
  ) {
    this.gz = createGzip({ level: 6 });
    const out = createWriteStream(path);
    this.done = new Promise((resolve, reject) => {
      out.on("finish", resolve);
      out.on("error", reject);
    });
    this.gz.pipe(out);
    const h = Buffer.from(JSON.stringify(header), "utf8");
    const pre = Buffer.alloc(8);
    pre.write(REPLAY_MAGIC, 0, "ascii");
    pre.writeUInt32LE(h.length, 4);
    this.gz.write(pre);
    this.gz.write(h);
  }

  record(tick: number, msg: Message): void {
    if (this.closed) return;
    let bytes: Uint8Array;
    try {
      bytes = encode(msg);
    } catch {
      return;
    }
    if (bytes.length > 0xffff) return;
    const f = Buffer.alloc(6);
    f.writeUInt32LE(tick, 0);
    f.writeUInt16LE(bytes.length, 4);
    this.gz.write(f);
    this.gz.write(bytes);
    this.frames++;
  }

  close(): Promise<void> {
    if (!this.closed) {
      this.closed = true;
      this.gz.end();
    }
    return this.done;
  }
}

export interface ReplayFrame {
  tick: number;
  msg: Message;
}

/** Parses a whole .bpr file (tests, tooling). The client has its own GDScript reader. */
export function readReplay(gz: Uint8Array): { header: ReplayHeader; frames: ReplayFrame[] } {
  const b = gunzipSync(gz);
  if (b.toString("ascii", 0, 4) !== REPLAY_MAGIC) throw new Error("not a replay");
  const hl = b.readUInt32LE(4);
  const header = JSON.parse(b.toString("utf8", 8, 8 + hl)) as ReplayHeader;
  const frames: ReplayFrame[] = [];
  let o = 8 + hl;
  while (o + 6 <= b.length) {
    const tick = b.readUInt32LE(o);
    const len = b.readUInt16LE(o + 4);
    o += 6;
    frames.push({ tick, msg: decode(new Uint8Array(b.buffer, b.byteOffset + o, len)) });
    o += len;
  }
  return { header, frames };
}

export function replayPath(dir: string, matchId: string): string | null {
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(matchId)) return null;
  return join(dir, `${matchId}.bpr`);
}

export function ensureReplayDir(dir: string): void {
  mkdirSync(dir, { recursive: true });
}

/** Deletes replays older than the retention window (spec §14.3: kept 14 days for review). */
export function pruneReplays(dir: string, now = Date.now(), days = REPLAY_RETENTION_DAYS): number {
  let removed = 0;
  let names: string[] = [];
  try {
    names = readdirSync(dir);
  } catch {
    return 0;
  }
  for (const n of names) {
    if (!n.endsWith(".bpr")) continue;
    const p = join(dir, n);
    try {
      if (now - statSync(p).mtimeMs > days * 86_400_000) {
        unlinkSync(p);
        removed++;
      }
    } catch {
      /* raced with another pruner */
    }
  }
  return removed;
}
