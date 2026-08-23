import SwiftUI
import AppKit

/// Renders an extension's icon: an SF Symbol name (e.g. "note.text"), or a
/// custom svg/png/pdf file bundled inside the extension's own folder,
/// tinted to match the surrounding UI like a template image.
struct ExtensionIconImage: View {
    let iconValue: String
    let folderURL: URL?
    var size: CGFloat = 16

    private static let customExtensions = [".svg", ".png", ".pdf"]

    var body: some View {
        if let folderURL, Self.customExtensions.contains(where: { iconValue.hasSuffix($0) }),
           let nsImage = Self.loadTemplateImage(folderURL.appendingPathComponent(iconValue).path) {
            // Custom brand glyphs render visually smaller/thinner than SF Symbols
            // at the same box size, so scale them up a bit to match apparent weight.
            let customSize = size * 1.375
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: customSize, height: customSize)
        } else {
            Image(systemName: iconValue)
                .font(.system(size: size, weight: .medium))
        }
    }

    private static func loadTemplateImage(_ path: String) -> NSImage? {
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        image.isTemplate = true
        return image
    }
}
