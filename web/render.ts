// Runs inside headless Chromium for the CLI: builds the logo once, then hands back frames,
// the layout and a .glb on request.

import * as THREE from 'three';
import { GLTFExporter } from 'three/examples/jsm/exporters/GLTFExporter.js';
import { encode, layout as makeLayout, type Layout } from './chrome/layout';
import { outline } from './chrome/outline';
import { ChromeScene } from './chrome/scene';
import type { ChromeSettings } from './chrome/settings';
import { load } from './chrome/studio';

let scene: ChromeScene;
let layout: Layout;
let size = 0, supersample = 1;

const base64 = (bytes: Uint8Array) => {
  let s = '';
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s);
};

(window as any).azaChrome = {
  async setup(svg: string, settings: ChromeSettings, px: number, ss: number, studio: string) {
    size = px; supersample = ss;
    const canvas = document.querySelector('canvas')!;
    scene = new ChromeScene(canvas, { preserveDrawingBuffer: true });
    scene.setStudio(await load(Uint8Array.from(atob(studio), (c) => c.charCodeAt(0)).buffer));
    layout = makeLayout(outline(svg));
    scene.setLayout(layout);
    scene.setSettings(settings);
    // No more supersampling than the GPU can draw: past its largest canvas it draws only a corner.
    const gl = scene.renderer.getContext();
    const most = Math.min(gl.getParameter(gl.MAX_RENDERBUFFER_SIZE), gl.getParameter(gl.MAX_VIEWPORT_DIMS)[0]);
    supersample = Math.max(1, Math.min(ss, Math.floor(most / size)));
    scene.resize(size * supersample, size * supersample, 1);
    return { points: layout.x.length, triangles: layout.triangles.length / 3, supersample };
  },

  /**
   * One frame as straight-alpha RGBA, top row first, base64. A video's frames are drawn larger and
   * averaged down; a still is drawn at its size and averaged from many frames, offset within a
   * pixel, which smooths the mirror's highlights that a larger frame alone leaves stepped.
   */
  frame(rotation: [number, number, number, number], still = false) {
    scene.setMotion(new THREE.Quaternion(...rotation));
    const ss = still ? 1 : supersample;
    scene.resize(size * ss, size * ss, 1);
    scene.render();
    if (still) while (scene.refine());
    const gl = scene.renderer.getContext();
    const big = size * ss;
    const raw = new Uint8Array(big * big * 4);
    gl.readPixels(0, 0, big, big, gl.RGBA, gl.UNSIGNED_BYTE, raw);
    const out = new Uint8Array(size * size * 4);
    const n = ss * ss;
    for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
      // Average premultiplied samples, then divide out alpha.
      let r = 0, g = 0, b = 0, a = 0;
      for (let j = 0; j < ss; j++) for (let i = 0; i < ss; i++) {
        const k = ((big - 1 - (y * ss + j)) * big + x * ss + i) * 4;
        r += raw[k]; g += raw[k + 1]; b += raw[k + 2]; a += raw[k + 3];
      }
      const o = (y * size + x) * 4;
      if (a > 0) { out[o] = Math.min(255, (r * 255) / a); out[o + 1] = Math.min(255, (g * 255) / a); out[o + 2] = Math.min(255, (b * 255) / a); }
      out[o + 3] = a / n;
    }
    return base64(out);
  },

  layout() {
    return base64(encode(layout));
  },

  async glb() {
    // The renderer's per-pixel bevel attribute means nothing elsewhere; the normals carry the shape.
    const geometry = scene.mesh.geometry.clone();
    geometry.deleteAttribute('chrome');
    const mesh = new THREE.Mesh(geometry, scene.mesh.material);
    const buffer = await new GLTFExporter().parseAsync(mesh, { binary: true });
    return base64(new Uint8Array(buffer as ArrayBuffer));
  },
};
