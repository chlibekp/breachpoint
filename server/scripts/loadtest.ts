// Load test (spec §18 milestone 10: 200 concurrent matches). Spreads N matches over W worker threads,
// runs them in real time and reports tick cost per worker, late ticks, bandwidth and memory.
// Usage: npx tsx server/scripts/loadtest.ts [--matches 200] [--workers 4] [--seconds 30] [--map solstice]
import { Worker } from "node:worker_threads";
import { cpus } from "node:os";

const arg = (k: string, d: string): string => {
  const i = process.argv.indexOf(`--${k}`);
  return i > 0 ? process.argv[i + 1]! : d;
};
const N = Number(arg("matches", "200"));
const W = Number(arg("workers", String(cpus().length)));
const seconds = Number(arg("seconds", "30"));
const map = arg("map", "solstice");

interface Result {
  matches: number;
  ticks: number;
  avgMs: number;
  p99Ms: number;
  maxMs: number;
  late: number;
  bytesOut: number;
  wallS: number;
}

const per = Math.ceil(N / W);
const jobs: Promise<Result>[] = [];
let peakRss = 0;
const rssTimer = setInterval(() => (peakRss = Math.max(peakRss, process.memoryUsage().rss)), 500);
for (let w = 0, first = 0; w < W && first < N; w++, first += per) {
  const count = Math.min(per, N - first);
  const worker = new Worker(new URL("./loadtest-worker.ts", import.meta.url), {
    workerData: { first, count, seconds, map },
    execArgv: ["--import", "tsx"],
  });
  jobs.push(new Promise((res, rej) => (worker.once("message", res), worker.once("error", rej))));
}
const results = await Promise.all(jobs);
clearInterval(rssTimer);
const players = N * 10;
const bytes = results.reduce((a, r) => a + r.bytesOut, 0);
const wall = Math.max(...results.map((r) => r.wallS));
const perMatchMs = results.reduce((a, r) => a + r.avgMs, 0) / N;
console.log(
  `load test: ${N} matches × 10 clients on ${map}, ${results.length} workers, ${seconds} s`,
);
for (const [i, r] of results.entries())
  console.log(
    `  worker ${i}: ${r.matches} matches  tick avg ${r.avgMs.toFixed(2)} ms  p99 ${r.p99Ms.toFixed(2)} ms  max ${r.maxMs.toFixed(1)} ms  late ${((100 * r.late) / r.ticks).toFixed(1)}%`,
  );
console.log(
  `  per match: ${perMatchMs.toFixed(3)} ms/tick → ${Math.floor(15.625 / perMatchMs)} matches per core at 100% (budget 15.6 ms)`,
);
console.log(
  `  egress ${((bytes * 8) / wall / 1e6).toFixed(1)} Mbit/s total, ${((bytes * 8) / wall / players / 1000).toFixed(1)} kbit/s per client; peak RSS ${(peakRss / 1e6).toFixed(0)} MB`,
);
