import SwiftUI

struct TranscriptRow: View {
    let segment: TranscriptSegment

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(segment.formattedTime)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)

            if segment.detectedReferences.isEmpty {
                Text(segment.text)
                    .font(.body)
                    .textSelection(.enabled)
            } else {
                // Highlight text containing verse references
                Text(segment.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(2)
                    .background(Color.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
            }
        }
        .padding(.horizontal)
    }
}
