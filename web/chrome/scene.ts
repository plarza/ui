// The three.js scene: the chrome mesh lit only by the studio, on a transparent background.
// The Svelte component and the CLI's renderer both draw through this.

import * as THREE from 'three';
import type { Layout } from './layout';
import { domeSoft, domeUnit } from './bevel';
import { fieldLo, fieldSpan } from './layout';
import { bevelAttribute, shape, triangles } from './mesh';
import { shapeSettings, type ChromeSettings } from './settings';
import type { Studio } from './studio';

const rad = Math.PI / 180;
/** Radius of the sphere the camera keeps in view, in logo units. */
const fit = 0.6;
/** Frames averaged into a still, each shifted by a fraction of a pixel. */
const stillSamples = 16;
/** Frames in before the still replaces the moving frame (multisampled) on the canvas. */
const stillShown = 4;

export class ChromeScene {
  readonly renderer: THREE.WebGLRenderer;
  private scene = new THREE.Scene();
  private camera = new THREE.PerspectiveCamera();
  private geometry = new THREE.BufferGeometry();
  private uniforms = {
    chromeRim: { value: 0 }, chromeRimWidth: { value: 0 }, chromeBevelWidth: { value: 0 },
    chromeCurve: { value: 1 }, chromeGroove: { value: 0 }, chromeRecess: { value: 0 }, chromeDome: { value: 0 },
  };
  private fieldUniform = { value: null as THREE.DataTexture | null };
  private material = chromeMaterial(this.uniforms, this.fieldUniform);
  private object = new THREE.Mesh(this.geometry, this.material);
  private layout?: Layout;
  private settings?: ChromeSettings;
  private rest = new THREE.Quaternion();
  private motion = new THREE.Quaternion();
  private pmrem: THREE.PMREMGenerator;
  private still?: Still;
  private ascii?: AsciiPass;
  private size = new THREE.Vector2(1, 1);
  private samples = 0;

