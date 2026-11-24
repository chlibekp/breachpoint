// Prometheus metrics (spec §14.5 observability): tick duration, players, bandwidth, packet loss.
// A tiny dependency-free registry that renders the text exposition format on GET /metrics.
import { createServer, type Server } from "node:http";

type Labels = Record<string, string>;

const key = (labels: Labels): string =>
  Object.keys(labels)
    .sort()
    .map((k) => `${k}="${labels[k]!.replace(/["\\\n]/g, "_")}"`)
    .join(",");

abstract class Metric {
  constructor(
    readonly name: string,
    readonly help: string,
    readonly type: "counter" | "gauge" | "histogram",
  ) {}
  abstract render(): string[];
}

export class Counter extends Metric {
  private readonly values = new Map<string, number>();
  constructor(name: string, help: string) {
    super(name, help, "counter");
  }
  inc(by = 1, labels: Labels = {}): void {
    const k = key(labels);
    this.values.set(k, (this.values.get(k) ?? 0) + by);
  }
  get(labels: Labels = {}): number {
    return this.values.get(key(labels)) ?? 0;
  }
  render(): string[] {
    if (this.values.size === 0) return [`${this.name} 0`];
    return [...this.values].map(([k, v]) => `${this.name}${k ? `{${k}}` : ""} ${v}`);
  }
}

export class Gauge extends Metric {
  private readonly values = new Map<string, number>();
  constructor(name: string, help: string) {
    super(name, help, "gauge");
  }
  set(v: number, labels: Labels = {}): void {
    this.values.set(key(labels), v);
  }
  delete(labels: Labels): void {
    this.values.delete(key(labels));
  }
  render(): string[] {
    if (this.values.size === 0) return [`${this.name} 0`];
    return [...this.values].map(([k, v]) => `${this.name}${k ? `{${k}}` : ""} ${v}`);
  }
}

/** Cumulative histogram with fixed upper bounds (seconds or any unit). */
export class Histogram extends Metric {
  readonly counts: number[];
  sum = 0;
  count = 0;
  constructor(
    name: string,
    help: string,
    readonly bounds: number[],
  ) {
    super(name, help, "histogram");
    this.counts = bounds.map(() => 0);
  }
  observe(v: number): void {
    this.sum += v;
    this.count++;
    for (let i = 0; i < this.bounds.length; i++) if (v <= this.bounds[i]!) this.counts[i]!++;
  }
  /** Merge pre-bucketed (cumulative) observations, e.g. from a match worker. */
  merge(counts: number[], sum: number, count: number): void {
    for (let i = 0; i < this.counts.length; i++) this.counts[i]! += counts[i] ?? 0;
    this.sum += sum;
    this.count += count;
  }
  render(): string[] {
    return [
      ...this.bounds.map((b, i) => `${this.name}_bucket{le="${b}"} ${this.counts[i]}`),
      `${this.name}_bucket{le="+Inf"} ${this.count}`,
      `${this.name}_sum ${this.sum}`,
      `${this.name}_count ${this.count}`,
    ];
  }
}

/** Tick-duration buckets in seconds: dense around the 10 ms alert line and the 15.6 ms budget. */
export const TICK_BUCKETS = [
  0.0005, 0.001, 0.002, 0.004, 0.006, 0.008, 0.01, 0.0125, 0.015625, 0.02, 0.05, 0.1,
];

/** Worker-side accumulator: bucketed like TICK_BUCKETS, shipped to the main thread as a delta. */
export class TickSampler {
  counts = TICK_BUCKETS.map(() => 0);
  sum = 0;
  count = 0;
  observe(seconds: number): void {
    this.sum += seconds;
    this.count++;
    for (let i = 0; i < TICK_BUCKETS.length; i++)
      if (seconds <= TICK_BUCKETS[i]!) this.counts[i]!++;
  }
  take(): { counts: number[]; sum: number; count: number } {
    const out = { counts: this.counts, sum: this.sum, count: this.count };
    this.counts = TICK_BUCKETS.map(() => 0);
    this.sum = 0;
    this.count = 0;
    return out;
  }
}

export class Registry {
  private readonly metrics: Metric[] = [];
  readonly tickSeconds = this.add(
    new Histogram("bp_tick_duration_seconds", "Match simulation tick duration", TICK_BUCKETS),
  );
  readonly lateTicks = this.add(
    new Counter("bp_late_ticks_total", "Ticks that started after their deadline"),
  );
  readonly matches = this.add(new Gauge("bp_matches", "Running matches"));
  readonly players = this.add(new Gauge("bp_players", "Players in matches, by kind"));
  readonly connections = this.add(new Gauge("bp_connections", "Open WebSocket connections"));
  readonly bytesOut = this.add(new Counter("bp_bytes_sent_total", "Bytes sent to clients"));
  readonly bytesIn = this.add(new Counter("bp_bytes_received_total", "Bytes received"));
  readonly inputsReceived = this.add(
    new Counter("bp_inputs_total", "Client input commands consumed by the simulation"),
  );
  readonly inputsMissing = this.add(
    new Counter(
      "bp_inputs_missing_total",
      "Ticks where a human had no input queued (packet loss / late packets)",
    ),
  );
  readonly framesDropped = this.add(
    new Counter("bp_frames_dropped_total", "Client frames rejected (rate limit, malformed)"),
  );

  private add<T extends Metric>(m: T): T {
    this.metrics.push(m);
    return m;
  }

  render(): string {
    const lines: string[] = [];
    for (const m of this.metrics) {
      lines.push(`# HELP ${m.name} ${m.help}`, `# TYPE ${m.name} ${m.type}`, ...m.render());
    }
    return lines.join("\n") + "\n";
  }

  listen(port: number, host = "0.0.0.0"): Promise<Server> {
    const server = createServer((req, res) => {
      if (req.url === "/metrics") {
        res.writeHead(200, { "content-type": "text/plain; version=0.0.4" }).end(this.render());
      } else res.writeHead(404).end();
    });
    return new Promise((resolve) => server.listen(port, host, () => resolve(server)));
  }
}

/** Process-wide registry. */
export const metrics = new Registry();
