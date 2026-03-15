import SwiftUI

struct CaptureRow: View {
    let capture: CapturedVerse

    var body: some View {
        HStack {
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(capture.reference)
                .font(.caption)
            Spacer()
            Text(capture.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
