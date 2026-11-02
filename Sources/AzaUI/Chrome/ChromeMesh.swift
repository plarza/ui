import Foundation
import RealityKit

/// The flat layout of a logo's front face, as the chrome-logo CLI writes it (`.chromelayout`):
/// points on rings that follow the outline inward, each with its distance from the outline and the
/// inward direction there, and the triangles between them. See web/chrome/layout.ts.
nonisolated struct ChromeLayout: Sendable {
    var x: [Float], y: [Float], d: [Float], gx: [Float], gy: [Float]
    /// The outline inflated like a membrane, and its slope: what the face dome is shaped from.
    var u: [Float], ux: [Float], uy: [Float]
    var triangles: [UInt32]
    /// The outline as (start, count) runs of points, filled side on the left.
    var loops: [(start: Int, count: Int)]

    var points: Int { x.count }
    var wallPoints: Int { loops.reduce(0) { $0 + $1.count } }
    var vertexCount: Int { 2 * points + 2 * wallPoints }

    init(contentsOf url: URL) throws {
        let packed = try Data(contentsOf: url)
        let data = try (packed as NSData).decompressed(using: .zlib) as Data
        var at = 0
        func u32() -> UInt32 {
            defer { at += 4 }
            return data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: at, as: UInt32.self)) }
        }
        func f32s(_ n: Int) -> [Float] {
            defer { at += 4 * n }
            return data.withUnsafeBytes { raw in
                (0..<n).map { Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: at + 4 * $0, as: UInt32.self))) }
            }
        }
        guard u32() == 0x4c43_5a41, u32() == 2 else { throw CocoaError(.fileReadCorruptFile) }
        let n = Int(u32()), t = Int(u32()), l = Int(u32())
        loops = (0..<l).map { _ in (Int(u32()), Int(u32())) }
        x = f32s(n); y = f32s(n); d = f32s(n); gx = f32s(n); gy = f32s(n)
        u = f32s(n); ux = f32s(n); uy = f32s(n)
        triangles = data.withUnsafeBytes { raw in
            (0..<3 * t).map { UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: at + 4 * $0, as: UInt32.self)) }
        }
    }

    /// Front faces, mirrored back faces, then the walls: a quad per outline edge.
    func indices() -> [UInt32] {
        let n = UInt32(points)
        var out = triangles
        out.reserveCapacity(triangles.count * 2 + wallPoints * 6)
        for t in stride(from: 0, to: triangles.count, by: 3) {
            out += [triangles[t] + n, triangles[t + 2] + n, triangles[t + 1] + n]
        }
        var base = 2 * n
        for loop in loops {
            let count = UInt32(loop.count)
            for k in 0..<count {
                let top = base + 2 * k, bottom = top + 1
                let top2 = base + 2 * ((k + 1) % count), bottom2 = top2 + 1
                out += [top, bottom, top2, bottom, bottom2, top2]
            }
            base += 2 * count
        }
        return out
    }

    /// Writes interleaved position and normal (six floats per vertex) for these settings.
    func shape(_ s: ChromeSettings, into v: UnsafeMutableBufferPointer<Float>) {
        let n = points
        for i in 0..<n {
            let (h, across, up) = bevel(d[i], s)
            let (lift, dx, dy) = dome(u[i], ux[i], uy[i], s)
            // Slopes add: the normal is the bevel's, leaned by the dome's slope.
            let nx = -across * gx[i] - up * dx, ny = -across * gy[i] - up * dy
            let len = max((nx * nx + ny * ny + up * up).squareRoot(), 1e-9)
            let z = h + lift
            write(v, i, x[i], y[i], z, nx / len, ny / len, up / len)
            write(v, n + i, x[i], y[i], -z, nx / len, ny / len, -up / len)
        }
        let wall = bevel(0, s).z
        var at = 2 * n
        for loop in loops {
            for p in loop.start..<(loop.start + loop.count) {
                write(v, at, x[p], y[p], wall, -gx[p], -gy[p], 0)
                write(v, at + 1, x[p], y[p], -wall, -gx[p], -gy[p], 0)
                at += 2
            }
        }
    }

    private func write(_ v: UnsafeMutableBufferPointer<Float>, _ i: Int, _ a: Float, _ b: Float, _ c: Float, _ d: Float, _ e: Float, _ f: Float) {
        let o = 6 * i
        v[o] = a; v[o + 1] = b; v[o + 2] = c; v[o + 3] = d; v[o + 4] = e; v[o + 5] = f
    }
}

