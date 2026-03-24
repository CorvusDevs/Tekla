import SwiftUI

/// Displays word predictions above the keyboard.
/// The center slot is the primary (best) prediction, highlighted with the accent color.
struct PredictionBar: View {
    let predictions: [String]
    /// Index of the primary prediction (center slot).
    let primaryIndex: Int
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(predictions.enumerated()), id: \.offset) { index, word in
                Button {
                    onSelect(word)
                } label: {
                    Text(word)
                        .font(.body)
                        .fontWeight(index == primaryIndex ? .semibold : .regular)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(index == primaryIndex
                                      ? Color.accentColor.opacity(0.18)
                                      : Color.primary.opacity(0.05))
                        )
                        .padding(.horizontal, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(index == primaryIndex
                    ? String(localized: "\(word), primary suggestion")
                    : word)
            }

            // Always take up space so the bar doesn't collapse when empty
            if predictions.isEmpty {
                Text(String(localized: "Type to see suggestions"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
        }
        .frame(height: 36)
        .padding(.horizontal, 8)
    }
}
