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

  constructor(canvas: HTMLCanvasElement | OffscreenCanvas, options: { preserveDrawingBuffer?: boolean } = {}) {
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
    this.renderer.setPixelRatio(pixelRatio);
    this.renderer.setSize(width, height, false);
    this.camera.aspect = width / height;
    this.frame();
  }

  render() {
    this.object.quaternion.multiplyQuaternions(this.motion, this.rest);
    this.renderer.render(this.scene, this.camera);
  }

  /** The mesh, for export. */
  get mesh() {
    return this.object;
  }

  dispose() {
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
        }`)
      .replace('#include <normal_fragment_begin>', `#include <normal_fragment_begin>
        vec2 chromeS = chromeSlope(vChromeD);
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
