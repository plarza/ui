// The chrome logo as characters, over a whole page, in a few kilobytes and three passes a frame,
// with no three.js: a light renderer for pages that need the logo on screen at once.
//
// 1. The logo: the coarse layout (a .chromelite, CLI `--only lite`), bevelled here (mesh.ts),
//    drawn into a target the size of its box at about 1.6 CSS pixels a sample, shaded as
//    ChromeScene shades it: polished silver reflecting the studio, tone-mapped and in sRGB.
// 2. The cells: one pixel per character cell of the page, each the average of 4 × 8 samples of the
//    logo, becoming a character from the ramp by its brightness, in its colour; or, where the
//    logo is too dark, a character of the field, a faint noise over the whole page.
// 3. The screen: each pixel looks up its cell and the cell's character in an atlas drawn from
//    the glyphs' outlines at the screen's exact cell size, so every character is crisp.
//
// Like terminal renderers (beamterm), the screen pass is one draw of two texture reads a pixel;
// the logo and cells are small, so a frame costs well under a millisecond on a laptop.

import { dome } from './chrome/bevel';
import { bevelAttribute, shape, triangles, type MeshLayout } from './chrome/mesh';
import { loadLite } from './chrome/lite';
import { Motion } from './chrome/motion';
import { matrix, mul, yxz } from './chrome/quat';
import { resolve, type ChromeSettings } from './chrome/settings';
import { HI, LO } from './chrome/range';

export interface Glyphs {
  /** Font units per em, the ascender and descender, and the advance every glyph shares. */
  em: number;
  ascender: number;
  descender: number;
  advance: number;
  /** Each character's outline as SVG path data in font units, y up. */
  paths: Record<string, string>;
}

export interface AsciiChromeOptions {
  /** The canvas, covering the page. */
  canvas: HTMLCanvasElement;
  /** Where the logo is on the page: a square, in CSS pixels. */
  box: HTMLElement;
  /** The coarse layout's .chromelite, or the layout itself. */
  layout: string | URL | Promise<MeshLayout>;
  /** A studio image, log-encoded grey (AzaUI's studios, or the CLI's). */
  studio: string | URL;
  settings?: Partial<ChromeSettings>;
  glyphs: Glyphs;
  /** Characters from darkest to brightest; the field uses the first `fieldLevels`. */
  ramp: string;
  fieldLevels?: number;
  /** A cell in CSS pixels, rounded to whole device pixels, and the font size in CSS pixels. */
  cell: [number, number];
  fontSize: number;
  /** Below this brightness a cell is the field's. */
  threshold?: number;
  /** The logo's characters this much brighter than the render. */
  gain?: number;
  /** The page's colour, and the field's characters from faint to brighter. */
  page: string;
  field: [string, string];
  /** Cells per wave of the field's noise. */
  fieldScale?: number;
  /** Drag, cursor and gyro. */
  interactive?: boolean;
}

// The vertex carries what ChromeScene's shader reads (mesh.ts bevelAttribute): the distance in
// from the outline, the inward direction and the face; and the dome's slope there.
const VERTEX = `#version 300 es
in vec3 position;
in vec4 bevel;
in vec2 lean;
uniform mat3 rotation;
uniform mat4 projection;
uniform float distance;
out float vD;
out vec3 vG, vZ, vLean, vPosition;
void main() {
  vec3 p = rotation * position;
  vPosition = p;
  vD = bevel.x;
  vG = rotation * vec3(bevel.yz, 0.0);
  vZ = rotation * vec3(0.0, 0.0, bevel.w);
  vLean = rotation * vec3(lean, 0.0);
  gl_Position = projection * vec4(p - vec3(0.0, 0.0, distance), 1.0);
}`;

