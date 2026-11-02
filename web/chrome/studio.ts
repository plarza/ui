// The studio the chrome reflects: a photographed equirectangular panorama in grey. Chrome has no
// colour of its own, so this image is the whole look: its walls and lights are what flow through
// every curve.
//
// Studios ship as 8-bit grey AVIFs that store log₂ of brightness from 2^LO to 2^HI, which keeps a
// photographed studio's full range in one small channel (about 20 KB at 2048 × 1024). The CLI
// makes them from any Radiance .hdr panorama. AzaUI's ChromeStudio.swift reads the same files.

import * as THREE from 'three';
import { HDRLoader } from 'three/examples/jsm/loaders/HDRLoader.js';

export const LO = -10;
export const HI = 7;

export interface Studio {
  width: number;
  height: number;
  /** RGBA float, bottom row first (three.js's layout). */
  data: Float32Array;
}

/** A Radiance .hdr panorama, in grey so the silver stays neutral. */
export function fromHdr(bytes: ArrayBuffer): Studio {
  const loader = new HDRLoader().setDataType(THREE.FloatType);
  const { width, height, data } = loader.parse(bytes) as { width: number; height: number; data: Float32Array };
  const out = new Float32Array(width * height * 4);
  for (let row = 0; row < height; row++) for (let col = 0; col < width; col++) {
    const i = ((height - 1 - row) * width + col) * 4, o = (row * width + col) * 4;
    const l = 0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2];
    out[o] = out[o + 1] = out[o + 2] = l;
    out[o + 3] = 1;
  }
  return { width, height, data: out };
}

/** A studio image (AVIF or anything the browser decodes), log-encoded as above. Browser only. */
export async function fromImage(bytes: ArrayBuffer): Promise<Studio> {
  const bitmap = await createImageBitmap(new Blob([bytes]), { colorSpaceConversion: 'none', premultiplyAlpha: 'none' });
  const { width, height } = bitmap;
  const canvas = new OffscreenCanvas(width, height);
  const context = canvas.getContext('2d', { colorSpace: 'srgb' })!;
  context.drawImage(bitmap, 0, 0);
  const pixels = context.getImageData(0, 0, width, height).data;
  const table = Float32Array.from({ length: 256 }, (_, v) => 2 ** (LO + (v / 255) * (HI - LO)));
  const out = new Float32Array(width * height * 4);
  for (let row = 0; row < height; row++) for (let col = 0; col < width; col++) {
    const l = table[pixels[((height - 1 - row) * width + col) * 4]];
    out.set([l, l, l, 1], (row * width + col) * 4);
  }
  return { width, height, data: out };
}

/** Either kind, told apart by the .hdr signature. */
export function load(bytes: ArrayBuffer): Promise<Studio> {
  const head = new Uint8Array(bytes, 0, 2);
  return head[0] === 0x23 && head[1] === 0x3f ? Promise.resolve(fromHdr(bytes)) : fromImage(bytes);
}

/**
 * The 8-bit log-encoded pixels of a studio, top row first, turned by `angle` degrees about the
 * vertical, and resized to `width` × `width / 2`: what goes into the AVIF.
 */
export function logPixels(studio: Studio, angle = 0, width = studio.width): Uint8Array {
  const W = width, H = width / 2;
  const px = new Uint8Array(W * H);
  for (let y = 0; y < H; y++) {
    const sy = Math.min(studio.height - 1, Math.floor(((y + 0.5) / H) * studio.height));
    for (let x = 0; x < W; x++) {
      const u = ((x + 0.5) / W + angle / 360) % 1;
      const sx = Math.min(studio.width - 1, Math.floor(u * studio.width));
      const l = studio.data[((studio.height - 1 - sy) * studio.width + sx) * 4];
      const v = (Math.log2(Math.max(l, 2 ** LO)) - LO) / (HI - LO);
      px[y * W + x] = Math.round(Math.min(1, Math.max(0, v)) * 255);
    }
  }
  return px;
}
