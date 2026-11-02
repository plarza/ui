// Builds layouts off the main thread; the outline is parsed on the main thread, which has DOMParser.
import { layout } from './layout';
import type { Ring } from './outline';

self.onmessage = (e: MessageEvent<{ id: number; outline: Ring[] }>) => {
  try {
    const l = layout(e.data.outline);
    postMessage({ id: e.data.id, layout: l }, { transfer: [l.x, l.y, l.d, l.gx, l.gy, l.u, l.ux, l.uy, l.field, l.triangles, l.loops].map((a) => a.buffer) });
  } catch (error) {
    postMessage({ id: e.data.id, error: String(error) });
  }
};
