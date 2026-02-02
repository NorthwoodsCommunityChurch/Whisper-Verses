import SwiftUI

struct AudioLevelView: View {
    let level: Float

    /// Normalize audio RMS to 0-1 range for display
    private var normalizedLevel: CGFloat {
        // RMS values are typically 0-0.5 for normal speech
        let clamped = min(max(CGFloat(level) * 3, 0), 1)
        return clamped
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.2))

                RoundedRectangle(cornerRadius: 3)
                    .fill(levelColor)
                    .frame(width: geometry.size.width * normalizedLevel)
                    .animation(.easeOut(duration: 0.1), value: normalizedLevel)
            }
        }
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
}