const SHADE = `#version 300 es
precision highp float;
in float vD;
in vec3 vG, vZ, vLean, vPosition;
uniform sampler2D studio;
uniform bool linear;
uniform float studioWidth, studioLevels, exposure, distance;
uniform float rim, rimWidth, groove, bevelWidth, curve, recess;
out vec4 color;
// The bevel's slope at distance d, as ChromeScene's shader (bevel.ts): (across, up).
vec2 slope(float d) {
  if (d < rim) { float x = rim - d; return vec2(x, sqrt(max(rim * rim - x * x, 0.0))) / rim; }
  float at = d - rim - rimWidth;
  if (at < 0.0) return vec2(0.0, 1.0);
  if (at < groove) return vec2(-at, sqrt(max(groove * groove - at * at, 0.0))) / groove;
  at -= groove;
  if (at < bevelWidth) {
    float t = max(at / bevelWidth, 1e-6);
    return normalize(vec2(-(recess - groove) * curve * pow(t, curve - 1.0) / bevelWidth, 1.0));
  }
  return vec2(0.0, 1.0);
}
vec3 neutral(vec3 c) {
  c *= exposure;
  float x = min(c.r, min(c.g, c.b));
  c -= x < 0.08 ? x - 6.25 * x * x : 0.04;
  float peak = max(c.r, max(c.g, c.b));
  if (peak < 0.76) return c;
  float d = 0.24, top = 1.0 - d * d / (peak + d - 0.76);
  c *= top / peak;
  return mix(c, vec3(top), 1.0 - 1.0 / (0.15 * (peak - top) + 1.0));
}
vec3 srgb(vec3 c) { return mix(12.92 * c, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c)); }
void main() {
  // Per pixel, averaged over what the pixel covers, so the rim and groove never facet or step.
  float w = fwidth(vD);
  vec2 s = slope(vD - 0.375 * w) + slope(vD - 0.125 * w) + slope(vD + 0.125 * w) + slope(vD + 0.375 * w);
  vec3 n = normalize(-s.x * vG + s.y * (vZ - vLean));
  vec3 v = normalize(vec3(0.0, 0.0, distance) - vPosition);
  vec3 r = reflect(-v, n);
  // The studio as three.js maps an equirectangular panorama, blurred as much as a pixel spans.
  vec2 uv = vec2(atan(r.z, r.x) * 0.1591549 + 0.5, asin(clamp(r.y, -1.0, 1.0)) * 0.3183099 + 0.5);
  float spread = max(length(dFdx(r)), length(dFdy(r))) * studioWidth * 0.1591549;
  // Three-quarters of a level more: ChromeScene's PMREM softens a polished (0.03) metal that much.
  float level = clamp(log2(max(spread, 1.0)) + 0.75, 0.0, studioLevels);
  float stored = textureLod(studio, uv, level).r;
  float light = linear ? stored : exp2(${LO.toFixed(1)} + stored * ${(HI - LO).toFixed(1)});
  // Metal with the colour 0.9: Fresnel toward white at grazing angles.
  float f = 0.9 + 0.1 * pow(1.0 - max(dot(n, v), 0.0), 5.0);
  color = vec4(srgb(clamp(neutral(vec3(light * f)), 0.0, 1.0)), 1.0);
}`;

// A studio's log₂ brightness, stored in a byte, to light.
const DECODE = `#version 300 es
precision highp float;
uniform sampler2D logs;
out vec4 color;
void main() { color = vec4(exp2(${LO.toFixed(1)} + texelFetch(logs, ivec2(gl_FragCoord.xy), 0).r * ${(HI - LO).toFixed(1)}), 0.0, 0.0, 1.0); }`;

const QUAD = `#version 300 es
in vec2 corner;
void main() { gl_Position = vec4(corner, 0.0, 1.0); }`;

