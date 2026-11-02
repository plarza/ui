#!/usr/bin/env bun
// Rebuilds Sources/AzaUI/Resources/Studios/*.avif, the one copy AzaUI and the web code both read:
// downloads each studio's 2k panorama from Poly Haven, turns it grey and to its angle, and stores
// log brightness as an 8-bit grey AVIF (see chrome/studio.ts).

import { mkdirSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { fromHdr, logPixels } from './chrome/studio';
import { studios } from './chrome/studios';

const work = mkdtempSync(join(tmpdir(), 'studios-'));
mkdirSync(dirname(fileURLToPath(studios.monochrome.url)), { recursive: true });

for (const [name, { source, angle, url }] of Object.entries(studios)) {
  const response = await fetch(`https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/2k/${source}_2k.hdr`);
  if (!response.ok) throw new Error(`${source}: ${response.status}`);
  const studio = fromHdr(await response.arrayBuffer());
  const width = 2048, height = 1024;
  const raw = join(work, `${name}.gray`), png = join(work, `${name}.png`), avif = fileURLToPath(url);
  await Bun.write(raw, logPixels(studio, angle, width));
  await run(['ffmpeg', '-loglevel', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'gray', '-s', `${width}x${height}`, '-i', raw, png]);
  await run(['avifenc', '-q', '50', '--yuv', '400', '-s', '2', png, avif]);
  console.log(`${avif}  ${(Bun.file(avif).size / 1024).toFixed(0)} KB`);
}

async function run(cmd: string[]) {
  const p = Bun.spawn(cmd, { stdout: 'ignore', stderr: 'inherit' });
  if ((await p.exited) !== 0) throw new Error(`${cmd[0]} failed`);
}
