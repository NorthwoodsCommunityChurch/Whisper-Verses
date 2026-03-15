import SwiftUI

struct ConnectionStatusView: View {
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isConnected ? .green : .red)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(isConnected ? "Connected" : "Disconnected")
                .font(.caption)
                .foregroundStyle(isConnected ? .primary : .secondary)
        }
    }
}
