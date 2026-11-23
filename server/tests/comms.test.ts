import { describe, expect, it } from "vitest";
import type { Message } from "@breachpoint/shared/protocol";
import { Match } from "../src/match/match.ts";

function setup(): { m: Match; got: Map<number, Message[]> } {
  const m = new Match({ matchId: "c", map: "solstice", seed: 1 });
  const got = new Map<number, Message[]>();
  m.setTransport((id, msg) => {
    if (
      msg.type === "Chat" ||
      msg.type === "VoiceSignal" ||
      msg.type === "VoiceData" ||
      msg.type === "MapPing"
    )
      (got.get(id) ?? got.set(id, []).get(id)!).push(msg);
  });
  m.addPlayer(1, "a1", "kestrel", false, 0);
  m.addPlayer(2, "a2", "kestrel", false, 0);
  m.addPlayer(3, "b1", "kestrel", false, 1);
  m.startManual();
  return { m, got };
}

describe("text chat and voice relay (spec 15.4)", () => {
  it("team chat reaches only teammates; all chat reaches everyone; control chars stripped", () => {
    const { m, got } = setup();
    m.chat(1, true, "rotate\u0007 B");
    m.chat(3, false, "gg");
    expect(got.get(2)?.map((x) => x.type === "Chat" && x.text)).toEqual(["rotate B", "gg"]);
    expect(got.get(3)?.map((x) => x.type === "Chat" && x.text)).toEqual(["gg"]);
  });

  it("rate-limits chat to 5 messages per 5 s", () => {
    const { m, got } = setup();
    for (let i = 0; i < 9; i++) m.chat(1, false, `spam ${i}`);
    expect(got.get(3)?.length).toBe(5);
  });

  it("relays voice signalling and frames to teammates only, stamped with the sender", () => {
    const { m, got } = setup();
    m.voiceSignal(1, 2, 0, "v=0");
    m.voiceSignal(1, 3, 0, "v=0"); // enemy: dropped
    m.voiceData(1, 7, new Uint8Array(320));
    m.voiceData(1, 8, new Uint8Array(1000)); // oversized: dropped
    const toMate = got.get(2) ?? [];
    expect(toMate.map((x) => x.type)).toEqual(["VoiceSignal", "VoiceData"]);
    expect(toMate[0]!.type === "VoiceSignal" && toMate[0]!.fromId).toBe(1);
    expect(toMate[1]!.type === "VoiceData" && toMate[1]!.playerId).toBe(1);
    expect(got.get(3)).toBeUndefined();
  });

  it("map pings go to the sender's team only and are rate-limited", () => {
    const { m, got } = setup();
    for (let i = 0; i < 5; i++) m.mapPing(1, 0, { x: 1, y: 0, z: 2 });
    expect(got.get(2)?.filter((x) => x.type === "MapPing").length).toBe(3);
    expect(got.get(3)).toBeUndefined();
  });
});
