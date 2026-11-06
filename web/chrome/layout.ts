// Outline → the flat layout of the front face: points on rings that follow the outline inward
// (so the bevel's curves land on vertices), a sparser grid across the face, and their triangles.
// Each point keeps its distance from the outline and the inward direction there, so any bevel
// can be applied later without triangulating again. The back face mirrors the front.

import Constrainautor from '@kninnug/constrainautor';
import { EndType, inflatePaths, JoinType } from 'clipper2-ts';
import Delaunator from 'delaunator';
import { reach } from './bevel';
import { densify, fromPaths, scale, toPaths, type Ring } from './outline';

export interface Layout {
  /** Per point: x, y, distance inside the outline, inward unit direction (gx, gy). */
  x: Float32Array;
  y: Float32Array;
  d: Float32Array;
  gx: Float32Array;
  gy: Float32Array;
  /** Per point: the outline inflated like a membrane (u) and its slope (ux, uy). The face dome is
   *  shaped from this, which curves smoothly where distance would crease down each stroke. */
  u: Float32Array;
  ux: Float32Array;
  uy: Float32Array;
  /** The inflation on a fieldSize² grid over [fieldLo, fieldLo + fieldSpan]², as RGBA (u, ux, uy, 0),
   *  so a renderer can read the dome's slope for each pixel instead of blending it across triangles. */
  field: Float32Array;
  fieldSize: number;
  /** Front-face triangles, counter-clockwise seen from the front. */
  triangles: Uint32Array;
  /** The outline: [start, count] runs of points, in order, filled side on the left. */
  loops: Uint32Array;
}

const rings = 40;
/** Longest edge along a ring; rings are simplified as far as their neighbours allow. */
const ringSpacing = 0.0045;
const gridSpacing = 0.006;

export function layout(outline: Ring[]): Layout {
  const index = new Segments(outline);
  const xs: number[] = [], ys: number[] = [], ds: number[] = [], gxs: number[] = [], gys: number[] = [];
  const loops: number[] = [];

  // The outline itself, with its inward normals.
  for (const ring of outline) {
    const n = ring.length / 2;
    loops.push(xs.length, n);
    const first = xs.length;
    for (let i = 0; i < n; i++) {
      const [nx, ny] = leftNormal(ring, i);
      xs.push(ring[2 * i]); ys.push(ring[2 * i + 1]); ds.push(0); gxs.push(nx); gys.push(ny);
    }
    // Clipper keeps the filled side on the left; check rather than trust it.
    if (!index.inside(xs[first] + gxs[first] * 1e-4, ys[first] + gys[first] * 1e-4))
      for (let i = first; i < xs.length; i++) { gxs[i] = -gxs[i]; gys[i] = -gys[i]; }
  }

  const add = (x: number, y: number) => {
    const [d, gx, gy] = index.nearest(x, y);
    xs.push(x); ys.push(y); ds.push(d); gxs.push(gx); gys.push(gy);
    return xs.length - 1;
  };

  // Rings inward, closer together near the edge where the rim curves fastest. Each ring is an
  // exact offset of the outline, simplified only as far as keeps it clear of its neighbours,
  // and is a constraint: triangles then run ring to ring, so the bevel never zigzags.
  const edges: [number, number][] = [];
  for (let i = 0; i < loops.length; i += 2)
    for (let k = 0; k < loops[i + 1]; k++) edges.push([loops[i] + k, loops[i] + ((k + 1) % loops[i + 1])]);
  // Points added along straight runs don't change an offset; leaving them out keeps Clipper fast.
  const paths = toPaths(outline.map((ring) => simplify(ring, 2e-6)));
  const at = (k: number) => reach * (k / rings) ** 2;
  for (let k = 1; k <= rings; k++) {
    const d = at(k);
    const out = inflatePaths(paths, -d * scale, JoinType.Round, EndType.Polygon, 2, Math.min(0.00002, d / 4) * scale);
    const tolerance = 0.2 * Math.min(d - at(k - 1), at(k + 1) - d);
    for (const ring of fromPaths(out)) {
      const simple = densify(simplify(ring, tolerance), ringSpacing);
      if (simple.length < 6) continue;
      const first = xs.length, n = simple.length / 2;
      for (let i = 0; i < simple.length; i += 2) add(simple[i], simple[i + 1]);
      for (let i = 0; i < n; i++) edges.push([first + i, first + ((i + 1) % n)]);
    }
  }

  // The face beyond the rings: a triangular grid.
  const rowStep = (gridSpacing * Math.sqrt(3)) / 2;
  for (let row = 0, y = -0.5; y <= 0.5; row++, y += rowStep) {
    for (let x = -0.5 + (row % 2) * (gridSpacing / 2); x <= 0.5; x += gridSpacing) {
      if (!index.inside(x, y)) continue;
      const [d] = index.nearest(x, y);
      if (d > reach + gridSpacing / 2) add(x, y);
    }
  }

  // Triangulate everything, then keep the triangles inside the outline.
  const coords = new Float64Array(xs.length * 2);
  for (let i = 0; i < xs.length; i++) { coords[2 * i] = xs[i]; coords[2 * i + 1] = ys[i]; }
  const delaunay = new Delaunator(coords);
  const constrain = new Constrainautor(delaunay);
  // Most ring edges are already in the triangulation: lock those directly, since constrainOne
  // rescans every edge after each call, then constrain the few that are missing.
  const missing: [number, number][] = [];
  const c = constrain as unknown as { findEdge(a: number, b: number): number; protect(edge: number): void };
  // Delaunator leaves out a point that repeats another (rings of separate shapes can meet), and
  // findEdge never returns for a point it left out: such edges use the copy it kept, or are
  // dropped when it kept none.
  const left = constrain.untriangulatedPoints();
  const twin = twins(left, xs, ys), out = new Set(left);
  for (let [a, b] of edges) {
    a = twin.get(a) ?? a; b = twin.get(b) ?? b;
    if (a === b || out.has(a) || out.has(b)) continue;
    const edge = c.findEdge(a, b);
    // findEdge: an edge index, minus one on the hull, or Infinity when there is no edge.
    if (Number.isFinite(edge)) c.protect(Math.abs(edge));
    else missing.push([a, b]);
  }
  for (const [a, b] of missing) {
    try { constrain.constrainOne(a, b); } catch { /* an edge through a point: leave it unconstrained */ }
  }
  const all = delaunay.triangles;
  const kept: number[] = [];
  for (let t = 0; t < all.length; t += 3) {
    const a = all[t], b = all[t + 1], c = all[t + 2];
    const cx = (xs[a] + xs[b] + xs[c]) / 3, cy = (ys[a] + ys[b] + ys[c]) / 3;
    if (!index.inside(cx, cy)) continue;
    const area = (xs[b] - xs[a]) * (ys[c] - ys[a]) - (xs[c] - xs[a]) * (ys[b] - ys[a]);
    if (area > 0) kept.push(a, b, c);
    else if (area < 0) kept.push(a, c, b);
  }

  const [u, ux, uy, field, fieldSize] = inflate(index, xs, ys);
  return {
    x: Float32Array.from(xs), y: Float32Array.from(ys), d: Float32Array.from(ds),
    gx: Float32Array.from(gxs), gy: Float32Array.from(gys), u, ux, uy, field, fieldSize,
    triangles: Uint32Array.from(kept), loops: Uint32Array.from(loops),
  };
}

