import { mkdtempSync, readFileSync, utimesSync, writeFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { Match, Phase } from "../src/match/match.ts";
import { pruneReplays, readReplay, replayPath, REPLAY_EVERY } from "../src/match/replay.ts";

describe("match replays", () => {
  it("records a full-visibility stream that round-trips through the codec", async () => {
    const dir = mkdtempSync(join(tmpdir(), "bp-replay-"));
    const m = new Match({
      matchId: "rp1",
      map: "neon",
      mode: "unrated",
      seed: 7,
      fillBots: true,
      roundsToWin: 2,
      phaseScale: 0.4,
      replayDir: dir,
    });
    let finished = false;
    m.onFinished = () => {
      finished = true;
    };
    m.startManual();
    let ticks = 0;
    while (!m.finished && ticks < 64 * 60 * 10) {
      m.step();
      ticks++;
    }
    expect(finished).toBe(true);
    expect(m.phase).toBe(Phase.MATCH_OVER);
    await m.closeReplay();
    const bytes = readFileSync(join(dir, "rp1.bpr"));
    const { header, frames } = readReplay(bytes);
    expect(header.map).toBe("neon");
    expect(header.snapshotEvery).toBe(REPLAY_EVERY);
    const snaps = frames.filter((f) => f.msg.type === "Snapshot");
    // Spectator snapshots carry every player (no fog-of-war culling).
    for (const s of snaps.slice(0, 50))
      if (s.msg.type === "Snapshot") expect(s.msg.players.length).toBe(10);
    // Snapshots run on live ticks; the 10 s post-match hold is mostly idle.
    expect(snaps.length).toBeGreaterThan((ticks / REPLAY_EVERY) * 0.8);
    expect(frames.some((f) => f.msg.type === "RoundEnd")).toBe(true);
    expect(frames.some((f) => f.msg.type === "MatchState")).toBe(true);
    // Ticks are non-decreasing (viewer seeks by binary search).
    for (let i = 1; i < frames.length; i++)
      expect(frames[i]!.tick).toBeGreaterThanOrEqual(frames[i - 1]!.tick);
    console.log(
      `replay ${ticks} ticks, ${frames.length} frames, ${(bytes.length / 1024).toFixed(0)} KiB gz`,
    );
  }, 120000);

  it("rejects unsafe ids and prunes files older than 14 days", () => {
    const dir = mkdtempSync(join(tmpdir(), "bp-prune-"));
    expect(replayPath(dir, "../etc/passwd")).toBeNull();
    const old = join(dir, "old.bpr");
    const fresh = join(dir, "fresh.bpr");
    writeFileSync(old, "x");
    writeFileSync(fresh, "x");
    const t = (Date.now() - 15 * 86_400_000) / 1000;
    utimesSync(old, t, t);
    expect(pruneReplays(dir)).toBe(1);
    expect(existsSync(old)).toBe(false);
    expect(existsSync(fresh)).toBe(true);
  });
});
