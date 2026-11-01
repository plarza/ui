import SwiftUI

/// The aza mark: an @ around an "a", drawn to fit any square.
nonisolated public struct AzaLogo: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / 1000
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * scale, y: origin.y + y * scale) }
        var path = Path()
        path.move(to: p(439.9, 482.7))
        path.addCurve(to: p(434.8, 476.1), control1: p(435.0, 476.6), control2: p(435.2, 476.6))
        path.addCurve(to: p(458.3, 531.6), control1: p(431.4, 472.6), control2: p(434.7, 478.6))
        path.addCurve(to: p(467.6, 552.3), control1: p(459.2, 533.7), control2: p(460.5, 536.3))
        path.addCurve(to: p(517.6, 666.9), control1: p(496.1, 616.3), control2: p(517.4, 662.9))
        path.addCurve(to: p(511.8, 734.9), control1: p(519.8, 729.4), control2: p(516.3, 731.8))
        path.addCurve(to: p(373.5, 736.6), control1: p(504.3, 740.0), control2: p(384.5, 736.9))
        path.addCurve(to: p(17.3, 451.7), control1: p(236.7, 733.1), control2: p(61.4, 609.3))
        path.addCurve(to: p(397.3, 42.9), control1: p(-80.6, 102.2), control2: p(355.6, 42.8))
        path.addCurve(to: p(997.5, 552.3), control1: p(714.1, 43.8), control2: p(982.1, 302.6))
        path.addCurve(to: p(411.3, 934.1), control1: p(1017.8, 882.6), control2: p(692.0, 1016.1))
        path.addCurve(to: p(223.6, 841.6), control1: p(337.7, 912.7), control2: p(252.2, 864.9))
        path.addCurve(to: p(235.1, 804.4), control1: p(206.9, 827.9), control2: p(223.8, 801.5))
        path.addCurve(to: p(591.8, 912.3), control1: p(243.9, 806.6), control2: p(407.5, 935.8))
        path.addCurve(to: p(859.9, 661.5), control1: p(713.0, 896.8), control2: p(830.3, 837.6))
        path.addCurve(to: p(860.2, 548.0), control1: p(862.3, 647.4), control2: p(863.6, 573.3))
        path.addCurve(to: p(762.5, 296.2), control1: p(851.9, 486.1), control2: p(825.6, 389.0))
        path.addCurve(to: p(185.7, 181.8), control1: p(579.7, 27.5), control2: p(300.2, 35.6))
        path.addCurve(to: p(346.5, 697.1), control1: p(59.5, 342.9), control2: p(157.9, 682.8))
        path.addCurve(to: p(329.3, 645.2), control1: p(349.0, 697.3), control2: p(347.5, 695.1))
        path.addCurve(to: p(195.2, 264.8), control1: p(197.6, 284.3), control2: p(196.1, 284.3))
        path.addCurve(to: p(202.6, 206.1), control1: p(192.6, 209.7), control2: p(198.1, 207.7))
        path.addCurve(to: p(447.0, 205.3), control1: p(210.6, 203.2), control2: p(427.4, 205.2))
        path.addCurve(to: p(799.6, 565.2), control1: p(464.2, 205.5), control2: p(723.4, 338.5))
        path.addCurve(to: p(687.9, 733.1), control1: p(859.6, 743.8), control2: p(739.5, 760.6))
        path.addCurve(to: p(439.9, 482.7), control1: p(663.0, 719.9), control2: p(656.5, 716.4))
        path.addLine(to: p(450.8, 441.6))
        path.addCurve(to: p(607.0, 588.1), control1: p(587.8, 583.6), control2: p(590.3, 584.2))
        path.addCurve(to: p(615.0, 384.6), control1: p(664.8, 601.6), control2: p(671.9, 509.2))
        path.addCurve(to: p(429.7, 338.3), control1: p(594.2, 338.9), control2: p(584.1, 338.4))
        path.addCurve(to: p(351.3, 340.2), control1: p(351.9, 338.2), control2: p(350.8, 339.2))
        path.addCurve(to: p(450.8, 441.6), control1: p(351.5, 340.6), control2: p(442.8, 433.4))
        path.addLine(to: p(439.9, 482.7))
        path.closeSubpath()
        return path
    }
}
