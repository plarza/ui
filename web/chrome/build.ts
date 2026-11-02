// SVG → layout in the browser, in a worker, once per distinct SVG.
import type { Layout } from './layout';
import { outline } from './outline';

const cache = new Map<string, Promise<Layout>>();
let worker: Worker | undefined;
let next = 0;
const waiting = new Map<number, { resolve: (l: Layout) => void; reject: (e: Error) => void }>();

export function build(svg: string): Promise<Layout> {
  let found = cache.get(svg);
  if (!found) {
    found = run(svg);
    cache.set(svg, found);
    found.catch(() => cache.delete(svg));
  }
  return found;
}

async function run(svg: string): Promise<Layout> {
  const rings = outline(svg);
  if (!worker) {
    worker = new Worker(new URL('./worker.ts', import.meta.url), { type: 'module' });
    worker.onmessage = (e) => {
      const w = waiting.get(e.data.id);
      waiting.delete(e.data.id);
      if (e.data.error) w?.reject(new Error(e.data.error));
      else w?.resolve(e.data.layout);
    };
  }
  const id = next++;
  return new Promise((resolve, reject) => {
    waiting.set(id, { resolve, reject });
    worker!.postMessage({ id, outline: rings });
  });
}