/**
 * Poisson's equation ∇²u = -1 inside the outline with u = 0 on it: the height of a membrane
 * blown up from below. Solved on grids from coarse to fine (each starts from the last), then
 * sampled with its slope at every point.
 */
export const fieldLo = -0.52, fieldSpan = 1.04;

function inflate(index: Segments, xs: number[], ys: number[]): [Float32Array, Float32Array, Float32Array, Float32Array, number] {
  const lo = fieldLo, span = fieldSpan;
  let size = 0, grid = new Float64Array(0);
  for (const [n, sweeps] of [[64, 400], [128, 200], [256, 100], [512, 60], [1024, 30]]) {
    const h = span / n;
    const inside = new Uint8Array(n * n);
    for (let j = 0; j < n; j++) index.fillRow(lo + (j + 0.5) * h, lo, h, inside.subarray(j * n, (j + 1) * n));
    const next = new Float64Array(n * n);
    if (size) for (let j = 0; j < n; j++) for (let i = 0; i < n; i++)
      if (inside[j * n + i]) next[j * n + i] = sample(grid, size, (i + 0.5) / 2 - 0.5, (j + 0.5) / 2 - 0.5);
    const h2 = h * h;
    for (let sweep = 0; sweep < sweeps; sweep++) for (let colour = 0; colour < 2; colour++)
      for (let j = 1; j < n - 1; j++) for (let i = 1 + ((j + colour) & 1); i < n - 1; i += 2) {
        const k = j * n + i;
        if (!inside[k]) continue;
        const target = (next[k - 1] + next[k + 1] + next[k - n] + next[k + n] + h2) / 4;
        next[k] += 1.9 * (target - next[k]);
      }
    size = n;
    grid = next;
  }
  const h = span / size;
  const u = new Float32Array(xs.length), ux = new Float32Array(xs.length), uy = new Float32Array(xs.length);
  for (let p = 0; p < xs.length; p++) {
    const gi = (xs[p] - lo) / h - 0.5, gj = (ys[p] - lo) / h - 0.5;
    u[p] = Math.max(0, sample(grid, size, gi, gj));
    ux[p] = (sample(grid, size, gi + 1, gj) - sample(grid, size, gi - 1, gj)) / (2 * h);
    uy[p] = (sample(grid, size, gi, gj + 1) - sample(grid, size, gi, gj - 1)) / (2 * h);
  }
  const field = new Float32Array(size * size * 4);
  for (let j = 0; j < size; j++) for (let i = 0; i < size; i++) {
    const k = j * size + i;
    field[4 * k] = grid[k];
    field[4 * k + 1] = (sample(grid, size, i + 1, j) - sample(grid, size, i - 1, j)) / (2 * h);
    field[4 * k + 2] = (sample(grid, size, i, j + 1) - sample(grid, size, i, j - 1)) / (2 * h);
  }
  return [u, ux, uy, field, size];
}