const CELLS = `#version 300 es
precision highp float;
uniform sampler2D logo;
uniform vec4 box;
uniform vec2 cell;
uniform float threshold, gain, levels, fieldLevels, fieldScale;
uniform vec3 dim, bright;
out vec4 color;
float hash(vec2 p) { p = fract(p * vec2(0.1031, 0.1030)); p += dot(p, p.yx + 33.33); return fract((p.x + p.y) * p.x); }
float noise(vec2 p) {
  vec2 i = floor(p), f = p - i, s = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1, 0)), s.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), s.x), s.y);
}
float fbm(vec2 p) { return 0.5 * noise(p) + 0.3 * noise(2.0 * p + 7.0) + 0.2 * noise(4.0 * p + 1.0); }
void main() {
  vec2 index = floor(gl_FragCoord.xy);
  // The cell's light: 4 × 8 samples of the logo across it, over black.
  vec3 c = vec3(0.0);
  for (int y = 0; y < 8; y++) for (int x = 0; x < 4; x++) {
    vec2 at = ((index + (vec2(x, y) + 0.5) / vec2(4.0, 8.0)) * cell - box.xy) / box.zw;
    if (all(greaterThanEqual(at, vec2(0.0))) && all(lessThan(at, vec2(1.0)))) c += texture(logo, vec2(at.x, 1.0 - at.y)).rgb;
  }
  c /= 32.0;
  float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
  if (l >= threshold) {
    color = vec4(min(c * gain, 1.0), min(floor(l * levels), levels - 1.0) / 255.0);
  } else {
    float n = fbm(index / fieldScale);
    color = vec4(mix(dim, bright, n), min(floor(n * 0.9 * fieldLevels), fieldLevels - 1.0) / 255.0);
  }
}`;

const SCREEN = `#version 300 es
precision highp float;
precision highp usampler2D;
uniform sampler2D cells, atlas;
uniform vec2 cellPixels;
uniform float height;
uniform vec3 page;
out vec4 color;
void main() {
  vec2 p = vec2(gl_FragCoord.x, height - gl_FragCoord.y);
  ivec2 index = ivec2(floor(p / cellPixels));
  vec4 c = texelFetch(cells, index, 0);
  float glyph = floor(c.a * 255.0 + 0.5);
  ivec2 inside = ivec2(p - vec2(index) * cellPixels);
  float ink = texelFetch(atlas, ivec2(int(glyph * cellPixels.x) + inside.x, inside.y), 0).r;
  color = vec4(mix(page, c.rgb, ink), 1.0);
}`;

export class AsciiChrome {
  /** Settles once the first frame is on the canvas. */
  readonly ready: Promise<void>;
  private gl: WebGL2RenderingContext;
  private settings: ChromeSettings;
  private motion = new Motion();
  private frame = 0;
  private stopped = false;
  private cleanup: (() => void)[] = [];

  constructor(private o: AsciiChromeOptions) {
    const gl = o.canvas.getContext('webgl2', { alpha: false, antialias: false, depth: false, premultipliedAlpha: false, powerPreference: 'high-performance' });
    if (!gl) throw new Error('AsciiChrome needs WebGL2');
    this.gl = gl;
    this.settings = resolve(o.settings);
    this.ready = this.start();
  }

  dispose() {
    this.stopped = true;
    cancelAnimationFrame(this.frame);
    for (const f of this.cleanup) f();
  }

