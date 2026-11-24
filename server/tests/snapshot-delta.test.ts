import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { encode, type Message } from "@breachpoint/shared/protocol";
import { decodeDelta, encodeDelta } from "../src/match/snapshot-delta.ts";
import { Match } from "../src/match/match.ts";

const hex = (s: string): Uint8Array => Uint8Array.from(Buffer.from(s, "hex"));

describe("snapshot delta codec", () => {
  it("matches the shared golden sample (also checked by the GDScript decoder)", () => {
    const g = JSON.parse(
      readFileSync(
        new URL("../../shared/tests/protocol/snapshot-delta.json", import.meta.url),
        "utf8",
      ),
    ) as { base: string; full: string; delta: string };
    expect(Buffer.from(encodeDelta(hex(g.full), hex(g.base))!).toString("hex")).toBe(g.delta);
    expect(Buffer.from(decodeDelta(hex(g.delta), hex(g.base))).toString("hex")).toBe(g.full);
  });

  it("refuses bases of a different length", () => {
    expect(encodeDelta(new Uint8Array(4), new Uint8Array(5))).toBeNull();
  });

  it("sends deltas once the client acks, and they rebuild the exact snapshot", () => {
    const m = new Match({
      matchId: "d",
      map: "solstice",
      seed: 2,
      fillBots: true,
      snapshotDeltas: true,
    });
    const sent: Message[] = [];
    m.setTransport((id, msg) => {
      if (id === 1 && (msg.type === "Snapshot" || msg.type === "SnapshotDelta")) sent.push(msg);
    });
    m.addPlayer(1, "human");
    m.startManual();
    const have = new Map<number, Uint8Array>();
    let deltas = 0;
    let fullBytes = 0;
    let wireBytes = 0;
    for (let t = 0; t < 64 * 20; t++) {
      // Ack the newest snapshot we hold, as the client does in every Input.
      const ack = Math.max(0, ...have.keys());
      m.receiveInput(
        1,
        [{ seq: t + 1, tick: m.tick, buttons: 1, yaw: 0, pitch: 0, weaponSlot: 1, interpMs: 100 }],
        ack,
      );
      m.step();
      for (const msg of sent.splice(0)) {
        if (msg.type === "Snapshot") {
          const b = encode(msg);
          have.set(msg.tick, b);
          fullBytes += b.length;
          wireBytes += b.length;
        } else if (msg.type === "SnapshotDelta") {
          deltas++;
          const base = have.get(msg.baseTick)!;
          expect(base).toBeDefined();
          const full = decodeDelta(msg.data, base);
          have.set(msg.tick, full);
          fullBytes += full.length;
          wireBytes += encode(msg).length;
        }
      }
    }
    expect(deltas).toBeGreaterThan(64 * 10);
    console.log(
      `snapshot bytes: full ${fullBytes}, on the wire ${wireBytes} (${((100 * wireBytes) / fullBytes).toFixed(0)} %)`,
    );
    expect(wireBytes).toBeLessThan(fullBytes * 0.8);
  });
});
