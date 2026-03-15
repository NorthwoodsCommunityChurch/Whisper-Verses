import SwiftUI

struct AnimatedWaveformView: View {
    let level: Float
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var barOffsets: [Double] = [0, 0.2, 0.4, 0.1, 0.3]
    @State private var animationPhase: Double = 0

    private let barCount = 5

    private var normalizedLevel: Double {
        Double(min(max(level * 3, 0), 1))
    }

    private var levelColor: Color {
        if normalizedLevel > 0.8 {
            return .red
        } else if normalizedLevel > 0.5 {
            return .yellow
        } else {
            return .green
        }
    }

    var body: some View {
        if reduceMotion {
            // Fallback: simple bar like the original AudioLevelView
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(levelColor)
                        .frame(width: geometry.size.width * normalizedLevel)
                }
            }
        } else {
            // Animated multi-bar waveform
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(0..<barCount, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(isActive ? levelColor : Color.gray.opacity(0.3))
                            .frame(height: barHeight(for: index, in: geometry.size.height))
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                }
                .animation(.spring(response: 0.15, dampingFraction: 0.7), value: normalizedLevel)
                .animation(.spring(response: 0.15, dampingFraction: 0.7), value: animationPhase)
            }
            .onChange(of: level) { _, _ in
                if isActive {
                    // Vary bar offsets slightly for organic feel
                    animationPhase += 1
                    for i in 0..<barCount {
                        barOffsets[i] = Double.random(in: -0.15...0.15)
                    }
                }
            }
        }
    }

    private func barHeight(for index: Int, in maxHeight: Double) -> Double {
        let minHeight = maxHeight * 0.15
        guard isActive, normalizedLevel > 0.01 else {
            return minHeight
        }

        // Each bar gets a slightly different height based on level + offset
        let baseHeight = normalizedLevel * maxHeight
        let variation = barOffsets[index] * maxHeight * 0.3
        let height = baseHeight + variation

        return max(min(height, maxHeight), minHeight)
    }
}
