import CoreGraphics
import Foundation
import ImageIO

/// What the chrome reflects: a photographed studio, stored as an 8-bit grey AVIF of log₂
/// brightness from 2^-10 to 2^7 (about 20 KB each). Mirrors web/chrome/studios.ts; only the
/// studio a logo uses is ever read.
public enum ChromeStudio: String, CaseIterable, Sendable {
    case monochrome, broadway, countryHall, christmas, kominka, white, brown, wizja, london, neon, blocky

    nonisolated static let lo: Float = -10, hi: Float = 7

    /// The studio as linear brightness, the way `EnvironmentResource(equirectangular:)` wants it.
    nonisolated func image() throws -> CGImage {
        guard let url = Bundle.module.url(forResource: rawValue, withExtension: "avif", subdirectory: "Studios"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let encoded = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw CocoaError(.fileReadCorruptFile) }
        let width = encoded.width, height = encoded.height

        // The stored values, not colour-managed ones: draw into a grey context in the image's own space.
        var grey = [UInt8](repeating: 0, count: width * height)
        let space = encoded.colorSpace?.model == .monochrome ? encoded.colorSpace! : CGColorSpaceCreateDeviceGray()
        grey.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width, space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue)
            context?.draw(encoded, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        let table = (0..<256).map { exp2(Self.lo + Float($0) / 255 * (Self.hi - Self.lo)) }
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for i in 0..<(width * height) {
            let l = table[Int(grey[i])]
            pixels[4 * i] = l; pixels[4 * i + 1] = l; pixels[4 * i + 2] = l
        }
        let data = pixels.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData),
              let linear = CGColorSpace(name: CGColorSpace.linearSRGB),
              let image = CGImage(width: width, height: height, bitsPerComponent: 32, bitsPerPixel: 128,
                                  bytesPerRow: width * 16, space: linear,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue
                                      | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw CocoaError(.fileReadCorruptFile) }
        return image
    }
}
