// Rotations as [x, y, z, w] unit quaternions, the few operations the motion and the light renderer
// need, so neither has to load three.js.

export type Quat = [number, number, number, number];

export const identity = (): Quat => [0, 0, 0, 1];

/** The product a·b: b applied first, then a (three's multiplyQuaternions(a, b)). */
export function mul(a: Quat, b: Quat): Quat {
  const [ax, ay, az, aw] = a, [bx, by, bz, bw] = b;
  return [
    ax * bw + aw * bx + ay * bz - az * by,
    ay * bw + aw * by + az * bx - ax * bz,
    az * bw + aw * bz + ax * by - ay * bx,
    aw * bw - ax * bx - ay * by - az * bz,
  ];
}

export function axisAngle(x: number, y: number, z: number, angle: number): Quat {
  const s = Math.sin(angle / 2);
  return [x * s, y * s, z * s, Math.cos(angle / 2)];
}

/** Euler angles in radians, applied in three's 'YXZ' order (yaw, then pitch). */
export function yxz(pitch: number, yaw: number): Quat {
  const c1 = Math.cos(pitch / 2), c2 = Math.cos(yaw / 2), s1 = Math.sin(pitch / 2), s2 = Math.sin(yaw / 2);
  return [s1 * c2, c1 * s2, -s1 * s2, c1 * c2];
}

export function normalize(q: Quat): Quat {
  const l = Math.hypot(...q) || 1;
  return [q[0] / l, q[1] / l, q[2] / l, q[3] / l];
}

/** Spherical interpolation from a toward b by t. */
export function slerp(a: Quat, b: Quat, t: number): Quat {
  let cos = a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3];
  const s = cos < 0 ? -1 : 1;
  cos *= s;
  if (cos > 0.9995) return normalize(a.map((v, i) => v + (s * b[i] - v) * t) as Quat);
  const angle = Math.acos(cos), sin = Math.sin(angle);
  const ka = Math.sin((1 - t) * angle) / sin, kb = (s * Math.sin(t * angle)) / sin;
  return a.map((v, i) => v * ka + b[i] * kb) as Quat;
}

/** The rotation as a column-major 3×3 matrix, for a shader. */
export function matrix(q: Quat): Float32Array {
  const [x, y, z, w] = q;
  return new Float32Array([
    1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w),
    2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w),
    2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y),
  ]);
}
