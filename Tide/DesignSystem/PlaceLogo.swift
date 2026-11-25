import SwiftUI
import TideKit
import UIKit

/// What a place's logo looks like.
struct LogoAppearance: Equatable {
    var name: String
    var colorName: String?
    var emoji: String?
    var symbol: String?
    var imageData: Data?

    init(name: String, colorName: String? = nil, emoji: String? = nil, symbol: String? = nil, imageData: Data? = nil) {
        self.name = name
        self.colorName = colorName
        self.emoji = emoji
        self.symbol = symbol
        self.imageData = imageData
    }

    init(place: Place) {
        self.init(name: place.displayName, colorName: place.colorName, emoji: place.emoji,
                  symbol: place.symbol, imageData: place.logoData)
    }

    /// The chosen color, or a stable one derived from the name.
    var color: Color {
        if let colorName, !colorName.isEmpty { return TidePalette.color(named: colorName) }
        let names = TidePalette.names
        return TidePalette.color(named: names[PlaceName.colorIndex(name, paletteSize: names.count)])
    }
}

/// A round logo for where money was spent. In order of preference:
/// the place's photo, its emoji, its symbol, else a colored initial.
/// Entries without a place fall back to their category icon.
struct PlaceLogo: View {
    var appearance: LogoAppearance?
    var fallbackSymbol: String = "questionmark"
    var fallbackColor: Color = .gray
    var size: CGFloat = 44

    init(place: Place?, fallbackSymbol: String = "questionmark", fallbackColor: Color = .gray, size: CGFloat = 44) {
        self.appearance = place.map(LogoAppearance.init(place:))
        self.fallbackSymbol = fallbackSymbol
        self.fallbackColor = fallbackColor
        self.size = size
    }

    init(appearance: LogoAppearance, size: CGFloat = 44) {
        self.appearance = appearance
        self.size = size
    }

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(.circle)
            .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        if let logo = appearance {
            if let data = logo.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let emoji = logo.emoji, !emoji.isEmpty {
                Text(emoji)
                    .font(.system(size: size * 0.52))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(logo.color.opacity(0.22))
            } else if let symbol = logo.symbol, !symbol.isEmpty {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(logo.color.gradient)
            } else {
                Text(PlaceName.initial(logo.name))
                    .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(logo.color.gradient)
            }
        } else {
            Image(systemName: fallbackSymbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(fallbackColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(fallbackColor.opacity(0.18))
        }
    }
}

/// The logo for a transaction: its place, or its category icon.
struct EntryLogo: View {
    @ObservedObject var entry: LedgerEntry
    var size: CGFloat = 44

    var body: some View {
        PlaceLogo(place: entry.place,
                  fallbackSymbol: entry.category?.symbol ?? "questionmark",
                  fallbackColor: entry.category?.color ?? .gray,
                  size: size)
    }
}

enum LogoImage {
    /// Downscales a picked photo to a small square JPEG for storage.
    static func thumbnail(from data: Data, side: CGFloat = 256) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = side / min(image.size.width, image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let square = renderer.image { _ in
            image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                                  width: size.width, height: size.height))
        }
        return square.jpegData(compressionQuality: 0.8)
    }
}