  private async start() {
    const { gl, o } = this;
    // Flipped as it decodes (WebGL ignores UNPACK_FLIP_Y for bitmaps), so the bottom row is v = 0, as three.js has it.
    const studioBitmap = fetch(o.studio).then((r) => r.blob()).then((b) => createImageBitmap(b, { colorSpaceConversion: 'none', premultiplyAlpha: 'none', imageOrientation: 'flipY' }));
    const layout = typeof o.layout === 'string' || o.layout instanceof URL ? loadLite(o.layout) : o.layout;

    // Programs compile while the files arrive.
    const shade = program(gl, VERTEX, SHADE), cellsProgram = program(gl, QUAD, CELLS), screen = program(gl, QUAD, SCREEN);
    const locations = new Map<string, WebGLUniformLocation | null>();
    const at = (p: WebGLProgram, name: string) => {
      const key = `${p === shade ? 0 : p === cellsProgram ? 1 : 2}${name}`;
      if (!locations.has(key)) locations.set(key, gl.getUniformLocation(p, name));
      return locations.get(key)!;
    };
    const quad = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, quad);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);

    // The mesh: positions and normals from the bevel, the front, back and walls.
    const l = await layout;
    const { position } = shape(l, this.settings);
    const index = triangles(l);
    const vao = gl.createVertexArray();
    gl.bindVertexArray(vao);
    for (const [name, data, size] of [['position', position, 3], ['bevel', bevelAttribute(l), 4], ['lean', leanAttribute(l, this.settings), 2]] as const) {
      const buffer = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
      gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
      const at = gl.getAttribLocation(shade, name);
      gl.enableVertexAttribArray(at);
      gl.vertexAttribPointer(at, size, gl.FLOAT, false, 0, 0);
    }
    const elements = gl.createBuffer();
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, elements);
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, index, gl.STATIC_DRAW);
    gl.bindVertexArray(null);

    // The studio: its log brightness in one channel, with mipmaps to blur by.
    const bitmap = await studioBitmap;
    const studio = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, studio);
    gl.pixelStorei(gl.UNPACK_COLORSPACE_CONVERSION_WEBGL, gl.NONE);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.R8, gl.RED, gl.UNSIGNED_BYTE, bitmap);
    gl.generateMipmap(gl.TEXTURE_2D);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    const studioWidth = bitmap.width, studioLevels = Math.floor(Math.log2(bitmap.width));
    bitmap.close();
    // Blurring averages what is stored: logs average darker than light does, dimming the highlights
    // in every blurred reflection. So, where the GPU can render half floats, decode it to light first.
    let linear = false, studioTexture = studio;
    if (gl.getExtension('EXT_color_buffer_float')) {
      const light = gl.createTexture()!;
      gl.bindTexture(gl.TEXTURE_2D, light);
      gl.texStorage2D(gl.TEXTURE_2D, studioLevels + 1, gl.R16F, studioWidth, studioWidth / 2);
      const fb = gl.createFramebuffer();
      gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
      gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, light, 0);
      if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) === gl.FRAMEBUFFER_COMPLETE) {
        const decode = program(gl, QUAD, DECODE);
        gl.viewport(0, 0, studioWidth, studioWidth / 2);
        gl.useProgram(decode);
        bindQuad(gl, decode, quad);
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, studio);
        gl.drawArrays(gl.TRIANGLES, 0, 3);
        gl.bindTexture(gl.TEXTURE_2D, light);
        gl.generateMipmap(gl.TEXTURE_2D);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.deleteTexture(studio);
        gl.deleteProgram(decode);
        studioTexture = light;
        linear = true;
      } else gl.deleteTexture(light);
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);
      gl.deleteFramebuffer(fb);
    }

    // Sizes, redone on resize: the canvas in device pixels, whole-pixel cells, the logo's target.
    let logoTarget: Target | undefined, cellTarget: Target | undefined, atlas: WebGLTexture | undefined;
    let cellPixels: [number, number] = [1, 1], cols = 1, rows = 1, ratio = 1;
    const size = () => {
      ratio = Math.min(devicePixelRatio || 1, 3);
      const w = Math.max(1, Math.round(innerWidth * ratio)), h = Math.max(1, Math.round(innerHeight * ratio));
      o.canvas.width = w; o.canvas.height = h;
      cellPixels = [Math.max(1, Math.round(o.cell[0] * ratio)), Math.max(1, Math.round(o.cell[1] * ratio))];
      cols = Math.ceil(w / cellPixels[0]); rows = Math.ceil(h / cellPixels[1]);
      cellTarget = target(gl, cols, rows, false, cellTarget);
      const box = o.box.getBoundingClientRect();
      const side = Math.max(16, Math.round(box.width / 1.6));
      logoTarget = target(gl, side, side, true, logoTarget);
      if (atlas) gl.deleteTexture(atlas);
      atlas = drawAtlas(gl, o, cellPixels, ratio);
      draw();
    };

    const settings = this.settings, rest = yxz(settings.pitch * (Math.PI / 180), settings.yaw * (Math.PI / 180));
    const fov = (settings.fov * Math.PI) / 180, distance = 0.6 / settings.scale / Math.sin(fov / 2);
    const projection = perspective(fov, 1, distance / 10, distance * 10);
    const [dim, bright] = o.field.map(rgb), page = rgb(o.page);
    let rotation = matrix(rest);

    const draw = () => {
      if (!logoTarget || !cellTarget || !atlas) return;
      const box = o.box.getBoundingClientRect();
      // 1. The logo.
      gl.bindFramebuffer(gl.FRAMEBUFFER, logoTarget.framebuffer);
      gl.viewport(0, 0, logoTarget.width, logoTarget.height);
      gl.clearColor(0, 0, 0, 0);
      gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
      gl.enable(gl.DEPTH_TEST);
      gl.enable(gl.CULL_FACE);
      gl.useProgram(shade);
      gl.uniformMatrix3fv(at(shade, 'rotation'), false, rotation);
      gl.uniformMatrix4fv(at(shade, 'projection'), false, projection);
      gl.uniform1f(at(shade, 'distance'), distance);
      gl.uniform1f(at(shade, 'studioWidth'), studioWidth);
      gl.uniform1f(at(shade, 'studioLevels'), studioLevels);
      gl.uniform1f(at(shade, 'exposure'), settings.exposure);
      gl.uniform1i(at(shade, 'linear'), linear ? 1 : 0);
      gl.uniform1f(at(shade, 'rim'), Math.min(settings.rimRadius, settings.depth / 2));
      gl.uniform1f(at(shade, 'rimWidth'), settings.rimWidth);
      gl.uniform1f(at(shade, 'groove'), settings.groove);
      gl.uniform1f(at(shade, 'bevelWidth'), settings.bevelWidth);
      gl.uniform1f(at(shade, 'curve'), 1 + settings.bevelCurve);
      gl.uniform1f(at(shade, 'recess'), settings.recess);
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, studioTexture);
      gl.bindVertexArray(vao);
      gl.drawElements(gl.TRIANGLES, index.length, gl.UNSIGNED_INT, 0);
      gl.bindVertexArray(null);
      gl.disable(gl.DEPTH_TEST);
      gl.disable(gl.CULL_FACE);

      // 2. The cells.
      gl.bindFramebuffer(gl.FRAMEBUFFER, cellTarget.framebuffer);
      gl.viewport(0, 0, cols, rows);
      gl.useProgram(cellsProgram);
      bindQuad(gl, cellsProgram, quad);
      gl.bindTexture(gl.TEXTURE_2D, logoTarget.texture);
      gl.uniform4f(at(cellsProgram, 'box'), box.left, box.top, box.width, box.height);
      gl.uniform2f(at(cellsProgram, 'cell'), cellPixels[0] / ratio, cellPixels[1] / ratio);
      gl.uniform1f(at(cellsProgram, 'threshold'), o.threshold ?? 0.08);
      gl.uniform1f(at(cellsProgram, 'gain'), o.gain ?? 1.25);
      gl.uniform1f(at(cellsProgram, 'levels'), o.ramp.length);
      gl.uniform1f(at(cellsProgram, 'fieldLevels'), o.fieldLevels ?? 4);
      gl.uniform1f(at(cellsProgram, 'fieldScale'), o.fieldScale ?? 10);
      gl.uniform3fv(at(cellsProgram, 'dim'), dim);
      gl.uniform3fv(at(cellsProgram, 'bright'), bright);
      gl.drawArrays(gl.TRIANGLES, 0, 3);

      // 3. The screen.
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);
      gl.viewport(0, 0, o.canvas.width, o.canvas.height);
      gl.useProgram(screen);
      bindQuad(gl, screen, quad);
      gl.uniform1i(at(screen, 'cells'), 0);
      gl.uniform1i(at(screen, 'atlas'), 1);
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, cellTarget.texture);
      gl.activeTexture(gl.TEXTURE1);
      gl.bindTexture(gl.TEXTURE_2D, atlas);
      gl.activeTexture(gl.TEXTURE0);
      gl.uniform2f(at(screen, 'cellPixels'), cellPixels[0], cellPixels[1]);
      gl.uniform1f(at(screen, 'height'), o.canvas.height);
      gl.uniform3fv(at(screen, 'page'), page);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    };

    size();
    let resizing = 0;
    const onResize = () => { cancelAnimationFrame(resizing); resizing = requestAnimationFrame(size); };
    addEventListener('resize', onResize);
    this.cleanup.push(() => removeEventListener('resize', onResize));
    if (o.interactive !== false) this.listen();

    let last = performance.now();
    const tick = (now: number) => {
      if (this.stopped) return;
      this.frame = requestAnimationFrame(tick);
      const dt = (now - last) / 1000;
      last = now;
      // Swaying, it moves every frame; otherwise only while something moves it.
      if (!settings.sway && !this.motion.moving) return;
      rotation = matrix(mul(this.motion.step(dt, settings), rest));
      draw();
    };
    this.frame = requestAnimationFrame(tick);
  }

  /** The cursor leans it, a drag on the logo spins it, the phone's tilt leans it. */
  private listen() {
    const { o, motion, settings } = this;
    const inside = (e: PointerEvent) => {
      const r = o.box.getBoundingClientRect();
      return e.clientX >= Math.max(0, r.left) && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom;
    };
    let dragging: { x: number; y: number } | undefined;
    let askedForMotion = false;
    const move = (e: PointerEvent) => {
      const r = o.box.getBoundingClientRect();
      if (e.pointerType === 'mouse') motion.pointer((e.clientX - (r.left + r.width / 2)) / (innerWidth / 2), (e.clientY - (r.top + r.height / 2)) / (innerHeight / 2), settings);
      if (dragging) {
        motion.drag(e.clientX - dragging.x, e.clientY - dragging.y, Math.min(r.width, r.height));
        dragging = { x: e.clientX, y: e.clientY };
      } else o.canvas.style.cursor = inside(e) ? 'grab' : '';
    };
    const down = (e: PointerEvent) => {
      if (!inside(e)) return;
      o.canvas.setPointerCapture(e.pointerId);
      o.canvas.style.cursor = 'grabbing';
      dragging = { x: e.clientX, y: e.clientY };
      motion.start();
      // iOS only lets a page read the gyro after asking, from a tap.
      const D = DeviceOrientationEvent as unknown as { requestPermission?: () => Promise<string> };
      if (!askedForMotion && D.requestPermission) { askedForMotion = true; D.requestPermission().catch(() => {}); }
    };
    const up = () => {
      if (!dragging) return;
      dragging = undefined;
      o.canvas.style.cursor = 'grab';
      motion.end();
    };
    const left = () => motion.pointerLeft();
    const tilt = (e: DeviceOrientationEvent) => { if (e.beta !== null && e.gamma !== null) motion.gyro(e.beta, e.gamma, settings); };
    addEventListener('pointermove', move);
    o.canvas.addEventListener('pointerdown', down);
    addEventListener('pointerup', up);
    addEventListener('pointercancel', up);
    document.documentElement.addEventListener('pointerleave', left);
    addEventListener('deviceorientation', tilt);
    this.cleanup.push(() => {
      removeEventListener('pointermove', move);
      o.canvas.removeEventListener('pointerdown', down);
      removeEventListener('pointerup', up);
      removeEventListener('pointercancel', up);
      document.documentElement.removeEventListener('pointerleave', left);
      removeEventListener('deviceorientation', tilt);
    });
  }
}

