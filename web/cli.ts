#!/usr/bin/env bun
// chrome-logo: an SVG in, the chrome logo out as a still, videos, a .glb, and the layout that
// AzaUI's ChromeLogo reads. Rendering happens in headless Chromium with the same
// scene the Svelte component uses.

import { deflateRawSync } from 'node:zlib';
import { mkdirSync } from 'node:fs';
import { basename, extname, join, resolve as resolvePath } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { chromium } from 'playwright';
import * as THREE from 'three';
import { resolve, settings, type ChromeSettings, type SettingName } from './chrome/settings';
import { defaultStudio, studios, type StudioName } from './chrome/studios';

const outputs = ['png', 'video', 'glb', 'layout'] as const;
const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    out: { type: 'string', default: '.' },
    only: { type: 'string', default: outputs.join(',') },
    size: { type: 'string', default: '1080' },
    fps: { type: 'string', default: '60' },
    seconds: { type: 'string', default: '6' },
    motion: { type: 'string', default: 'sway' },
    studio: { type: 'string' },
    help: { type: 'boolean', short: 'h' },
    ...Object.fromEntries(Object.keys(settings).map((k) => [k, { type: 'string' as const }])),
  },
});

if (values.help || positionals.length !== 1) {
  console.log(`Usage: chrome-logo <file.svg> [options]

  --out <dir>           Where to write (default .)
  --only <list>         Any of ${outputs.join(',')} (default all)
  --size <px>           Square size of the still and videos (default 1080)
  --fps <n>             Video frame rate (default 60)
  --seconds <n>         Video length; it loops seamlessly (default 6)
  --motion sway|spin    Video motion (default sway)
  --studio <name|file>  What the chrome reflects: ${Object.keys(studios).join(', ')}
                        (default ${defaultStudio}), or any equirectangular .hdr panorama

Settings (logo units: the longer side is 1):
${Object.entries(settings).map(([k, s]) => `  --${k.padEnd(20)}${s.label}, ${s.min} to ${s.max} (default ${s.value})`).join('\n')}

Writes <name>.png, <name>.mp4 (on black), <name>.webm (VP9 with alpha),
<name>-hevc.mov (HEVC with alpha, for Apple), <name>-prores.mov (ProRes 4444 with alpha),
<name>.glb and <name>.chromelayout (for AzaUI's ChromeLogo).`);
  process.exit(values.help ? 0 : 1);
}

const file = resolvePath(positionals[0]);
const name = basename(file, extname(file));
const out = resolvePath(values.out!);
const only = new Set(values.only!.split(','));
const size = Number(values.size), fps = Number(values.fps), seconds = Number(values.seconds);
const chosen: Partial<ChromeSettings> = {};
for (const k of Object.keys(settings) as SettingName[]) {
  const v = (values as unknown as Record<string, string | undefined>)[k];
  if (v !== undefined) chosen[k] = Number(v);
}
const s = resolve(chosen);
mkdirSync(out, { recursive: true });
const written: string[] = [];
const write = async (path: string, data: Uint8Array | string) => { await Bun.write(path, data); written.push(path); };

const studio = values.studio ?? defaultStudio;
const studioBytes = await Bun.file(studio in studios ? fileURLToPath(studios[studio as StudioName].url) : resolvePath(studio)).arrayBuffer();

const built = await Bun.build({ entrypoints: [join(import.meta.dir, 'render.ts')], target: 'browser', minify: true });
if (!built.success) throw new AggregateError(built.logs, 'Could not bundle the renderer');
const script = await built.outputs[0].text();

const browser = await chromium.launch({ args: ['--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist'] });
const page = await browser.newPage();
page.on('pageerror', (e) => console.error(e));
await page.setContent(`<canvas></canvas><script type="module">${script.replaceAll('</script', '<\\/script')}</script>`);
await page.waitForFunction(() => (window as any).azaChrome);
const supersample = 3;
const info = await page.evaluate(([svg, s, size, ss, studio]) => (window as any).azaChrome.setup(svg, s, size, ss, studio),
  [await Bun.file(file).text(), s, size, supersample, Buffer.from(studioBytes).toString('base64')] as const);
console.log(`${name}: ${info.points} points, ${info.triangles} triangles per face`);