  constructor(canvas: HTMLCanvasElement | OffscreenCanvas, options: { preserveDrawingBuffer?: boolean; antialias?: boolean } = {}) {
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, ...options });
    this.renderer.setClearColor(0x000000, 0);
    this.renderer.toneMapping = THREE.NeutralToneMapping;
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.pmrem = new THREE.PMREMGenerator(this.renderer);
    this.object.frustumCulled = false;
    this.scene.add(this.object);
  }

  /** What the chrome reflects: an equirectangular panorama. */
  setStudio(studio: Studio) {
    // Half floats, because every WebGL2 GPU filters them smoothly; 32-bit floats may fall back to
    // nearest-pixel sampling, which shows as blocks in a mirror.
    const env = halfTexture(studio.data, studio.width, studio.height);
    env.mapping = THREE.EquirectangularReflectionMapping;
    env.colorSpace = THREE.LinearSRGBColorSpace;
    this.scene.environment?.dispose();
    this.scene.environment = this.pmrem.fromEquirectangular(env).texture;
    env.dispose();
  }

  setLayout(layout: Layout) {
    this.layout = layout;
    this.geometry.dispose();
    this.geometry = new THREE.BufferGeometry();
    this.geometry.setIndex(new THREE.BufferAttribute(triangles(layout), 1));
    this.geometry.setAttribute('chrome', new THREE.BufferAttribute(bevelAttribute(layout), 4));
    this.fieldUniform.value?.dispose();
    this.fieldUniform.value = halfTexture(layout.field, layout.fieldSize, layout.fieldSize);
    this.object.geometry = this.geometry;
    if (this.settings) this.setSettings(this.settings);
  }

  setSettings(s: ChromeSettings) {
    const shapeChanged = !this.settings || shapeSettings.some((k) => this.settings![k] !== s[k]);
    this.settings = { ...s };
    if (this.layout && (shapeChanged || !this.geometry.getAttribute('position'))) {
      const position = this.geometry.getAttribute('position') as THREE.BufferAttribute | undefined;
      const normal = this.geometry.getAttribute('normal') as THREE.BufferAttribute | undefined;
      const out = shape(this.layout, s, position?.array as Float32Array, normal?.array as Float32Array);
      if (position && normal) {
        position.needsUpdate = normal.needsUpdate = true;
      } else {
        this.geometry.setAttribute('position', new THREE.BufferAttribute(out.position, 3));
        this.geometry.setAttribute('normal', new THREE.BufferAttribute(out.normal, 3));
      }
    }
    const u = this.uniforms;
    u.chromeRim.value = Math.min(s.rimRadius, s.depth / 2);
    u.chromeRimWidth.value = s.rimWidth;
    u.chromeBevelWidth.value = s.bevelWidth;
    u.chromeCurve.value = 1 + s.bevelCurve;
    u.chromeGroove.value = s.groove;
    u.chromeRecess.value = s.recess;
    u.chromeDome.value = s.dome;
    this.material.roughness = s.roughness;
    this.renderer.toneMappingExposure = s.exposure;
    this.scene.environmentRotation.set(s.lightHeight * rad, s.lightAngle * rad, 0, 'YXZ');
    this.rest.setFromEuler(new THREE.Euler(s.pitch * rad, s.yaw * rad, 0, 'YXZ'));
    this.frame();
  }

  /** The rotation from dragging, tilting and the gyro, applied on top of the rest pose. */
  setMotion(q: THREE.Quaternion) {
    this.motion.copy(q);
  }

  resize(width: number, height: number, pixelRatio = 1) {
    this.size.set(width, height);
    this.ascii?.resize(width, height, pixelRatio);
    this.renderer.setPixelRatio(pixelRatio);
    this.renderer.setSize(width, height, false);
    this.camera.aspect = width / height;
    this.frame();
  }

  /** A frame as it moves: straight to the canvas, multisampled. A still starts again after it. */
  render() {
    this.object.quaternion.multiplyQuaternions(this.motion, this.rest);
    this.samples = 0;
    if (this.ascii) {
      this.renderer.setRenderTarget(this.ascii.frame);
      this.renderer.render(this.scene, this.camera);
      this.ascii.show(this.renderer);
      return;
    }
    this.renderer.setRenderTarget(null);
    this.renderer.render(this.scene, this.camera);
  }

  /**
   * Draw the logo as characters (null to stop): each cell of a grid becomes a character from
   * `ramp` by its brightness, in the logo's own colour. `origin` is where the grid's lines cross
   * the canvas, in CSS pixels, so the cells can line up with a grid drawn around it.
   */
  setAscii(options: AsciiOptions | null) {
    this.ascii?.dispose();
    this.ascii = options ? new AsciiPass(options) : undefined;
    if (this.ascii) this.ascii.resize(this.size.x, this.size.y, this.renderer.getPixelRatio());
  }

  /** Where the character grid's lines cross the canvas, in CSS pixels. */
  setAsciiOrigin(x: number, y: number) {
    this.ascii?.setOrigin(x, y);
  }

  /**
   * While it stands still, one more frame folded into the picture on the canvas, shifted by a
   * fraction of a pixel; false once all of them are in. Multisampling smooths only the outline:
   * the rim, groove and bevel turn the normal within a pixel, and a mirror shows every turn, so
   * their highlights step until many offset frames are averaged.
   */
  refine(): boolean {
    // Characters are drawn a cell at a time: nothing to sharpen.
    if (this.ascii || this.samples >= stillSamples) return false;
    const size = this.renderer.getDrawingBufferSize(new THREE.Vector2());
    if (!this.still || this.still.width !== size.x || this.still.height !== size.y) {
      this.still?.dispose();
      this.still = new Still(size.x, size.y);
    }
    const n = this.samples++;
    this.camera.setViewOffset(size.x, size.y, halton(n + 1, 2) - 0.5, halton(n + 1, 3) - 0.5, size.x, size.y);
    this.renderer.setRenderTarget(this.still.frame);
    this.renderer.render(this.scene, this.camera);
    this.camera.clearViewOffset();
    this.still.fold(this.renderer, 1 / (n + 1));
    if (this.samples >= stillShown) this.still.show(this.renderer);
    return true;
  }

  /** The mesh, for export. */
  get mesh() {
    return this.object;
  }

  dispose() {
    this.still?.dispose();
    this.ascii?.dispose();
    this.geometry.dispose();
    this.fieldUniform.value?.dispose();
    this.material.dispose();
    this.scene.environment?.dispose();
    this.pmrem.dispose();
    this.renderer.dispose();
  }

  private frame() {
    // The field of view spans the view's shorter side, so the logo looks the same in any shape of view.
    const fov = this.settings?.fov ?? 30;
    const aspect = this.camera.aspect || 1;
    this.camera.fov = aspect >= 1 ? fov : (2 * Math.atan(Math.tan((fov * rad) / 2) / aspect)) / rad;
    const distance = fit / (this.settings?.scale ?? 1) / Math.sin((fov * rad) / 2);
    this.camera.position.set(0, 0, distance);
    this.camera.near = distance / 10;
    this.camera.far = distance * 10;
    this.camera.lookAt(0, 0, 0);
    this.camera.updateProjectionMatrix();
  }
}