/** Per vertex, the dome's slope (bevel.ts dome), which leans the bevel's normal; none on the walls. */
function leanAttribute(l: MeshLayout, s: ChromeSettings) {
  const n = l.x.length, out = new Float32Array((position(l) / 3) * 2);
  for (let i = 0; i < n; i++) {
    const [, dx, dy] = dome(l.u[i], l.ux[i], l.uy[i], s);
    out[2 * i] = out[2 * (n + i)] = dx;
    out[2 * i + 1] = out[2 * (n + i) + 1] = dy;
  }
  return out;
}

/** How many floats of position the mesh has: front, back, and both rows of every wall. */
function position(l: MeshLayout) {
  let walls = 0;
  for (let i = 1; i < l.loops.length; i += 2) walls += l.loops[i];
  return (2 * l.x.length + 2 * walls) * 3;
}

interface Target { framebuffer: WebGLFramebuffer; texture: WebGLTexture; depth?: WebGLRenderbuffer; width: number; height: number }

/** A colour target (RGBA8, linear filtering), with depth if asked; the old one freed. */
function target(gl: WebGL2RenderingContext, width: number, height: number, depth: boolean, old?: Target): Target {
  if (old) {
    if (old.width === width && old.height === height) return old;
    gl.deleteFramebuffer(old.framebuffer); gl.deleteTexture(old.texture); if (old.depth) gl.deleteRenderbuffer(old.depth);
  }
  const texture = gl.createTexture()!;
  gl.bindTexture(gl.TEXTURE_2D, texture);
  gl.texStorage2D(gl.TEXTURE_2D, 1, gl.RGBA8, width, height);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  const framebuffer = gl.createFramebuffer()!;
  gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer);
  gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0);
  let renderbuffer: WebGLRenderbuffer | undefined;
  if (depth) {
    renderbuffer = gl.createRenderbuffer()!;
    gl.bindRenderbuffer(gl.RENDERBUFFER, renderbuffer);
    gl.renderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, width, height);
    gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, renderbuffer);
  }
  gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  return { framebuffer, texture, depth: renderbuffer, width, height };
}

