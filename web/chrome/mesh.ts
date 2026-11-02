// Layout + settings → vertex positions and normals: the front face, its mirror on the back,
// and the side wall around every loop of the outline. Only positions and normals depend on the
// settings, so changing a setting rewrites two arrays and keeps the triangles.

import { bevel, dome } from './bevel';
import type { Layout } from './layout';
import type { ChromeSettings } from './settings';

function wallCount(l: Layout) {
  let n = 0;
  for (let i = 1; i < l.loops.length; i += 2) n += l.loops[i];
  return n;
}

export function triangles(l: Layout): Uint32Array {
  const n = l.x.length, front = l.triangles.length;
  const index = new Uint32Array(front * 2 + wallCount(l) * 6);
  index.set(l.triangles);
  for (let t = 0; t < front; t += 3) {
    index[front + t] = l.triangles[t] + n;
    index[front + t + 1] = l.triangles[t + 2] + n;
    index[front + t + 2] = l.triangles[t + 1] + n;
  }
  // Walls: each outline point gets a top and a bottom vertex after the two faces.
  let at = front * 2, base = 2 * n;
  for (let i = 0; i < l.loops.length; i += 2) {
    const count = l.loops[i + 1];
    for (let k = 0; k < count; k++) {
      const top = base + 2 * k, bottom = top + 1;
      const k2 = (k + 1) % count;
      const top2 = base + 2 * k2, bottom2 = top2 + 1;
      // The filled side is on the left of the loop, so outward is on the right.
      index.set([top, bottom, top2, bottom, bottom2, top2], at);
      at += 6;
    }
    base += 2 * count;
  }
  return index;
}

export function shape(l: Layout, s: ChromeSettings, position?: Float32Array, normal?: Float32Array) {
  const n = l.x.length, size = (2 * n + 2 * wallCount(l)) * 3;
  position ??= new Float32Array(size);
  normal ??= new Float32Array(size);
  for (let i = 0; i < n; i++) {
    const [h, across, up] = bevel(l.d[i], s);
    const [lift, dx, dy] = dome(l.u[i], l.ux[i], l.uy[i], s);
    // Slopes add: the normal is the bevel's, leaned by the dome's slope.
    const nx = -across * l.gx[i] - up * dx, ny = -across * l.gy[i] - up * dy;
    const len = Math.hypot(nx, ny, up) || 1;
    const z = h + lift;
    position.set([l.x[i], l.y[i], z], 3 * i);
    normal.set([nx / len, ny / len, up / len], 3 * i);
    position.set([l.x[i], l.y[i], -z], 3 * (n + i));
    normal.set([nx / len, ny / len, -up / len], 3 * (n + i));
  }
  const wall = bevel(0, s)[0];
  let at = 2 * n;
  for (let i = 0; i < l.loops.length; i += 2) {
    const start = l.loops[i], count = l.loops[i + 1];
    for (let k = 0; k < count; k++) {
      const p = start + k;
      for (const z of [wall, -wall]) {
        position.set([l.x[p], l.y[p], z], 3 * at);
        normal.set([-l.gx[p], -l.gy[p], 0], 3 * at);
        at++;
      }
    }
  }
  return { position, normal };
}

/** Per vertex: distance inside the outline, inward direction, and which face (1 front, -1 back, 0 wall).
 *  The renderer's shader evaluates the bevel per pixel from these, so shading never shows facets. */
export function bevelAttribute(l: Layout): Float32Array {
  const n = l.x.length;
  const out = new Float32Array((2 * n + 2 * wallCount(l)) * 4);
  for (let i = 0; i < n; i++) {
    out.set([l.d[i], l.gx[i], l.gy[i], 1], 4 * i);
    out.set([l.d[i], l.gx[i], l.gy[i], -1], 4 * (n + i));
  }
  let at = 2 * n;
  for (let i = 0; i < l.loops.length; i += 2)
    for (let k = 0; k < l.loops[i + 1]; k++) {
      const p = l.loops[i] + k;
      out.set([0, l.gx[p], l.gy[p], 0], 4 * at++);
      out.set([0, l.gx[p], l.gy[p], 0], 4 * at++);
    }
  return out;
}
