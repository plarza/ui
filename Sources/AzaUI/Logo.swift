import SwiftUI

/// The aza mark: an @ around an "a", drawn to fit any square.
nonisolated struct AzaLogo: Shape {
    init() {}

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / 1000
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * scale, y: origin.y + y * scale) }
        var path = Path()
        path.move(to: p(560.1, 482.7))
        path.addCurve(to: p(565.2, 476.1), control1: p(565.0, 476.6), control2: p(564.8, 476.6))
        path.addCurve(to: p(541.7, 531.6), control1: p(568.6, 472.6), control2: p(565.3, 478.6))
        path.addCurve(to: p(532.4, 552.3), control1: p(540.8, 533.7), control2: p(539.5, 536.3))
        path.addCurve(to: p(482.4, 666.9), control1: p(503.9, 616.3), control2: p(482.6, 662.9))
        path.addCurve(to: p(488.2, 734.9), control1: p(480.2, 729.4), control2: p(483.7, 731.8))
        path.addCurve(to: p(626.5, 736.6), control1: p(495.7, 740.0), control2: p(615.5, 736.9))
        path.addCurve(to: p(982.7, 451.7), control1: p(763.3, 733.1), control2: p(938.6, 609.3))
        path.addCurve(to: p(602.7, 42.9), control1: p(1080.6, 102.2), control2: p(644.4, 42.8))
        path.addCurve(to: p(2.5, 552.3), control1: p(285.9, 43.8), control2: p(17.9, 302.6))
        path.addCurve(to: p(588.7, 934.1), control1: p(-17.8, 882.6), control2: p(308.0, 1016.1))
        path.addCurve(to: p(776.4, 841.6), control1: p(662.3, 912.7), control2: p(747.8, 864.9))
        path.addCurve(to: p(764.9, 804.4), control1: p(793.1, 827.9), control2: p(776.2, 801.5))
        path.addCurve(to: p(408.2, 912.3), control1: p(756.1, 806.6), control2: p(592.5, 935.8))
        path.addCurve(to: p(140.1, 661.5), control1: p(287.0, 896.8), control2: p(169.7, 837.6))
        path.addCurve(to: p(139.8, 548.0), control1: p(137.7, 647.4), control2: p(136.4, 573.3))
        path.addCurve(to: p(237.5, 296.2), control1: p(148.1, 486.1), control2: p(174.4, 389.0))
        path.addCurve(to: p(814.3, 181.8), control1: p(420.3, 27.5), control2: p(699.8, 35.6))
        path.addCurve(to: p(653.5, 697.1), control1: p(940.5, 342.9), control2: p(842.1, 682.8))
        path.addCurve(to: p(670.7, 645.2), control1: p(651.0, 697.3), control2: p(652.5, 695.1))
        path.addCurve(to: p(804.8, 264.8), control1: p(802.4, 284.3), control2: p(803.9, 284.3))
        path.addCurve(to: p(797.4, 206.1), control1: p(807.4, 209.7), control2: p(801.9, 207.7))
        path.addCurve(to: p(553.0, 205.3), control1: p(789.4, 203.2), control2: p(572.6, 205.2))
        path.addCurve(to: p(200.4, 565.2), control1: p(535.8, 205.5), control2: p(276.6, 338.5))
        path.addCurve(to: p(312.1, 733.1), control1: p(140.4, 743.8), control2: p(260.5, 760.6))
        path.addCurve(to: p(560.1, 482.7), control1: p(337.0, 719.9), control2: p(343.5, 716.4))
        path.addLine(to: p(549.2, 441.6))
        path.addCurve(to: p(393.0, 588.1), control1: p(412.2, 583.6), control2: p(409.7, 584.2))
        path.addCurve(to: p(385.0, 384.6), control1: p(335.2, 601.6), control2: p(328.1, 509.2))
        path.addCurve(to: p(570.3, 338.3), control1: p(405.8, 338.9), control2: p(415.9, 338.4))
        path.addCurve(to: p(648.7, 340.2), control1: p(648.1, 338.2), control2: p(649.2, 339.2))
        path.addCurve(to: p(549.2, 441.6), control1: p(648.5, 340.6), control2: p(557.2, 433.4))
        path.addLine(to: p(560.1, 482.7))
        path.closeSubpath()
        return path
    }
}
