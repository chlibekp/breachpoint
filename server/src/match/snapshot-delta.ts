// Snapshot delta codec (spec §13: snapshots delta-compressed against the last acknowledged one).
// Codec-agnostic: XOR the encoded Snapshot with the encoded base Snapshot (same length: same players
// in the same order), then run-length encode the zero bytes. Token stream:
//   0x00 n   → n zero bytes (1..255)
//   b (≠ 0)  → one literal byte
// Mirrored in client/scripts/net/snapshot_delta.gd; shared golden data in the protocol tests.

export function encodeDelta(full: Uint8Array, base: Uint8Array): Uint8Array | null {
  if (full.length !== base.length) return null;
  const out: number[] = [];
  let i = 0;
  while (i < full.length) {
    const x = full[i]! ^ base[i]!;
    if (x !== 0) {
      out.push(x);
      i++;
      continue;
    }
    let run = 0;
    while (i < full.length && run < 255 && (full[i]! ^ base[i]!) === 0) {
      run++;
      i++;
    }
    out.push(0, run);
  }
  return Uint8Array.from(out);
}

export function decodeDelta(delta: Uint8Array, base: Uint8Array): Uint8Array {
  const out = new Uint8Array(base.length);
  let o = 0;
  for (let i = 0; i < delta.length; i++) {
    const b = delta[i]!;
    if (b === 0) {
      const run = delta[++i]!;
      for (let k = 0; k < run; k++, o++) out[o] = base[o]!;
    } else {
      out[o] = base[o]! ^ b;
      o++;
    }
  }
  if (o !== base.length) throw new Error("delta length mismatch");
  return out;
}
