// How the logo moves: drag to spin it, and it keeps spinning and slows (friction), then eases
// back to rest (settle). On top of that it leans toward the cursor, or with the phone (gyro).
// AzaUI's ChromeLogo.swift mirrors this; change both together.

import * as THREE from 'three';
import type { ChromeSettings } from './settings';

const rad = Math.PI / 180;
const yAxis = new THREE.Vector3(0, 1, 0), xAxis = new THREE.Vector3(1, 0, 0);

export class Motion {
  /** The spin from dragging. */
  private spin = new THREE.Quaternion();
  /** Spin velocity in rad/s about screen x and y. */
  private velocity = new THREE.Vector2();
  private dragging = false;
  private recent: { t: number; dx: number; dy: number }[] = [];
  /** Lean, in [-1, 1] on each axis, and where it's heading. */
  private lean = new THREE.Vector2();
  private leanTarget = new THREE.Vector2();
  private leanScale = 0;
  private gyroRest?: THREE.Vector2;
  private out = new THREE.Quaternion();

  /** True while the logo is still moving, so a renderer can stop drawing when it's still. */
  get moving() {
    const turned = 1 - Math.abs(this.spin.w);
    return this.dragging || this.velocity.lengthSq() > 1e-6 || turned > 1e-7 || this.lean.distanceToSquared(this.leanTarget) > 1e-7;
  }

  start() {
    this.dragging = true;
    this.velocity.set(0, 0);
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
      const sum = this.recent.reduce((s, m) => s.add(new THREE.Vector2(m.dy, m.dx)), new THREE.Vector2());
      this.velocity.copy(sum.divideScalar(span));
    }
    this.recent = [];
  }

  /** The cursor relative to the logo, roughly -1 to 1 across the view. */
  pointer(x: number, y: number, s: ChromeSettings) {
    this.leanTarget.set(clamp(y), clamp(x));
    this.leanScale = s.cursorTilt;
  }

  pointerLeft() {
    this.leanTarget.set(0, 0);
  }

  /** Device tilt in degrees (DeviceOrientationEvent's beta and gamma, or CoreMotion's pitch and roll). */
  gyro(beta: number, gamma: number, s: ChromeSettings) {
    // Lean relative to how the phone is usually held, which drifts slowly toward the current pose.
    const now = new THREE.Vector2(beta, gamma);
    this.gyroRest ??= now.clone();
    this.gyroRest.lerp(now, 0.01);
    const d = now.clone().sub(this.gyroRest).divideScalar(25);
    this.leanTarget.set(clamp(-d.x), clamp(-d.y));
    this.leanScale = s.gyroTilt;
  }

  /** Advance by dt seconds; returns the rotation to apply on top of the rest pose. */
  step(dt: number, s: ChromeSettings): THREE.Quaternion {
    dt = Math.min(dt, 0.1);
    if (!this.dragging) {
      this.turn(this.velocity.x * dt, this.velocity.y * dt);
      this.velocity.multiplyScalar(Math.exp(-s.friction * dt));
      // Settle back once the spin has mostly died down, so a flick still gets to spin.
      const speed = this.velocity.length();
      const pull = s.settle * Math.max(0, 1 - speed / 6);
      this.spin.slerp(new THREE.Quaternion(), 1 - Math.exp(-pull * dt));
    }
    this.lean.lerp(this.leanTarget, 1 - Math.exp(-8 * dt));
    const lean = new THREE.Quaternion().setFromEuler(
      new THREE.Euler(this.lean.x * this.leanScale * rad, this.lean.y * this.leanScale * rad, 0, 'YXZ'));
    return this.out.multiplyQuaternions(lean, this.spin);
  }

  private turn(aboutX: number, aboutY: number) {
    const q = new THREE.Quaternion().setFromAxisAngle(yAxis, aboutY)
      .multiply(new THREE.Quaternion().setFromAxisAngle(xAxis, aboutX));
    this.spin.premultiply(q).normalize();
  }
}

const clamp = (v: number) => Math.max(-1, Math.min(1, v));
