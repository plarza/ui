// The cross-section of the front face, as a function of the distance d from the outline inward:
// a rounded rim off the side wall, a flat rim top, its inner side rounding down into a groove,
// a bevel down (or up) to the face, then the face.
// The dome then lifts the whole front smoothly; see `dome`.
// AzaUI's ChromeMesh.swift mirrors this function; change both together.

import type { ChromeSettings } from './settings';

/** How far the bevel can reach inward; the layout places rings up to here. */
export const reach = 0.07;

/** The dome's height grows with the square root of inflation (see layout.ts), which curves each
 *  stroke like a cushion across its whole width: a strip's inflation is parabolic across it, so its
 *  square root is an arc. `domeSoft` rounds off the arc's vertical start at the outline, and
 *  `domeUnit` is the inflation at which the height equals the Face dome setting. */
export const domeSoft = 0.0001;
export const domeUnit = 0.001;

/**
 * Height of the front face at distance `d` inside the outline, and the slope as a unit vector:
 * `[z, across, up]`, where the normal is `-across` along the inward direction plus `up` along +z.
 */
export function bevel(d: number, s: ChromeSettings): [number, number, number] {
  const top = s.depth / 2;
  const r = Math.min(s.rimRadius, top);
  if (d < r) {
    const x = r - d;
    const y = Math.sqrt(Math.max(r * r - x * x, 0));
    return [top - r + y, x / r, y / r];
  }
  let at = d - r;
  if (at < s.rimWidth) return [top, 0, 1];
  at -= s.rimWidth;
  // The rim's inner side rounds down into the groove: a quarter circle as deep as it is wide.
  const g = s.groove;
  if (at < g) {
    const y = Math.sqrt(Math.max(g * g - at * at, 0));
    return [top - g + y, -at / g, y / g];
  }
  at -= g;
  const k = 1 + s.bevelCurve;
  if (at < s.bevelWidth) {
    const t = at / s.bevelWidth;
    const fall = s.recess - g;
    const slope = (-fall * k * Math.pow(t, k - 1)) / s.bevelWidth;
    return [top - g - fall * Math.pow(t, k), ...unit(slope)];
  }
  return [top - s.recess, 0, 1];
}

/**
 * The face dome at inflation `u` with slope (ux, uy): `[height, dz/dx, dz/dy]`. It rises over the
 * whole front, bevel included, and is zero on the outline.
 */
export function dome(u: number, ux: number, uy: number, s: ChromeSettings): [number, number, number] {
  const k = s.dome / Math.sqrt(domeUnit);
  const lean = k / (2 * Math.sqrt(u + domeSoft));
  return [k * (Math.sqrt(u + domeSoft) - Math.sqrt(domeSoft)), lean * ux, lean * uy];
}

function unit(slope: number): [number, number] {
  const n = Math.hypot(slope, 1);
  return [slope / n, 1 / n];
}
