// How the logo moves: drag to spin it, and it keeps spinning and slows (friction), then eases
// back to rest (settle). On top of that it leans toward the cursor, or with the phone (gyro), and
// it can sway on its own, as the CLI's sway video does. Plain maths, no three.js, so the light
// renderer (web/ascii) moves the same way.
// AzaUI's ChromeLogo.swift mirrors this; change both together.

import { axisAngle, identity, mul, normalize, slerp, yxz, type Quat } from './quat';
import type { ChromeSettings } from './settings';

const rad = Math.PI / 180;
/** One sway, side to side and back, in seconds; it nods twice in that time. */
const swayPeriod = 10;
/** Seconds the sway takes to grow from nothing, so the first frame is the rest pose. */
const swayEaseIn = 3;

export class Motion {
  /** The spin from dragging. */
  private spin: Quat = identity();
  /** Spin velocity in rad/s about screen x and y. */
  private velocity: [number, number] = [0, 0];
  private dragging = false;
  private recent: { t: number; dx: number; dy: number }[] = [];
  /** Lean, in [-1, 1] on each axis, and where it's heading. */
  private lean: [number, number] = [0, 0];
  private leanTarget: [number, number] = [0, 0];
  private leanScale = 0;
  private gyroRest?: [number, number];
  /** Seconds since the first step, and the sway at the last one, in degrees. */
  private time = 0;
  private sway = 0;

  /** True while the logo is still moving, so a renderer can stop drawing when it's still. */
  get moving() {
    const turned = 1 - Math.abs(this.spin[3]);
    const [vx, vy] = this.velocity, dx = this.lean[0] - this.leanTarget[0], dy = this.lean[1] - this.leanTarget[1];
    return this.sway > 0 || this.dragging || vx * vx + vy * vy > 1e-6 || turned > 1e-7 || dx * dx + dy * dy > 1e-7;
  }

  start() {
    this.dragging = true;
    this.velocity = [0, 0];
    this.recent = [];
  }

  /** A drag of (dx, dy) pixels on a view `size` pixels across: half the width turns it 90°. */
  drag(dx: number, dy: number, size: number, t = performance.now() / 1000) {
    const k = Math.PI / size;
    this.turn(dy * k, dx * k);
    this.recent.push({ t, dx: dx * k, dy: dy * k });
    while (this.recent.length > 1 && t - this.recent[0].t > 0.08) this.recent.shift();
  }

  end(t = performance.now() / 1000) {
    this.dragging = false;
    const span = this.recent.length > 1 ? t - this.recent[0].t : 0;
    if (span > 0.005 && t - this.recent[this.recent.length - 1].t < 0.05) {
      const sx = this.recent.reduce((s, m) => s + m.dy, 0), sy = this.recent.reduce((s, m) => s + m.dx, 0);
      this.velocity = [sx / span, sy / span];
    }
    this.recent = [];
  }

  /** The cursor relative to the logo, roughly -1 to 1 across the view. */
  pointer(x: number, y: number, s: ChromeSettings) {
    this.leanTarget = [clamp(y), clamp(x)];
    this.leanScale = s.cursorTilt;
  }

  pointerLeft() {
    this.leanTarget = [0, 0];
  }

  /** Device tilt in degrees (DeviceOrientationEvent's beta and gamma, or CoreMotion's pitch and roll). */
  gyro(beta: number, gamma: number, s: ChromeSettings) {
    // Lean relative to how the phone is usually held, which drifts slowly toward the current pose.
    const rest = this.gyroRest ?? [beta, gamma];
    this.gyroRest = [rest[0] + (beta - rest[0]) * 0.01, rest[1] + (gamma - rest[1]) * 0.01];
    this.leanTarget = [clamp(-(beta - this.gyroRest[0]) / 25), clamp(-(gamma - this.gyroRest[1]) / 25)];
    this.leanScale = s.gyroTilt;
  }

  /** Advance by dt seconds; returns the rotation to apply on top of the rest pose. */
  step(dt: number, s: ChromeSettings): Quat {
    dt = Math.min(dt, 0.1);
    if (!this.dragging) {
      this.turn(this.velocity[0] * dt, this.velocity[1] * dt);
      const f = Math.exp(-s.friction * dt);
      this.velocity = [this.velocity[0] * f, this.velocity[1] * f];
      // Settle back once the spin has mostly died down, so a flick still gets to spin.
      const speed = Math.hypot(...this.velocity);
      const pull = s.settle * Math.max(0, 1 - speed / 6);
      this.spin = slerp(this.spin, identity(), 1 - Math.exp(-pull * dt));
    }
    const k = 1 - Math.exp(-8 * dt);
    this.lean = [this.lean[0] + (this.leanTarget[0] - this.lean[0]) * k, this.lean[1] + (this.leanTarget[1] - this.lean[1]) * k];
    const lean = yxz(this.lean[0] * this.leanScale * rad, this.lean[1] * this.leanScale * rad);
    // The sway: a figure of eight, side to side (s.sway degrees) while nodding at twice the rate,
    // as the CLI's sway video; eased in from nothing.
    this.time += dt;
    const grow = Math.min(1, this.time / swayEaseIn);
    this.sway = s.sway * grow * grow * (3 - 2 * grow);
    const phase = (2 * Math.PI * this.time) / swayPeriod;
    const sway = yxz(this.sway * (9 / 28) * Math.sin(2 * phase) * rad, this.sway * Math.sin(phase) * rad);
    return mul(mul(sway, lean), this.spin);
  }

  private turn(aboutX: number, aboutY: number) {
    const q = mul(axisAngle(0, 1, 0, aboutY), axisAngle(1, 0, 0, aboutX));
    this.spin = normalize(mul(q, this.spin));
  }
}

const clamp = (v: number) => Math.max(-1, Math.min(1, v));
