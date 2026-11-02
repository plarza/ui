// SVG → the filled region as clean polygons, in logo units (longer side 1, centred, y up).
// Fills follow their fill rule; strokes become outlines; everything is unioned.

import { area, EndType, FillRule, inflatePaths, JoinType, union, type Path64, type Paths64 } from 'clipper2-ts';
import { SVGLoader } from 'three/examples/jsm/loaders/SVGLoader.js';

export type Ring = Float64Array; // x0, y0, x1, y1, …

/** Clipper works in integers; logo units are scaled by this. */
export const scale = 1e6;
/** Longest edge kept when flattening curves. */
const spacing = 0.0015;

export function outline(svg: string): Ring[] {
  const { paths } = new SVGLoader().parse(svg);

  // Flatten in SVG units first, to find the bounds.
  const parts: { rings: [number, number][][]; closed: boolean[]; style: any }[] = [];
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  for (const path of paths) {
    const rings: [number, number][][] = [];
    const closed: boolean[] = [];
    for (const sub of path.subPaths) {
      const points = sub.getPoints(32).map((p) => [p.x, p.y] as [number, number]);
      if (points.length < 2) continue;
      rings.push(points);
      closed.push(sub.autoClose || near(points[0], points[points.length - 1]));
      for (const [x, y] of points) {
        minX = Math.min(minX, x); maxX = Math.max(maxX, x);
        minY = Math.min(minY, y); maxY = Math.max(maxY, y);
      }
    }
    parts.push({ rings, closed, style: path.userData?.style ?? {} });
  }
  if (!isFinite(minX)) throw new Error('The SVG has no paths');

  // Strokes widen the bounds a little; refine after the union.
  const unit = 1 / Math.max(maxX - minX, maxY - minY);
  const cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
  const toClipper = (ring: [number, number][]) =>
    ring.map(([x, y]) => ({ x: Math.round((x - cx) * unit * scale), y: Math.round(-(y - cy) * unit * scale) }));

  const all: Paths64 = [];
  for (const { rings, closed, style } of parts) {
    if (style.fill !== 'none' && !(style.fillOpacity === 0)) {
      const filled = rings.filter((_, i) => closed[i] || rings[i].length > 2).map(toClipper);
      all.push(...union(filled, style.fillRule === 'evenodd' ? FillRule.EvenOdd : FillRule.NonZero));
    }
    if (style.stroke && style.stroke !== 'none' && style.strokeWidth > 0 && style.strokeOpacity !== 0) {
      const join = { round: JoinType.Round, bevel: JoinType.Bevel }[style.strokeLineJoin as string] ?? JoinType.Miter;
      const cap = { round: EndType.Round, square: EndType.Square }[style.strokeLineCap as string] ?? EndType.Butt;
      const delta = (style.strokeWidth / 2) * unit * scale;
      rings.forEach((ring, i) =>
        all.push(...inflatePaths([toClipper(ring)], delta, join, closed[i] ? EndType.Joined : cap, style.strokeMiterLimit ?? 4, 0.0002 * scale)));
    }
  }

  return normalize(union(all, FillRule.NonZero).filter((r) => Math.abs(area(r)) > 1e-8 * scale * scale));
}

/** Rescale so the longer side is exactly 1 and the bounds are centred. */
function normalize(rings: Paths64): Ring[] {
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  for (const r of rings) for (const p of r) {
    minX = Math.min(minX, p.x); maxX = Math.max(maxX, p.x);
    minY = Math.min(minY, p.y); maxY = Math.max(maxY, p.y);
  }
  const k = 1 / Math.max(maxX - minX, maxY - minY);
  const cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
  return rings.map((r) => {
    const out = new Float64Array(r.length * 2);
    r.forEach((p, i) => { out[2 * i] = (p.x - cx) * k; out[2 * i + 1] = (p.y - cy) * k; });
    return densify(out);
  });
}

/** Rings as Clipper paths, for offsetting. */
export function toPaths(rings: Ring[]): Paths64 {
  return rings.map((r) => {
    const out: Path64 = [];
    for (let i = 0; i < r.length; i += 2) out.push({ x: Math.round(r[i] * scale), y: Math.round(r[i + 1] * scale) });
    return out;
  });
}

export function fromPaths(paths: Paths64): Ring[] {
  return paths.map((p) => {
    const out = new Float64Array(p.length * 2);
    p.forEach((q, i) => { out[2 * i] = q.x / scale; out[2 * i + 1] = q.y / scale; });
    return out;
  });
}

/** Adds points so no edge is longer than `max`. */
export function densify(ring: Ring, max = spacing): Ring {
  const out: number[] = [];
  const n = ring.length / 2;
  for (let i = 0; i < n; i++) {
    const ax = ring[2 * i], ay = ring[2 * i + 1];
    const bx = ring[(2 * i + 2) % ring.length], by = ring[(2 * i + 3) % ring.length];
    out.push(ax, ay);
    const extra = Math.floor(Math.hypot(bx - ax, by - ay) / max);
    for (let k = 1; k <= extra; k++) {
      const t = k / (extra + 1);
      out.push(ax + (bx - ax) * t, ay + (by - ay) * t);
    }
  }
  return new Float64Array(out);
}

function near(a: [number, number], b: [number, number]) {
  return Math.abs(a[0] - b[0]) < 1e-9 && Math.abs(a[1] - b[1]) < 1e-9;
}
