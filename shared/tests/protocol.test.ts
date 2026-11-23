import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { decode, encode, MsgId, type Message } from "../protocol/generated/protocol.ts";
import { dequantizeAngle, quantizeAngle } from "../protocol/codec.ts";
import { fromHex, messageFromJson, toHex, type ProtocolVector } from "../protocol/vectors.ts";
import { SHARED_DIR } from "../src/config.ts";

const { vectors } = JSON.parse(
  readFileSync(join(SHARED_DIR, "tests", "protocol", "vectors.json"), "utf8"),
) as { vectors: ProtocolVector[] };

/** Compare decoded output with the source message, allowing for quantisation. */
function approx(actual: unknown, expected: unknown, path: string): void {
  if (typeof expected === "number") {
    expect(typeof actual, path).toBe("number");
    expect(Math.abs((actual as number) - expected), path).toBeLessThanOrEqual(1e-3);
  } else if (expected instanceof Uint8Array) {
    expect(toHex(actual as Uint8Array), path).toBe(toHex(expected));
  } else if (Array.isArray(expected)) {
    expect((actual as unknown[]).length, path).toBe(expected.length);
    expected.forEach((e, i) => approx((actual as unknown[])[i], e, `${path}[${i}]`));
  } else if (expected !== null && typeof expected === "object") {
    for (const [k, v] of Object.entries(expected))
      approx((actual as Record<string, unknown>)[k], v, `${path}.${k}`);
  } else {
    expect(actual, path).toBe(expected);
  }
}

describe("protocol golden vectors", () => {
  it("covers every message type", () => {
    const covered = new Set(vectors.map((v) => v.message["type"]));
    for (const name of Object.keys(MsgId)) expect(covered.has(name), name).toBe(true);
  });

  for (const v of vectors) {
    it(`${String(v.message["type"])} encodes to the golden bytes and round-trips`, () => {
      const msg = messageFromJson(v.message);
      expect(toHex(encode(msg))).toBe(v.hex);
      approx(decode(fromHex(v.hex)), msg, String(msg.type));
    });
  }
});

describe("codec safety", () => {
  it("rejects truncated and trailing data", () => {
    const bytes = encode({ type: "Ping", nonce: 1, clientTimeMs: 2 });
    expect(() => decode(bytes.subarray(0, bytes.length - 1))).toThrow();
    expect(() => decode(new Uint8Array([...bytes, 0]))).toThrow();
    expect(() => decode(new Uint8Array([250]))).toThrow();
  });

  it("enforces array maximums", () => {
    const tooMany: Message = {
      type: "Input",
      ackSnapshot: 0,
      cmds: Array.from({ length: 4 }, (_, i) => ({
        seq: i,
        tick: i,
        buttons: 0,
        yaw: 0,
        pitch: 0,
        weaponSlot: 0,
      })),
    };
    expect(() => encode(tooMany)).toThrow();
  });

  it("quantises angles to within half a step and wraps to (-π, π]", () => {
    for (const a of [-Math.PI, -2.5, -0.001, 0, 0.7, Math.PI, 7]) {
      const back = dequantizeAngle(quantizeAngle(a));
      const diff = Math.atan2(Math.sin(back - a), Math.cos(back - a));
      expect(Math.abs(diff)).toBeLessThan(Math.PI / 65536 + 1e-12);
      expect(back).toBeGreaterThan(-Math.PI - 1e-12);
      expect(back).toBeLessThanOrEqual(Math.PI);
    }
  });
});