const frame = async (q: THREE.Quaternion) =>
  Buffer.from(await page.evaluate((r) => (window as any).azaChrome.frame(r), [q.x, q.y, q.z, q.w]), 'base64');

if (only.has('layout'))
  await write(join(out, `${name}.chromelayout`), deflateRawSync(Buffer.from(await page.evaluate(() => (window as any).azaChrome.layout()), 'base64')));
if (only.has('glb'))
  await write(join(out, `${name}.glb`), Buffer.from(await page.evaluate(() => (window as any).azaChrome.glb()), 'base64'));
if (only.has('png')) {
  const pixels = await frame(new THREE.Quaternion());
  await ffmpeg([], ['-frames:v', '1', join(out, `${name}.png`)], pixels);
}
if (only.has('video')) await video(frame);
await browser.close();

for (const path of written) console.log(path);

/** The rotation at time t in [0, 1); both motions loop. */
function motion(t: number) {
  const rad = Math.PI / 180;
  const e = values.motion === 'spin'
    ? new THREE.Euler(0, t * 2 * Math.PI, 0)
    : new THREE.Euler(9 * rad * Math.sin(4 * Math.PI * t), 28 * rad * Math.sin(2 * Math.PI * t), 0, 'YXZ');
  return new THREE.Quaternion().setFromEuler(e);
}

async function video(frame: (q: THREE.Quaternion) => Promise<Buffer>) {
  const black = ['-filter_complex', `color=black:s=${size}x${size}:r=${fps}[bg];[bg][0:v]overlay=shortest=1,format=yuv420p`];
  const encoders = [
    [...black, '-c:v', 'libx264', '-crf', '16', '-preset', 'slow', '-movflags', '+faststart', `${name}.mp4`],
    ['-c:v', 'libvpx-vp9', '-pix_fmt', 'yuva420p', '-b:v', '0', '-crf', '22', '-row-mt', '1', `${name}.webm`],
    ['-c:v', 'hevc_videotoolbox', '-alpha_quality', '0.9', '-q:v', '75', '-tag:v', 'hvc1', '-pix_fmt', 'bgra', `${name}-hevc.mov`],
    ['-c:v', 'prores_ks', '-profile:v', '4444', '-pix_fmt', 'yuva444p10le', '-alpha_bits', '16', `${name}-prores.mov`],
  ].map((args) => {
    const path = join(out, args.pop()!);
    written.push(path);
    return Bun.spawn(['ffmpeg', '-loglevel', 'error', '-y', ...input(), ...args, path], { stdin: 'pipe', stderr: 'inherit' });
  });

  const total = Math.round(fps * seconds);
  const start = performance.now();
  for (let i = 0; i < total; i++) {
    const pixels = await frame(motion(i / total));
    for (const e of encoders) e.stdin.write(pixels);
    progress(i + 1, total, start);
  }
  for (const e of encoders) e.stdin.end();
  const codes = await Promise.all(encoders.map((e) => e.exited));
  process.stderr.write('\n');
  if (codes.some((c) => c !== 0)) throw new Error('ffmpeg failed');
}

function input() {
  return ['-f', 'rawvideo', '-pix_fmt', 'rgba', '-s', `${size}x${size}`, '-r', String(fps), '-i', '-'];
}

async function ffmpeg(before: string[], after: string[], pixels: Buffer) {
  const p = Bun.spawn(['ffmpeg', '-loglevel', 'error', '-y', ...input(), ...before, ...after], { stdin: 'pipe', stderr: 'inherit' });
  p.stdin.write(pixels);
  p.stdin.end();
  if ((await p.exited) !== 0) throw new Error('ffmpeg failed');
  written.push(after[after.length - 1]);
}

function progress(done: number, total: number, start: number) {
  const elapsed = (performance.now() - start) / 1000;
  const rate = done / elapsed;
  const width = 30, filled = Math.round((done / total) * width);
  const eta = (total - done) / rate;
  process.stderr.write(`\r[${'#'.repeat(filled)}${'-'.repeat(width - filled)}] ${done}/${total} frames  ${elapsed.toFixed(0)}s  ${rate.toFixed(1)} fps  ETA ${eta.toFixed(0)}s `);
}
