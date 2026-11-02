// Every setting of the chrome effect. Lengths are in logo units: the logo's longer side is 1.
// AzaUI's ChromeSettings.swift mirrors this list; change both together.

export interface Setting {
  label: string;
  group: 'Shape' | 'Material' | 'View' | 'Motion';
  value: number;
  min: number;
  max: number;
  step: number;
}

export const settings = {
  depth: { label: 'Depth', group: 'Shape', value: 0.05, min: 0.005, max: 0.2, step: 0.001 },
  rimRadius: { label: 'Rim radius', group: 'Shape', value: 0.004, min: 0.0005, max: 0.02, step: 0.0005 },
  rimWidth: { label: 'Rim width', group: 'Shape', value: 0, min: 0, max: 0.015, step: 0.0005 },
  groove: { label: 'Groove', group: 'Shape', value: 0.004, min: 0, max: 0.01, step: 0.0005 },
  bevelWidth: { label: 'Bevel width', group: 'Shape', value: 0.016, min: 0, max: 0.035, step: 0.0005 },
  bevelCurve: { label: 'Bevel curve', group: 'Shape', value: 0, min: 0, max: 3, step: 0.05 },
  recess: { label: 'Face recess', group: 'Shape', value: -0.004, min: -0.015, max: 0.015, step: 0.0005 },
  dome: { label: 'Face dome', group: 'Shape', value: 0.01, min: -0.02, max: 0.04, step: 0.0005 },

  roughness: { label: 'Roughness', group: 'Material', value: 0.03, min: 0, max: 0.5, step: 0.005 },
  exposure: { label: 'Exposure', group: 'Material', value: 1.3, min: 0.2, max: 3, step: 0.01 },
  lightAngle: { label: 'Light angle', group: 'Material', value: 0, min: -180, max: 180, step: 1 },
  lightHeight: { label: 'Light height', group: 'Material', value: 0, min: -30, max: 30, step: 0.5 },

  pitch: { label: 'Pitch', group: 'View', value: 4, min: -45, max: 45, step: 0.5 },
  yaw: { label: 'Yaw', group: 'View', value: 5, min: -45, max: 45, step: 0.5 },
  fov: { label: 'Field of view', group: 'View', value: 30, min: 5, max: 70, step: 1 },
  scale: { label: 'Size', group: 'View', value: 1, min: 0.2, max: 2, step: 0.01 },

  friction: { label: 'Friction', group: 'Motion', value: 2.5, min: 0, max: 10, step: 0.1 },
  settle: { label: 'Settle', group: 'Motion', value: 1.2, min: 0, max: 10, step: 0.1 },
  cursorTilt: { label: 'Cursor tilt', group: 'Motion', value: 12, min: 0, max: 45, step: 0.5 },
  gyroTilt: { label: 'Gyro tilt', group: 'Motion', value: 20, min: 0, max: 60, step: 0.5 },
} satisfies Record<string, Setting>;

export type SettingName = keyof typeof settings;

/** The settings that move vertices; the rest only change the material, light or view. */
export const shapeSettings: SettingName[] = ['depth', 'rimRadius', 'rimWidth', 'groove', 'bevelWidth', 'bevelCurve', 'recess', 'dome'];
export type ChromeSettings = Record<SettingName, number>;

export const defaults = Object.fromEntries(
  Object.entries(settings).map(([name, s]) => [name, s.value]),
) as ChromeSettings;

export function resolve(partial: Partial<ChromeSettings> = {}): ChromeSettings {
  return { ...defaults, ...partial };
}
