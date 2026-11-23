// Golden protocol vectors: JSON <-> Message helpers shared by the vector generator and tests.
import type { Message } from "./generated/protocol.ts";

export interface ProtocolVector {
  message: Record<string, unknown>;
  hex: string;
}

export function toHex(bytes: Uint8Array): string {
  return Buffer.from(bytes).toString("hex");
}
export function fromHex(hex: string): Uint8Array {
  return new Uint8Array(Buffer.from(hex, "hex"));
}

/** JSON form: Uint8Array fields become {"$bytes": "<hex>"}. */
export function messageToJson(msg: Message): Record<string, unknown> {
  return JSON.parse(
    JSON.stringify(msg, (_k, v: unknown) => (v instanceof Uint8Array ? { $bytes: toHex(v) } : v)),
  ) as Record<string, unknown>;
}
export function messageFromJson(json: Record<string, unknown>): Message {
  return JSON.parse(JSON.stringify(json), (_k, v: unknown) => {
    if (v !== null && typeof v === "object" && "$bytes" in v) {
      return fromHex((v as { $bytes: string }).$bytes);
    }
    return v;
  }) as Message;
}
