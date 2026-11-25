import Foundation
import simd

/// How the logo moves: drag to spin it, and it keeps spinning and slows (friction), then eases back
/// to rest (settle). On top of that it leans toward the pointer, or with the phone, and it can sway
/// on its own, as the CLI's sway video does.
/// Mirrors web/chrome/motion.ts; change both together.
final class ChromeMotion {
    private var spin = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    /// Spin velocity in rad/s about screen x and y.
    private var velocity: SIMD2<Float> = .zero
    private(set) var dragging = false
    private var lean: SIMD2<Float> = .zero
    private var leanTarget: SIMD2<Float> = .zero
    private var leanScale: Float = 0
    private var gyroRest: SIMD2<Float>?
    /// Seconds since the first step, and the sway at the last one, in degrees.
    private var time: Float = 0
    private(set) var sway: Float = 0
    /// One sway, side to side and back, in seconds; it nods twice in that time.
    private let swayPeriod: Float = 10
    /// Seconds the sway takes to grow from nothing, so the first frame is the rest pose.
    private let swayEaseIn: Float = 3

    func start() {
        dragging = true
        velocity = .zero
    }

    /// A drag of (dx, dy) points on a view `size` points across: half the width turns it 90°.
    func drag(dx: Float, dy: Float, size: Float) {
        let k = Float.pi / size
        turn(aboutX: dy * k, aboutY: dx * k)
    }

    /// Release with the gesture's velocity in points per second.
    func end(velocity v: SIMD2<Float>, size: Float) {
        dragging = false
        velocity = SIMD2(v.y, v.x) * (Float.pi / size)
    }

    /// The pointer relative to the logo, about -1 to 1 across the view.
    func pointer(x: Float, y: Float, _ s: ChromeSettings) {
        leanTarget = SIMD2(clamp(y), clamp(x))
        leanScale = s.cursorTilt
    }

    func pointerLeft() {
        leanTarget = .zero
    }

    /// Device tilt in degrees: pitch (front to back) and roll (side to side).
    func gyro(pitch: Float, roll: Float, _ s: ChromeSettings) {
        // Lean relative to how the phone is usually held, which drifts slowly toward the current pose.
        let now = SIMD2(pitch, roll)
        let rest = simd_mix(gyroRest ?? now, now, SIMD2(repeating: 0.01))
        gyroRest = rest
        let d = (now - rest) / 25
        leanTarget = SIMD2(clamp(-d.x), clamp(-d.y))
        leanScale = s.gyroTilt
    }

    /// Advance by dt seconds; returns the rotation to apply on top of the rest pose.
    func step(_ dt: Float, _ s: ChromeSettings) -> simd_quatf {
        let dt = min(dt, 0.1)
        if !dragging {
            turn(aboutX: velocity.x * dt, aboutY: velocity.y * dt)
            velocity *= exp(-s.friction * dt)
            // Settle back once the spin has mostly died down, so a flick still gets to spin.
            let pull = s.settle * max(0, 1 - simd_length(velocity) / 6)
            spin = simd_slerp(spin, simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), 1 - exp(-pull * dt))
        }
        lean = simd_mix(lean, leanTarget, SIMD2(repeating: 1 - exp(-8 * dt)))
        let rad = Float.pi / 180
        let leanRotation = simd_quatf(angle: lean.y * leanScale * rad, axis: [0, 1, 0])
            * simd_quatf(angle: lean.x * leanScale * rad, axis: [1, 0, 0])
        // The sway: a figure of eight, side to side (s.sway degrees) while nodding at twice the
        // rate, as the CLI's sway video; eased in from nothing.
        time += dt
        let grow = min(1, time / swayEaseIn)
        sway = s.sway * grow * grow * (3 - 2 * grow)
        let phase = 2 * Float.pi * time / swayPeriod
        let swayRotation = simd_quatf(angle: sway * sin(phase) * rad, axis: [0, 1, 0])
            * simd_quatf(angle: sway * (9 / 28) * sin(2 * phase) * rad, axis: [1, 0, 0])
        return swayRotation * leanRotation * spin
    }

    private func turn(aboutX: Float, aboutY: Float) {
        let q = simd_quatf(angle: aboutY, axis: [0, 1, 0]) * simd_quatf(angle: aboutX, axis: [1, 0, 0])
        spin = simd_normalize(q * spin)
    }

    private func clamp(_ v: Float) -> Float { min(1, max(-1, v)) }
}
