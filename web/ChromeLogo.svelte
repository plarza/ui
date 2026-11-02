<!--
  An SVG as a polished chrome object you can spin. Drag it and it keeps turning, then settles;
  it leans toward the cursor, and on phones with the phone. Any filled SVG works; strokes
  become outlines. Without `svg` it shows the aza mark.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import aza from '../assets/aza.svg?raw';
  import { build } from './chrome/build';
  import { Motion } from './chrome/motion';
  import { ChromeScene } from './chrome/scene';
  import { resolve, type ChromeSettings } from './chrome/settings';
  import { load } from './chrome/studio';
  import { defaultStudio, studios, type StudioName } from './chrome/studios';

  const studioURL = (studio: string) => (studio in studios ? studios[studio as StudioName].url.href : studio);

  interface Props {
    /** SVG markup. */
    svg?: string;
    settings?: Partial<ChromeSettings>;
    /** What the chrome reflects: one of `studios`, or the URL of an equirectangular .hdr or studio .avif. */
    studio?: StudioName | (string & {});
    /** Drag, cursor and gyro. Off gives a still. */
    interactive?: boolean;
    label?: string;
    class?: string;
    style?: string;
  }

  let { svg = aza, settings = {}, studio = defaultStudio, interactive = true, label = 'Logo', class: className = '', style = '' }: Props = $props();

  let box: HTMLDivElement;
  let canvas: HTMLCanvasElement;
  let scene: ChromeScene | undefined = $state();
  let shaped = $state(false);
  let lit = $state(false);
  const ready = $derived(shaped && lit);
  const motion = new Motion();
  const maxPixels = 6e6;
  const resolved = $derived(resolve(settings));
  let dirty = true;

  $effect(() => {
    scene?.setSettings(resolved);
    dirty = true;
  });

  $effect(() => {
    if (!scene) return;
    const current = scene;
    let stale = false;
    build(svg).then((layout) => {
      if (stale) return;
      current.setLayout(layout);
      shaped = true;
      dirty = true;
    }, (error) => console.error('ChromeLogo:', error));
    return () => { stale = true; };
  });

  $effect(() => {
    if (!scene) return;
    const current = scene;
    let stale = false;
    fetch(studioURL(studio)).then((r) => r.arrayBuffer()).then(load).then((loaded) => {
      if (stale) return;
      current.setStudio(loaded);
      lit = true;
      dirty = true;
    }, (error) => console.error('ChromeLogo studio:', error));
    return () => { stale = true; };
  });

  onMount(() => {
    const s = new ChromeScene(canvas);
    scene = s;
    let visible = true, frame = 0, last = performance.now();

    const size = () => {
      const r = box.getBoundingClientRect();
      const w = Math.max(1, r.width), h = Math.max(1, r.height);
      // Draw at twice the screen's resolution when the pixel budget allows; the browser averages it
      // down, which smooths the thin rim highlights that multisampling alone leaves jagged.
      s.resize(w, h, Math.max(Math.min(devicePixelRatio, 2), Math.min(2 * devicePixelRatio, Math.sqrt(maxPixels / (w * h)))));
      dirty = true;
    };
    const resize = new ResizeObserver(size);
    resize.observe(box);
    const seen = new IntersectionObserver(([e]) => { visible = e.isIntersecting; });
    seen.observe(box);

    const tick = (now: number) => {
      frame = requestAnimationFrame(tick);
      const dt = (now - last) / 1000;
      last = now;
      if (!visible || !ready) return;
      if (motion.moving || dirty) {
        s.setMotion(motion.step(dt, resolved));
        s.render();
        dirty = false;
      }
    };
    frame = requestAnimationFrame(tick);

    // The cursor anywhere on the page: the logo leans toward it.
    const hover = (e: PointerEvent) => {
      if (!interactive || e.pointerType !== 'mouse') return;
      const r = box.getBoundingClientRect();
      motion.pointer((e.clientX - (r.left + r.width / 2)) / (innerWidth / 2), (e.clientY - (r.top + r.height / 2)) / (innerHeight / 2), resolved);
    };
    const leave = () => motion.pointerLeft();
    const tilt = (e: DeviceOrientationEvent) => {
      if (interactive && e.beta !== null && e.gamma !== null) motion.gyro(e.beta, e.gamma, resolved);
    };
    addEventListener('pointermove', hover);
    document.documentElement.addEventListener('pointerleave', leave);
    addEventListener('deviceorientation', tilt);

    return () => {
      cancelAnimationFrame(frame);
      resize.disconnect();
      seen.disconnect();
      removeEventListener('pointermove', hover);
      document.documentElement.removeEventListener('pointerleave', leave);
      removeEventListener('deviceorientation', tilt);
      s.dispose();
    };
  });

  let dragging: { x: number; y: number } | undefined;
  let askedForMotion = false;

  function down(e: PointerEvent) {
    if (!interactive) return;
    canvas.setPointerCapture(e.pointerId);
    dragging = { x: e.clientX, y: e.clientY };
    motion.start();
    // iOS only lets a page read the gyro after asking, from a tap.
    const D = DeviceOrientationEvent as unknown as { requestPermission?: () => Promise<string> };
    if (!askedForMotion && D.requestPermission) {
      askedForMotion = true;
      D.requestPermission().catch(() => {});
    }
  }

  function move(e: PointerEvent) {
    if (!dragging) return;
    motion.drag(e.clientX - dragging.x, e.clientY - dragging.y, Math.min(box.clientWidth, box.clientHeight));
    dragging = { x: e.clientX, y: e.clientY };
  }

  function up() {
    if (!dragging) return;
    dragging = undefined;
    motion.end();
  }
</script>

<div bind:this={box} class="chrome-logo {className}" {style} role="img" aria-label={label}>
  <canvas
    bind:this={canvas}
    class:interactive
    class:ready
    onpointerdown={down}
    onpointermove={move}
    onpointerup={up}
    onpointercancel={up}
  ></canvas>
</div>

<style>
  .chrome-logo {
    position: relative;
    aspect-ratio: 1;
  }
  canvas {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    opacity: 0;
    transition: opacity 0.3s;
  }
  canvas.ready {
    opacity: 1;
  }
  canvas.interactive {
    cursor: grab;
    touch-action: none;
  }
  canvas.interactive:active {
    cursor: grabbing;
  }
</style>