/** Every character of the ramp in a row, a cell each, filled from its outline at the cell's size. */
function drawAtlas(gl: WebGL2RenderingContext, o: AsciiChromeOptions, [w, h]: [number, number], ratio: number) {
  const { glyphs, ramp, fontSize } = o;
  const canvas = new OffscreenCanvas(w * ramp.length, h);
  const g = canvas.getContext('2d')!;
  const scale = (fontSize * ratio) / glyphs.em;
  // The em box centred in the cell's height, the glyph in its width.
  const baseline = (h - (glyphs.ascender - glyphs.descender) * scale) / 2 + glyphs.ascender * scale;
  const left = (w - glyphs.advance * scale) / 2;
  // White on black: the red channel is each pixel's coverage.
  g.fillStyle = '#000';
  g.fillRect(0, 0, canvas.width, canvas.height);
  g.fillStyle = '#fff';
  [...ramp].forEach((ch, i) => {
    const d = glyphs.paths[ch];
    if (!d) return;
    g.setTransform(scale, 0, 0, -scale, i * w + left, baseline);
    g.fill(new Path2D(d));
  });
  const texture = gl.createTexture()!;
  gl.bindTexture(gl.TEXTURE_2D, texture);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.R8, gl.RED, gl.UNSIGNED_BYTE, canvas.transferToImageBitmap());
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
  return texture;
}