/** The n-th point of the Halton sequence in a base: offsets that cover a pixel evenly. */
function halton(n: number, base: number) {
  let r = 0, f = 1;
  for (; n > 0; n = Math.floor(n / base)) r += (f /= base) * (n % base);
  return r;
}

/**
 * A still built up frame by frame: each frame (linear light, premultiplied by its coverage) is
 * tone-mapped as the canvas would be and averaged into the sum, which goes to the canvas in sRGB.
 * Tone-mapping each frame before averaging keeps the still as bright as a moving frame.
 */
class Still {
  readonly frame: THREE.WebGLRenderTarget;
  private sum: THREE.WebGLRenderTarget;
  private next: THREE.WebGLRenderTarget;
  private quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2));
  private camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  private folding = new THREE.ShaderMaterial({
    uniforms: { frame: { value: null }, sum: { value: null }, weight: { value: 1 }, toneMappingExposure: { value: 1 } },
    vertexShader: 'varying vec2 vUv; void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }',
    fragmentShader: `
      #include <tonemapping_pars_fragment>
      uniform sampler2D frame, sum;
      uniform float weight;
      varying vec2 vUv;
      void main() {
        vec4 c = texture2D(frame, vUv);
        if (c.a > 0.0) c.rgb = NeutralToneMapping(c.rgb / c.a) * c.a;
        gl_FragColor = mix(texture2D(sum, vUv), c, weight);
      }`,
    depthTest: false, depthWrite: false, blending: THREE.NoBlending, toneMapped: false,
  });
  private showing = new THREE.ShaderMaterial({
    uniforms: { sum: { value: null } },
    vertexShader: 'varying vec2 vUv; void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }',
    fragmentShader: `
      uniform sampler2D sum;
      varying vec2 vUv;
      void main() {
        vec4 c = texture2D(sum, vUv);
        if (c.a > 0.0) c.rgb = sRGBTransferOETF(vec4(c.rgb / c.a, 1.0)).rgb * c.a;
        gl_FragColor = c;
      }`,
    depthTest: false, depthWrite: false, blending: THREE.NoBlending, toneMapped: false,
  });

  constructor(readonly width: number, readonly height: number) {
    const target = (depthBuffer: boolean) => new THREE.WebGLRenderTarget(width, height, { type: THREE.HalfFloatType, depthBuffer });
    this.frame = target(true);
    this.sum = target(false);
    this.next = target(false);
    this.quad.frustumCulled = false;
  }

  fold(renderer: THREE.WebGLRenderer, weight: number) {
    this.folding.uniforms.frame.value = this.frame.texture;
    this.folding.uniforms.sum.value = this.sum.texture;
    this.folding.uniforms.weight.value = weight;
    // three sets the exposure only when a material is first drawn; this one follows the setting.
    this.folding.uniforms.toneMappingExposure.value = renderer.toneMappingExposure;
    this.draw(renderer, this.folding, this.next);
    [this.sum, this.next] = [this.next, this.sum];
  }

  show(renderer: THREE.WebGLRenderer) {
    this.showing.uniforms.sum.value = this.sum.texture;
    this.draw(renderer, this.showing, null);
  }

  dispose() {
    for (const t of [this.frame, this.sum, this.next]) t.dispose();
    this.quad.geometry.dispose();
    this.folding.dispose();
    this.showing.dispose();
  }

  private draw(renderer: THREE.WebGLRenderer, material: THREE.Material, target: THREE.WebGLRenderTarget | null) {
    this.quad.material = material;
    renderer.setRenderTarget(target);
    renderer.render(this.quad, this.camera);
  }
}