/** Bilinear sample of an n × n grid at fractional cell (i, j). */
function sample(grid: Float64Array, n: number, i: number, j: number) {
  i = Math.min(Math.max(i, 0), n - 1.001); j = Math.min(Math.max(j, 0), n - 1.001);
  const i0 = Math.floor(i), j0 = Math.floor(j), fi = i - i0, fj = j - j0;
  const k = j0 * n + i0;
  return (grid[k] * (1 - fi) + grid[k + 1] * fi) * (1 - fj) + (grid[k + n] * (1 - fi) + grid[k + n + 1] * fi) * fj;
}

/** For each point left out of the triangulation, a point at the same place that is in it. */
function twins(left: number[], xs: number[], ys: number[]): Map<number, number> {
  const twin = new Map<number, number>();
  if (!left.length) return twin;
  const out = new Set(left);
  const at = new Map<string, number[]>();
  for (const i of left) push(at, `${xs[i]},${ys[i]}`, i);
  for (let i = 0; i < xs.length; i++) {
    if (out.has(i)) continue;
    const copies = at.get(`${xs[i]},${ys[i]}`);
    if (copies) for (const k of copies) twin.set(k, i);
  }
  return twin;
}

/** Douglas–Peucker on a closed ring: drops points while the ring stays within `tolerance`. */
function simplify(ring: Ring, tolerance: number): Ring {
  const n = ring.length / 2;
  if (n < 8) return ring;
  const keep = new Uint8Array(n + 1);
  keep[0] = keep[n >> 1] = keep[n] = 1;
  const x = (i: number) => ring[2 * (i % n)], y = (i: number) => ring[2 * (i % n) + 1];
  const stack: [number, number][] = [[0, n >> 1], [n >> 1, n]];
  while (stack.length) {
    const [a, b] = stack.pop()!;
    const ex = x(b) - x(a), ey = y(b) - y(a), len = Math.hypot(ex, ey) || 1;
    let worst = -1, far = 0;
    for (let i = a + 1; i < b; i++) {
      const dist = Math.abs((x(i) - x(a)) * ey - (y(i) - y(a)) * ex) / len;
      if (dist > far) { far = dist; worst = i; }
    }
    if (far > tolerance) { keep[worst] = 1; stack.push([a, worst], [worst, b]); }
  }
  const out: number[] = [];
  for (let i = 0; i < n; i++) if (keep[i]) out.push(x(i), y(i));
  return new Float64Array(out);
}

/** Unit normal to the left of the outline at point i, averaged over its two edges. */
function leftNormal(ring: Ring, i: number): [number, number] {
  const n = ring.length / 2;
  const p = (i + n - 1) % n, q = (i + 1) % n;
  let ax = ring[2 * i] - ring[2 * p], ay = ring[2 * i + 1] - ring[2 * p + 1];
  let bx = ring[2 * q] - ring[2 * i], by = ring[2 * q + 1] - ring[2 * i + 1];
  const la = Math.hypot(ax, ay) || 1, lb = Math.hypot(bx, by) || 1;
  const nx = -ay / la - by / lb, ny = ax / la + bx / lb;
  const l = Math.hypot(nx, ny) || 1;
  return [nx / l, ny / l];
}

/** The outline's edges, bucketed for nearest-point and inside queries. */
class Segments {
  private seg: Float64Array;
  private cells = new Map<number, number[]>();
  private rows = new Map<number, number[]>();
  private cell = 0.01;
  private row = 0.004;

  constructor(outline: Ring[]) {
    const s: number[] = [];
    for (const ring of outline) {
      const n = ring.length / 2;
      for (let i = 0; i < n; i++) {
        const j = (i + 1) % n;
        s.push(ring[2 * i], ring[2 * i + 1], ring[2 * j], ring[2 * j + 1]);
      }
    }
    this.seg = Float64Array.from(s);
    for (let k = 0; k < s.length / 4; k++) {
      const [ax, ay, bx, by] = s.slice(4 * k, 4 * k + 4);
      for (let cx = Math.floor(Math.min(ax, bx) / this.cell); cx <= Math.floor(Math.max(ax, bx) / this.cell); cx++)
        for (let cy = Math.floor(Math.min(ay, by) / this.cell); cy <= Math.floor(Math.max(ay, by) / this.cell); cy++)
          push(this.cells, key(cx, cy), k);
      for (let r = Math.floor(Math.min(ay, by) / this.row); r <= Math.floor(Math.max(ay, by) / this.row); r++)
        push(this.rows, r, k);
    }
  }

