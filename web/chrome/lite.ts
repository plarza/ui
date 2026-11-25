// The .chromelite file: a layout small enough to load with a page, for the light renderer
// (web/ascii). The CLI writes it (`--only lite`, the coarse density); the browser only decodes it
// and runs the bevel, a few milliseconds, instead of building the layout itself.
//
// Little-endian, deflate-raw compressed: "AZCM", version 1, point count, triangle count, loop
// count; loops (start, count) as UInt32; then field by field, for the compressor: x, y as UInt16
// over [-0.5, 0.5]; d as UInt16 over [0, 0.5]; the inward direction as a UInt16 angle; u, ux, uy
// as Float16; then the triangles, each turned to start at its lowest point and sorted by it: that
// point as a UInt32 step from the last triangle's, the other two as Int32 steps from it, which
// are small, so they compress well.

import type { MeshLayout } from './mesh';

const MAGIC = 0x4d435a41;

export function encodeLite(l: MeshLayout): Uint8Array {
  const n = l.x.length, t = l.triangles.length / 3, loops = l.loops.length / 2;
  const buf = new ArrayBuffer(20 + loops * 8 + n * 14 + t * 12);
  const v = new DataView(buf);
  [MAGIC, 1, n, t, loops].forEach((x, i) => v.setUint32(i * 4, x, true));
  let at = 20;
  for (const x of l.loops) { v.setUint32(at, x, true); at += 4; }
  const u16 = (x: number) => { v.setUint16(at, Math.max(0, Math.min(65535, Math.round(x))), true); at += 2; };
  for (const x of l.x) u16((x + 0.5) * 65535);
  for (const y of l.y) u16((y + 0.5) * 65535);
  for (const d of l.d) u16((d / 0.5) * 65535);
  for (let i = 0; i < n; i++) u16(((Math.atan2(l.gy[i], l.gx[i]) + Math.PI) / (2 * Math.PI)) * 65535);
  for (const a of [l.u, l.ux, l.uy]) for (const x of a) { v.setUint16(at, toHalf(x), true); at += 2; }
  const tris: [number, number, number][] = [];
  for (let i = 0; i < l.triangles.length; i += 3) {
    const [a, b, c] = [l.triangles[i], l.triangles[i + 1], l.triangles[i + 2]];
    // Turning keeps the winding.
    tris.push(a <= b && a <= c ? [a, b, c] : b <= c ? [b, c, a] : [c, a, b]);
  }
  tris.sort((p, q) => p[0] - q[0] || p[1] - q[1]);
  // Field by field again: the steps between first points, then the second and third offsets.
  let last = 0;
  for (const [a] of tris) { v.setUint32(at, a - last, true); at += 4; last = a; }
  for (const k of [1, 2]) for (const tri of tris) { v.setInt32(at, tri[k] - tri[0], true); at += 4; }
  return new Uint8Array(buf);
}

export function decodeLite(bytes: ArrayBuffer): MeshLayout {
  const v = new DataView(bytes);
  if (v.getUint32(0, true) !== MAGIC) throw new Error('not a .chromelite file');
  const n = v.getUint32(8, true), t = v.getUint32(12, true), count = v.getUint32(16, true);
  let at = 20;
  const loops = new Uint32Array(count * 2);
  for (let i = 0; i < loops.length; i++, at += 4) loops[i] = v.getUint32(at, true);
  const read = (f: (raw: number) => number) => { const out = new Float32Array(n); for (let i = 0; i < n; i++, at += 2) out[i] = f(v.getUint16(at, true)); return out; };
  const x = read((r) => r / 65535 - 0.5), y = read((r) => r / 65535 - 0.5), d = read((r) => (r / 65535) * 0.5);
  const angle = read((r) => (r / 65535) * 2 * Math.PI - Math.PI);
  const gx = angle.map(Math.cos), gy = angle.map(Math.sin);
  const u = read(fromHalf), ux = read(fromHalf), uy = read(fromHalf);
  const triangles = new Uint32Array(t * 3);
  let last = 0;
  for (let i = 0; i < t; i++, at += 4) triangles[3 * i] = last += v.getUint32(at, true);
  for (const k of [1, 2]) for (let i = 0; i < t; i++, at += 4) triangles[3 * i + k] = triangles[3 * i] + v.getInt32(at, true);
  return { x, y, d, gx, gy, u, ux, uy, triangles, loops };
}

/** Fetch and decode a .chromelite file. */
export async function loadLite(url: string | URL): Promise<MeshLayout> {
  const response = await fetch(url);
  if (!response.ok || !response.body) throw new Error(`${url}: ${response.status}`);
  return decodeLite(await new Response(response.body.pipeThrough(new DecompressionStream('deflate-raw'))).arrayBuffer());
}

const f32 = new Float32Array(1), u32 = new Uint32Array(f32.buffer);
function toHalf(x: number) {
  f32[0] = x;
  const b = u32[0], sign = (b >>> 16) & 0x8000, e = ((b >>> 23) & 0xff) - 127 + 15, m = b & 0x7fffff;
  if (e <= 0) return sign | (e < -10 ? 0 : (m | 0x800000) >> (14 - e));
  if (e >= 31) return sign | 0x7c00;
  return sign | (e << 10) | (m >> 13);
}
function fromHalf(h: number) {
  const s = h & 0x8000 ? -1 : 1, e = (h >> 10) & 0x1f, m = h & 0x3ff;
  if (e === 0) return s * 2 ** -14 * (m / 1024);
  if (e === 31) return m ? NaN : s * Infinity;
  return s * 2 ** (e - 15) * (1 + m / 1024);
}
