import Foundation

/// Every setting of the chrome effect. Lengths are in logo units: the logo's longer side is 1.
/// Mirrors web/chrome/settings.ts, which has each setting's range; change both together.
public struct ChromeSettings: Equatable, Sendable {
    // Shape
    public var depth: Float = 0.05
    public var rimRadius: Float = 0.004
    public var rimWidth: Float = 0
    public var groove: Float = 0.004
    public var bevelWidth: Float = 0.016
    public var bevelCurve: Float = 0
    public var recess: Float = -0.004
    public var dome: Float = 0.01

    // Material
    public var roughness: Float = 0.03
    public var exposure: Float = 1.3
    /// Degrees the studio turns around the logo.
    public var lightAngle: Float = 0
    /// Degrees the studio tilts.
    public var lightHeight: Float = 0

    // View, in degrees
    public var pitch: Float = 4
    public var yaw: Float = 5
    public var fov: Float = 30
    /// How much of the view the logo fills; 1 leaves a small margin.
    public var scale: Float = 1

    // Motion
    /// How fast a flick slows down, per second.
    public var friction: Float = 2.5
    /// How fast it returns to rest once the spin has died down.
    public var settle: Float = 1.2
    /// Degrees it leans toward the pointer.
    public var cursorTilt: Float = 12
    /// Degrees it leans with the phone.
    public var gyroTilt: Float = 20

    public init() {}

    var shape: [Float] { [depth, rimRadius, rimWidth, groove, bevelWidth, bevelCurve, recess, dome] }
}