export interface AsciiOptions {
  /** A cell's size in CSS pixels. */
  cell: [number, number];
  /** The font the characters are drawn in: a CSS font family, and its weight. */
  font: string;
  weight?: number;
  /** Font size in CSS pixels. */
  fontSize: number;
  /** Characters from darkest to brightest; the first is drawn for nothing. */
  ramp: string;
  /** Brightness below which a cell is left empty, so what is behind the canvas shows. */
  threshold: number;
  /** How much brighter the characters are than the render (1.25 lifts the chrome's greys). */
  gain: number;
  /** The colour a lit cell sits on, hiding what is behind it. */
  background: string;
}

/**
 * The logo as characters: the scene drawn at CSS resolution into a target, then a pass over the
 * canvas that picks each cell's character by its brightness (tone-mapped as the canvas would be)
 * and draws it from an atlas, in the cell's colour times `gain`. Lit cells are opaque, on
 * `background`; the rest are transparent.
 */
class AsciiPass {
  frame = new THREE.WebGLRenderTarget(1, 1, { type: THREE.HalfFloatType });
  private atlas?: THREE.CanvasTexture;
  private quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2));
  private camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  private ratio = 1;
  private material = new THREE.ShaderMaterial({
    uniforms: {
      frame: { value: null }, atlas: { value: null }, glyphs: { value: 1 }, cell: { value: new THREE.Vector2() },
      origin: { value: new THREE.Vector2() }, resolution: { value: new THREE.Vector2() }, threshold: { value: 0 },
      gain: { value: 1 }, background: { value: new THREE.Color() }, toneMappingExposure: { value: 1 },
    },
    vertexShader: 'void main() { gl_Position = vec4(position.xy, 0.0, 1.0); }',
    fragmentShader: `
      #include <tonemapping_pars_fragment>
      uniform sampler2D frame, atlas;
      uniform float glyphs, threshold, gain;
      uniform vec2 cell, origin, resolution;
      uniform vec3 background;
      // The render's colour at p (canvas pixels from the top left), as the canvas would show it.
      vec3 display(vec2 p) {
        vec4 c = texture2D(frame, vec2(p.x, resolution.y - p.y) / resolution);
        if (c.a <= 0.0) return vec3(0.0);
        return sRGBTransferOETF(vec4(NeutralToneMapping(c.rgb / c.a), 1.0)).rgb * c.a;
      }
      void main() {
        // Canvas pixels from the top left, the cell this pixel is in, and where in it.
        vec2 p = vec2(gl_FragCoord.x, resolution.y - gl_FragCoord.y);
        vec2 at = (p - origin) / cell, index = floor(at), inside = at - index;
        vec2 centre = origin + (index + 0.5) * cell;
        // The cell's colour: four samples across it.
        vec3 c = 0.25 * (display(centre + cell * vec2(-0.25, -0.25)) + display(centre + cell * vec2(0.25, -0.25))
          + display(centre + cell * vec2(-0.25, 0.25)) + display(centre + cell * vec2(0.25, 0.25)));
        float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
        if (l < threshold) { gl_FragColor = vec4(0.0); return; }
        float glyph = min(floor(l * glyphs), glyphs - 1.0);
        float ink = texture2D(atlas, vec2((glyph + inside.x) / glyphs, 1.0 - inside.y)).a;
        gl_FragColor = vec4(mix(background, min(c * gain, vec3(1.0)), ink), 1.0);
      }`,
    depthTest: false, depthWrite: false, blending: THREE.NoBlending, toneMapped: false,
  });

  constructor(private options: AsciiOptions) {
    this.quad.material = this.material;
    this.quad.frustumCulled = false;
    const u = this.material.uniforms;
    u.glyphs.value = options.ramp.length;
    u.threshold.value = options.threshold;
    u.gain.value = options.gain;
    // As written, in sRGB: the pass mixes in the colours the canvas shows.
    u.background.value = new THREE.Color().setStyle(options.background, THREE.LinearSRGBColorSpace);
  }

  resize(width: number, height: number, ratio: number) {
    this.ratio = ratio;
    // The scene at CSS resolution: a cell is several of its pixels, which is all the pass reads.
    this.frame.setSize(Math.max(1, Math.round(width)), Math.max(1, Math.round(height)));
    const u = this.material.uniforms;
    u.cell.value.set(this.options.cell[0] * ratio, this.options.cell[1] * ratio);
    u.resolution.value.set(Math.round(width * ratio), Math.round(height * ratio));
    this.drawAtlas();
  }

  setOrigin(x: number, y: number) {
    this.material.uniforms.origin.value.set(x * this.ratio, y * this.ratio);
  }

  show(renderer: THREE.WebGLRenderer) {
    const u = this.material.uniforms;
    u.frame.value = this.frame.texture;
    u.toneMappingExposure.value = renderer.toneMappingExposure;
    renderer.setRenderTarget(null);
    renderer.render(this.quad, this.camera);
  }

  dispose() {
    this.frame.dispose();
    this.atlas?.dispose();
    this.quad.geometry.dispose();
    this.material.dispose();
  }

  /** Every character of the ramp in a row, each in a cell, drawn at the canvas's resolution. */
  private drawAtlas() {
    const { ramp, font, weight = 400, fontSize, cell } = this.options;
    const w = Math.ceil(cell[0] * this.ratio), h = Math.ceil(cell[1] * this.ratio);
    const canvas = document.createElement('canvas');
    canvas.width = w * ramp.length;
    canvas.height = h;
    const g = canvas.getContext('2d')!;
    g.font = `${weight} ${fontSize * this.ratio}px ${font}`;
    g.textBaseline = 'top';
    g.fillStyle = '#fff';
    [...ramp].forEach((ch, i) => g.fillText(ch, i * w, 0));
    this.atlas?.dispose();
    this.atlas = new THREE.CanvasTexture(canvas);
    this.atlas.minFilter = this.atlas.magFilter = THREE.LinearFilter;
    this.atlas.generateMipmaps = false;
    this.material.uniforms.atlas.value = this.atlas;
  }
}

