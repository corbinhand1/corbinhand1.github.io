//
//  PanelKit.swift
//  Cue to Cue
//
//  Shared building blocks for the app's panels (Connected Viewers, Users &
//  Permissions, Website): one header, one footer, native grouped forms.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

/// Icon tile, title and one line explaining what the panel is for.
struct PanelHeader: View {
    let systemImage: String
    let title: String
    let subtitle: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Bottom bar with optional leading content and a Done button (Return / Esc).
struct PanelFooter<Leading: View>: View {
    let leading: Leading
    let done: () -> Void

    init(@ViewBuilder leading: () -> Leading, done: @escaping () -> Void) {
        self.leading = leading()
        self.done = done
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                leading
                Spacer()
                // Esc closes. Not Return: panels can contain text fields, and
                // Return while typing must not close the panel.
                Button("Done", action: done)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(.bar)
        .onExitCommand(perform: done)
    }
}

extension PanelFooter where Leading == EmptyView {
    init(done: @escaping () -> Void) {
        self.init(leading: { EmptyView() }, done: done)
    }
}

/// QR code image for a string (used for the viewer join link).
enum QRCode {
    static func image(for string: String, size: CGFloat) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
