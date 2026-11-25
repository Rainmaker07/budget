import SwiftUI

/// A grid of SF Symbols to choose an icon from.
struct IconPicker: View {
    @Binding var selection: String
    var color: Color

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(CategoryStore.iconChoices, id: \.self) { symbol in
                let isSelected = symbol == selection
                Button {
                    selection = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : color)
                        .frame(width: 44, height: 44)
                        .background(isSelected ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(0.14)), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// A row of color swatches from Tide's palette.
struct ColorSwatchPicker: View {
    @Binding var selection: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(TidePalette.names, id: \.self) { name in
                let isSelected = name == selection
                Button {
                    selection = name
                } label: {
                    Circle()
                        .fill(TidePalette.color(named: name).gradient)
                        .frame(width: 36, height: 36)
                        .overlay {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .overlay(Circle().strokeBorder(.white.opacity(isSelected ? 0.9 : 0), lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}