/// The cross-section of the front face at distance `d` inside the outline: a rounded rim off the
/// side wall, a flat rim top, its inner side rounding down into a groove, a bevel to the face,
/// then the face. `dome` then lifts the whole front. Returns the height and the slope as
/// a unit vector: the normal is `-across` along the inward direction plus `up` along +z.
/// Mirrors web/chrome/bevel.ts; change both together.
nonisolated func bevel(_ d: Float, _ s: ChromeSettings) -> (z: Float, across: Float, up: Float) {
    let top = s.depth / 2
    let r = min(s.rimRadius, top)
    if d < r {
        let x = r - d, y = (max(r * r - x * x, 0)).squareRoot()
        return (top - r + y, x / r, y / r)
    }
    var at = d - r
    if at < s.rimWidth { return (top, 0, 1) }
    at -= s.rimWidth
    // The rim's inner side rounds down into the groove: a quarter circle as deep as it is wide.
    let g = s.groove
    if at < g {
        let y = (max(g * g - at * at, 0)).squareRoot()
        return (top - g + y, -at / g, y / g)
    }
    at -= g
    let k = 1 + s.bevelCurve
    func unit(_ slope: Float) -> (Float, Float) {
        let n = (slope * slope + 1).squareRoot()
        return (slope / n, 1 / n)
    }
    if at < s.bevelWidth {
        let t = at / s.bevelWidth
        let fall = s.recess - g
        let (a, u) = unit(-fall * k * pow(t, k - 1) / s.bevelWidth)
        return (top - g - fall * pow(t, k), a, u)
    }
    return (top - s.recess, 0, 1)
}

/// The face dome at inflation `u` with slope (ux, uy): height and its slope. The height grows with
/// the square root of inflation, which curves each stroke like a cushion across its whole width.
/// Mirrors web/chrome/bevel.ts's `dome`.
nonisolated func dome(_ u: Float, _ ux: Float, _ uy: Float, _ s: ChromeSettings) -> (z: Float, dx: Float, dy: Float) {
    let soft: Float = 0.0001, unit: Float = 0.001
    let k = s.dome / unit.squareRoot()
    let root = (max(u, 0) + soft).squareRoot()
    let lean = k / (2 * root)
    return (k * (root - soft.squareRoot()), lean * ux, lean * uy)
}

/// A RealityKit mesh of the layout whose vertices are rewritten in place when the shape changes.
final class ChromeMesh {
    let layout: ChromeLayout
    let mesh: LowLevelMesh
    let resource: MeshResource

    init(layout: ChromeLayout, settings: ChromeSettings) throws {
        self.layout = layout
        let indices = layout.indices()
        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexCapacity = layout.vertexCount
        descriptor.indexCapacity = indices.count
        descriptor.vertexAttributes = [
            .init(semantic: .position, format: .float3, offset: 0),
            .init(semantic: .normal, format: .float3, offset: 12),
        ]
        descriptor.vertexLayouts = [.init(bufferIndex: 0, bufferStride: 24)]
        descriptor.indexType = .uint32
        mesh = try LowLevelMesh(descriptor: descriptor)
        mesh.withUnsafeMutableIndices { raw in
            let out = raw.bindMemory(to: UInt32.self)
            for (i, index) in indices.enumerated() { out[i] = index }
        }
        resource = try MeshResource(from: mesh)
        update(settings)
    }

    func update(_ s: ChromeSettings) {
        var half: Float = 0
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let vertices = raw.bindMemory(to: Float.self)
            layout.shape(s, into: vertices)
            // The dome lifts the face above the walls, so measure rather than assume.
            for z in stride(from: 2, to: vertices.count, by: 6) { half = max(half, abs(vertices[z])) }
        }
        mesh.parts.replaceAll([
            LowLevelMesh.Part(indexCount: mesh.descriptor.indexCapacity, topology: .triangle,
                              bounds: BoundingBox(min: [-0.5, -0.5, -half], max: [0.5, 0.5, half])),
        ])
    }
}
