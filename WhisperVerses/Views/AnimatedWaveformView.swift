import SwiftUI

/// Horizontal LED-segment audio meter — broadcast cockpit convention.
/// Fills left-to-right as level rises; first 60% is green, next 20% gold, top 20% coral.
struct AnimatedWaveformView: View {
    let level: Float
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let segmentCount = 18

    private var normalizedLevel: Double {
        Double(min(max(level * 3, 0), 1))
    }

    var body: some View {
        GeometryReader { geometry in
            let totalSegments = segmentCount
            let lit = isActive ? Int((normalizedLevel * Double(totalSegments)).rounded()) : 0
            let segmentSpacing: CGFloat = 1
            let segmentWidth = max(1, (geometry.size.width - CGFloat(totalSegments - 1) * segmentSpacing) / CGFloat(totalSegments))

            HStack(spacing: segmentSpacing) {
                ForEach(0..<totalSegments, id: \.self) { idx in
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(color(for: idx, lit: lit))
                        .frame(width: segmentWidth)
                }
            }
            .frame(maxHeight: .infinity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.06), value: lit)
        }
    }

    /// LED color for a given segment index, given how many are currently lit.
    private func color(for index: Int, lit: Int) -> Color {
        let isLit = index < lit
        let position = Double(index) / Double(segmentCount)

        let color: Color
        if position < 0.6 {
            color = Theme.Brand.green
        } else if position < 0.8 {
            color = Theme.Brand.gold
        } else {
            color = Theme.Status.live
        }

        return isLit ? color : color.opacity(0.10)
    }
}
