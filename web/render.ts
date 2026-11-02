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
    scene.resize(size * ss, size * ss, 1);
    return { points: layout.x.length, triangles: layout.triangles.length / 3 };
  },

  /** One frame as straight-alpha RGBA, top row first, base64. */
  frame(rotation: [number, number, number, number]) {
    scene.setMotion(new THREE.Quaternion(...rotation));
    scene.render();
    const gl = scene.renderer.getContext();
    const big = size * supersample;
    const raw = new Uint8Array(big * big * 4);
    gl.readPixels(0, 0, big, big, gl.RGBA, gl.UNSIGNED_BYTE, raw);
    const out = new Uint8Array(size * size * 4);
    const n = supersample * supersample;
    for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
      // Average premultiplied samples, then divide out alpha.
      let r = 0, g = 0, b = 0, a = 0;
      for (let j = 0; j < supersample; j++) for (let i = 0; i < supersample; i++) {
        const k = ((big - 1 - (y * supersample + j)) * big + x * supersample + i) * 4;
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
