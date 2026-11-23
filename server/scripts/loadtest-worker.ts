// One load-test worker: hosts `count` matches in a single 64 Hz loop (deployment packs several
// matches per core the same way). Each match has 10 synthetic human clients sending a random-walk
// input every tick; every outgoing message is encoded so snapshot + fog-of-war costs are real.
import { parentPort, workerData } from "node:worker_threads";
import { encode } from "@breachpoint/shared/protocol";
import { Match } from "../src/match/match.ts";
import { Buttons as B } from "../src/sim/movement.ts";

interface Job {
  first: number;
  count: number;
  seconds: number;
  map: string;
}
const job = workerData as Job;
const TICK_MS = 1000 / 64;
let bytesOut = 0;
const matches: { m: Match; yaw: number[]; seq: number }[] = [];
for (let i = 0; i < job.count; i++) {
  const m = new Match({
    matchId: `load-${job.first + i}`,
    map: job.map,
    seed: job.first + i,
    roundsToWin: 13,
  });
  m.setTransport((_id, msg) => {
    bytesOut += encode(msg).byteLength;
  });
  for (let p = 1; p <= 10; p++) m.addPlayer(p, `client${p}`, "kestrel", false, p <= 5 ? 0 : 1);
  m.startManual();
  matches.push({ m, yaw: Array.from({ length: 11 }, () => Math.random() * 6.28), seq: 0 });
}

const tickTimes: number[] = [];
let late = 0;
const start = performance.now();
let ticks = 0;
const total = Math.round(job.seconds * 64);
function loop(): void {
  while (ticks < total && performance.now() - start >= ticks * TICK_MS) {
    const t0 = performance.now();
    for (const s of matches) {
      s.seq++;
      for (let p = 1; p <= 10; p++) {
        s.yaw[p]! += (Math.random() - 0.5) * 0.2;
        const r = Math.random();
        const buttons =
          B.FORWARD | (r < 0.3 ? B.LEFT : r > 0.7 ? B.RIGHT : 0) | (r > 0.85 ? B.FIRE : 0);
        s.m.receiveInput(p, [
          {
            seq: s.seq,
            tick: s.m.tick,
            buttons,
            yaw: s.yaw[p]!,
            pitch: 0,
            weaponSlot: 1,
            interpMs: 100,
          },
        ]);
      }
      s.m.step();
    }
    const dt = performance.now() - t0;
    tickTimes.push(dt);
    if (dt > TICK_MS) late++;
    ticks++;
  }
  if (ticks >= total) {
    tickTimes.sort((a, b) => a - b);
    parentPort!.postMessage({
      matches: job.count,
      ticks,
      avgMs: tickTimes.reduce((a, b) => a + b, 0) / tickTimes.length,
      p99Ms: tickTimes[Math.floor(tickTimes.length * 0.99)]!,
      maxMs: tickTimes[tickTimes.length - 1]!,
      late,
      bytesOut,
      wallS: (performance.now() - start) / 1000,
    });
    return;
  }
  setTimeout(loop, Math.max(0, ticks * TICK_MS - (performance.now() - start) - 1));
}
loop();