/** RGBA floats as a half-float texture, which every WebGL2 GPU filters smoothly. */
function halfTexture(data: Float32Array, width: number, height: number) {
  const half = new Uint16Array(data.length);
  for (let i = 0; i < half.length; i++) half[i] = THREE.DataUtils.toHalfFloat(data[i]);
  const texture = new THREE.DataTexture(half, width, height, THREE.RGBAFormat, THREE.HalfFloatType);
  texture.magFilter = texture.minFilter = THREE.LinearFilter;
  texture.needsUpdate = true;
  return texture;
}

/**
 * Polished silver whose normals come from the bevel and the dome for each pixel (the GLSL twin of
 * bevel.ts): the bevel from the distance to the outline, the dome from the inflation field.
 */
function chromeMaterial(uniforms: Record<string, { value: number }>, field: { value: THREE.Texture | null }) {
  const material = new THREE.MeshStandardMaterial({ color: new THREE.Color(0.9, 0.9, 0.9), metalness: 1 });
  const varyings = `
    varying float vChromeD;
    varying vec3 vChromeG;
    varying vec3 vChromeZ;
    varying vec2 vChromeXY;
    varying vec3 vChromeX;
    varying vec3 vChromeY;`;
  material.onBeforeCompile = (shader) => {
    Object.assign(shader.uniforms, uniforms, { chromeField: field });
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', `#include <common>
        attribute vec4 chrome;${varyings}`)
      .replace('#include <begin_vertex>', `#include <begin_vertex>
        vChromeD = chrome.x;
        vChromeG = normalMatrix * vec3(chrome.yz, 0.0);
        vChromeZ = normalMatrix * vec3(0.0, 0.0, chrome.w);
        vChromeXY = position.xy;
        vChromeX = normalMatrix * vec3(1.0, 0.0, 0.0);
        vChromeY = normalMatrix * vec3(0.0, 1.0, 0.0);`);
    shader.fragmentShader = shader.fragmentShader
      .replace('#include <common>', `#include <common>
        uniform float chromeRim, chromeRimWidth, chromeGroove, chromeBevelWidth, chromeCurve, chromeRecess, chromeDome;
        uniform sampler2D chromeField;${varyings}
        // (across, up): the normal is -across along the inward direction plus up along the face.
        vec2 chromeSlope(float d) {
          if (d < chromeRim) {
            float x = chromeRim - d;
            return vec2(x, sqrt(max(chromeRim * chromeRim - x * x, 0.0))) / chromeRim;
          }
          float at = d - chromeRim - chromeRimWidth;
          if (at < 0.0) return vec2(0.0, 1.0);
          if (at < chromeGroove) return vec2(-at, sqrt(max(chromeGroove * chromeGroove - at * at, 0.0))) / chromeGroove;
          at -= chromeGroove;
          if (at < chromeBevelWidth) {
            float t = max(at / chromeBevelWidth, 1e-6);
            return normalize(vec2(-(chromeRecess - chromeGroove) * chromeCurve * pow(t, chromeCurve - 1.0) / chromeBevelWidth, 1.0));
          }
          return vec2(0.0, 1.0);
        }
        // The slope averaged over the pixel, so a frame in motion steps less where it turns sharply.
        vec2 chromeSlopeOverPixel(float d) {
          float w = fwidth(d);
          return chromeSlope(d - 0.375 * w) + chromeSlope(d - 0.125 * w) + chromeSlope(d + 0.125 * w) + chromeSlope(d + 0.375 * w);
        }`)
      .replace('#include <normal_fragment_begin>', `#include <normal_fragment_begin>
        vec2 chromeS = chromeSlopeOverPixel(vChromeD);
        // The dome leans the bevel's normal by its slope; the walls (no face direction) take none.
        vec3 chromeLeanBy = vec3(0.0);
        if (dot(vChromeZ, vChromeZ) > 0.0) {
          vec3 f = texture2D(chromeField, (vChromeXY - ${fieldLo.toFixed(4)}) / ${fieldSpan.toFixed(4)}).xyz;
          float lean = chromeDome / (2.0 * sqrt(${domeUnit.toFixed(8)}) * sqrt(max(f.x, 0.0) + ${domeSoft.toFixed(8)}));
          chromeLeanBy = lean * (f.y * vChromeX + f.z * vChromeY);
        }
        normal = normalize(-chromeS.x * vChromeG + chromeS.y * (vChromeZ - chromeLeanBy));
        nonPerturbedNormal = normal;`);
  };
  return material;
}
