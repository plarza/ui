#if os(macOS)
import CoreImage.CIFilterBuiltins
import SwiftUI

/// A Mac signing in: the QR code to scan with the aza app on your phone, until it answers.
struct PhoneSignIn: View {
    let qr: String
    @Environment(Account.self) private var account
    @Environment(\.appInfo) private var app

    var body: some View {
        VStack(spacing: 18) {
            Text("Scan with the aza app")
                .font(.title2.weight(.semibold))
            QRCode(text: qr)
                .frame(width: 220, height: 220)
                .padding(14)
                .background(.white, in: .rect(cornerRadius: 20))
                .accessibilityLabel("QR code to sign in to \(app.name)")
                .accessibilityIdentifier("signIn.qr")
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for aza").foregroundStyle(.secondary)
            }
            .font(.callout)
            Button("Cancel") { account.cancelSignIn() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("signIn.cancel")
        }
        .padding(28)
    }
}

/// A QR code, sharp at any size.
struct QRCode: View {
    let text: String

    var body: some View {
        if let image = Self.image(text) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .aspectRatio(1, contentMode: .fit)
        }
    }

    private static func image(_ text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
#endif
