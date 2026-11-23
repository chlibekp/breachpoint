// Hand-written binary primitives shared by the generated TypeScript codec.
// Quantisation rules here MUST match client/scripts/net/protocol_codec.gd exactly.
export interface Vec3 {
  x: number;
  y: number;
  z: number;
}

const TAU = Math.PI * 2;
const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true });

/** Round half up — identical to GDScript floor(x + 0.5) on doubles. */
export function qround(x: number): number {
  return Math.floor(x + 0.5);
}
export function quantizeAngle(rad: number): number {
  return ((qround((rad / TAU) * 65536) % 65536) + 65536) % 65536;
}
export function dequantizeAngle(q: number): number {
  const a = (q / 65536) * TAU;
  return a > Math.PI ? a - TAU : a;
}
function clamp(v: number, lo: number, hi: number): number {
  return v < lo ? lo : v > hi ? hi : v;
}

export class Writer {
  private buf = new Uint8Array(256);
  private view = new DataView(this.buf.buffer);
  private len = 0;

  private ensure(n: number): void {
    if (this.len + n <= this.buf.length) return;
    let cap = this.buf.length * 2;
    while (cap < this.len + n) cap *= 2;
    const next = new Uint8Array(cap);
    next.set(this.buf.subarray(0, this.len));
    this.buf = next;
    this.view = new DataView(next.buffer);
  }
  u8(v: number): void {
    this.ensure(1);
    this.view.setUint8(this.len, v);
    this.len += 1;
  }
  i8(v: number): void {
    this.ensure(1);
    this.view.setInt8(this.len, v);
    this.len += 1;
  }
  u16(v: number): void {
    this.ensure(2);
    this.view.setUint16(this.len, v, true);
    this.len += 2;
  }
  i16(v: number): void {
    this.ensure(2);
    this.view.setInt16(this.len, v, true);
    this.len += 2;
  }
  u32(v: number): void {
    this.ensure(4);
    this.view.setUint32(this.len, v, true);
    this.len += 4;
  }
  i32(v: number): void {
    this.ensure(4);
    this.view.setInt32(this.len, v, true);
    this.len += 4;
  }
  f32(v: number): void {
    this.ensure(4);
    this.view.setFloat32(this.len, v, true);
    this.len += 4;
  }
  bool(v: boolean): void {
    this.u8(v ? 1 : 0);
  }
  string(v: string): void {
    this.bytes(encoder.encode(v));
  }
  bytes(v: Uint8Array): void {
    if (v.length > 65535) throw new Error("byte field too long");
    this.u16(v.length);
    this.ensure(v.length);
    this.buf.set(v, this.len);
    this.len += v.length;
  }
  pos(v: Vec3): void {
    this.i32(clamp(qround(v.x * 1000), -2147483648, 2147483647));
    this.i32(clamp(qround(v.y * 1000), -2147483648, 2147483647));
    this.i32(clamp(qround(v.z * 1000), -2147483648, 2147483647));
  }
  vel(v: Vec3): void {
    this.i16(clamp(qround(v.x * 1000), -32767, 32767));
    this.i16(clamp(qround(v.y * 1000), -32767, 32767));
    this.i16(clamp(qround(v.z * 1000), -32767, 32767));
  }
  angle(rad: number): void {
    this.u16(quantizeAngle(rad));
  }
  arrayLen(n: number, max: number): void {
    if (n > max) throw new Error(`array length ${n} exceeds max ${max}`);
    this.u16(n);
  }
  finish(): Uint8Array {
    const out = this.buf.slice(0, this.len);
    this.len = 0;
    return out;
  }
}

export class Reader {
  private readonly view: DataView;
  private off = 0;
  constructor(private readonly buf: Uint8Array) {
    this.view = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  }
  private need(n: number): number {
    if (this.off + n > this.buf.length) throw new Error("message truncated");
    const at = this.off;
    this.off += n;
    return at;
  }
  u8(): number {
    return this.view.getUint8(this.need(1));
  }
  i8(): number {
    return this.view.getInt8(this.need(1));
  }
  u16(): number {
    return this.view.getUint16(this.need(2), true);
  }
  i16(): number {
    return this.view.getInt16(this.need(2), true);
  }
  u32(): number {
    return this.view.getUint32(this.need(4), true);
  }
  i32(): number {
    return this.view.getInt32(this.need(4), true);
  }
  f32(): number {
    return this.view.getFloat32(this.need(4), true);
  }
  bool(): boolean {
    return this.u8() !== 0;
  }
  bytes(): Uint8Array {
    const n = this.u16();
    const at = this.need(n);
    return this.buf.slice(at, at + n);
  }
  string(): string {
    return decoder.decode(this.bytes());
  }
  pos(): Vec3 {
    return { x: this.i32() / 1000, y: this.i32() / 1000, z: this.i32() / 1000 };
  }
  vel(): Vec3 {
    return { x: this.i16() / 1000, y: this.i16() / 1000, z: this.i16() / 1000 };
  }
  angle(): number {
    return dequantizeAngle(this.u16());
  }
  arrayLen(max: number): number {
    const n = this.u16();
    if (n > max) throw new Error(`array length ${n} exceeds max ${max}`);
    return n;
  }
  expectEnd(): void {
    if (this.off !== this.buf.length) throw new Error("trailing bytes in message");
  }
}