  /** Even-odd test against the outline. */
  inside(x: number, y: number): boolean {
    const list = this.rows.get(Math.floor(y / this.row));
    if (!list) return false;
    let inside = false;
    for (const k of list) {
      const ay = this.seg[4 * k + 1], by = this.seg[4 * k + 3];
      if (ay > y === by > y) continue;
      const ax = this.seg[4 * k], bx = this.seg[4 * k + 2];
      if (ax + ((y - ay) * (bx - ax)) / (by - ay) > x) inside = !inside;
    }
    return inside;
  }

  /** Marks the cells of one grid row (centres at lo + (i + 0.5) h) that are inside, even-odd. */
  fillRow(y: number, lo: number, h: number, out: Uint8Array) {
    const list = this.rows.get(Math.floor(y / this.row));
    if (!list) return;
    const xs: number[] = [];
    for (const k of list) {
      const ay = this.seg[4 * k + 1], by = this.seg[4 * k + 3];
      if (ay > y === by > y) continue;
      const ax = this.seg[4 * k], bx = this.seg[4 * k + 2];
      xs.push(ax + ((y - ay) * (bx - ax)) / (by - ay));
    }
    xs.sort((a, b) => a - b);
    for (let p = 0; p + 1 < xs.length; p += 2) {
      const from = Math.max(0, Math.ceil((xs[p] - lo) / h - 0.5)), to = Math.min(out.length - 1, Math.floor((xs[p + 1] - lo) / h - 0.5));
      for (let i = from; i <= to; i++) out[i] = 1;
    }
  }

  /** Distance to the outline and the unit direction away from its nearest point. */
  nearest(x: number, y: number): [number, number, number] {
    const cx = Math.floor(x / this.cell), cy = Math.floor(y / this.cell);
    let best = Infinity, px = x, py = y;
    for (let r = 0; r < 200; r++) {
      for (let i = -r; i <= r; i++) for (let j = -r; j <= r; j++) {
        if (Math.max(Math.abs(i), Math.abs(j)) !== r) continue;
        const list = this.cells.get(key(cx + i, cy + j));
        if (!list) continue;
        for (const k of list) {
          const ax = this.seg[4 * k], ay = this.seg[4 * k + 1], bx = this.seg[4 * k + 2], by = this.seg[4 * k + 3];
          const ex = bx - ax, ey = by - ay;
          const t = Math.max(0, Math.min(1, ((x - ax) * ex + (y - ay) * ey) / (ex * ex + ey * ey || 1)));
          const qx = ax + ex * t, qy = ay + ey * t;
          const dd = (x - qx) ** 2 + (y - qy) ** 2;
          if (dd < best) { best = dd; px = qx; py = qy; }
        }
      }
      if (Math.sqrt(best) <= r * this.cell) break;
    }
    const d = Math.sqrt(best);
    return d > 0 ? [d, (x - px) / d, (y - py) / d] : [0, 0, 0];
  }
}

const key = (x: number, y: number) => (x + 1000) * 4096 + (y + 1000);
function push<K>(map: Map<K, number[]>, k: K, v: number) {
  const list = map.get(k);
  if (list) list.push(v); else map.set(k, [v]);
}

// The .chromelayout file: what the CLI writes and AzaUI's ChromeMesh.swift reads. It leaves out
// the field: AzaUI shades per vertex.
// Little-endian: "AZCL", version 2, point count, triangle count, loop count,
// then loops (start, count), x, y, d, gx, gy, u, ux, uy as Float32, triangles as UInt32.

export function encode(l: Layout): Uint8Array {
  const n = l.x.length, t = l.triangles.length / 3, loops = l.loops.length / 2;
  const buf = new ArrayBuffer(20 + loops * 8 + n * 32 + t * 12);
  const v = new DataView(buf);
  [0x4c435a41, 2, n, t, loops].forEach((x, i) => v.setUint32(i * 4, x, true));
  let at = 20;
  for (const x of l.loops) { v.setUint32(at, x, true); at += 4; }
  for (const arr of [l.x, l.y, l.d, l.gx, l.gy, l.u, l.ux, l.uy]) for (const x of arr) { v.setFloat32(at, x, true); at += 4; }
  for (const x of l.triangles) { v.setUint32(at, x, true); at += 4; }
  return new Uint8Array(buf);
}
