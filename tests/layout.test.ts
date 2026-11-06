// The chrome layout, from outline rings to the mesh the renderers draw.
import { expect, test } from 'bun:test';
import { layout } from '../web/chrome/layout';

const square = (x: number, y: number, s: number) => Float64Array.from([x, y, x + s, y, x + s, y + s, x, y + s]);

test('outlines that touch at a point still triangulate', () => {
  // Both squares have a corner at the origin, so that point is given twice.
  const l = layout([square(-0.5, -0.5, 0.5), square(0, 0, 0.5)]);
  expect(l.triangles.length).toBeGreaterThan(0);
  expect(l.triangles.every((i) => i < l.x.length)).toBe(true);
}, 10_000);