function program(gl: WebGL2RenderingContext, vertex: string, fragment: string) {
  const p = gl.createProgram()!;
  for (const [type, source] of [[gl.VERTEX_SHADER, vertex], [gl.FRAGMENT_SHADER, fragment]] as const) {
    const s = gl.createShader(type)!;
    gl.shaderSource(s, source);
    gl.compileShader(s);
    gl.attachShader(p, s);
  }
  gl.linkProgram(p);
  if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(`AsciiChrome: ${gl.getProgramInfoLog(p)}`);
  return p;
}

function bindQuad(gl: WebGL2RenderingContext, p: WebGLProgram, quad: WebGLBuffer | null) {
  gl.bindBuffer(gl.ARRAY_BUFFER, quad);
  const at = gl.getAttribLocation(p, 'corner');
  gl.enableVertexAttribArray(at);
  gl.vertexAttribPointer(at, 2, gl.FLOAT, false, 0, 0);
}

function perspective(fov: number, aspect: number, near: number, far: number) {
  const f = 1 / Math.tan(fov / 2), nf = 1 / (near - far);
  return new Float32Array([f / aspect, 0, 0, 0, 0, f, 0, 0, 0, 0, (far + near) * nf, -1, 0, 0, 2 * far * near * nf, 0]);
}

const rgb = (hex: string) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255);
