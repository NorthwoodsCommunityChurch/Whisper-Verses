import SwiftUI

/// Top chrome bar — broadcast cockpit treatment.
/// Replaces the standard window toolbar with: wordmark + Northwoods marker,
/// Pro7 connection status (clickable to open settings), LIVE clock when
/// listening, and a row of small ALL-CAPS action buttons.
struct ChromeBar: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    let onPickVerse: () -> Void
    let onImport: () -> Void

    @State private var elapsed: TimeInterval = 0
    @State private var clockTimer: Timer?
    @State private var listenStart: Date?
    @State private var pulse = false

    var body: some View {
        HStack(spacing: Theme.Space.med) {
            wordmark
            connectionStatus
            if appState.isListening {
                liveClock
                    .transition(.opacity)
            }
            Spacer(minLength: Theme.Space.med)
            actions
        }
        .padding(.leading, 100)  // traffic lights end at x=69; this gives a generous breathing gap
        .padding(.trailing, Theme.Space.med)
        .frame(height: 44)
        .background(Theme.Surface.panel)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Surface.divider)
                .frame(height: 1)
        }
        .onChange(of: appState.isListening) { _, listening in
            if listening {
                listenStart = Date()
                startClock()
            } else {
                listenStart = nil
                stopClock()
                elapsed = 0
            }
        }
        .onAppear { if appState.isListening { startClock() } }
    }

    // MARK: - Pieces

    private var wordmark: some View {
        HStack(spacing: 8) {
            NorthwoodsMarker()
                .frame(width: 14, height: 18)
            Text("WHISPER VERSES")
                .font(Theme.Typography.statusPill(11))
                .tracking(2.0)
                .foregroundStyle(Theme.Foreground.primary)
        }
    }

    private var connectionStatus: some View {
        Button {
            openSettings()
        } label: {
            HStack(spacing: Theme.Space.small) {
                Circle()
                    .fill(appState.isProPresenterConnected ? Theme.Status.ready : Theme.Status.offline)
                    .frame(width: 8, height: 8)
                    .shadow(
                        color: (appState.isProPresenterConnected ? Theme.Status.ready : Theme.Status.offline).opacity(0.6),
                        radius: 4
                    )
                statusLabel
            }
            .padding(.horizontal, Theme.Space.small)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(appState.isProPresenterConnected ? "ProPresenter connected — click to open settings" : "ProPresenter unreachable — click to open settings")
    }

    @ViewBuilder
    private var statusLabel: some View {
        if appState.isProPresenterConnected {
            if let indexer = appState.presentationIndexer, indexer.indexedBookCount > 0 {
                Text("PRO7 \u{00B7} \(indexer.indexedBookCount)/66")
                    .font(Theme.Typography.statusPill(10))
                    .tracking(1.2)
                    .foregroundStyle(Theme.Foreground.secondary)
            } else {
                Text("PRO7")
                    .font(Theme.Typography.statusPill(10))
                    .tracking(1.2)
                    .foregroundStyle(Theme.Foreground.secondary)
            }
        } else {
            Text("PRO7 OFFLINE")
                .font(Theme.Typography.statusPill(10))
                .tracking(1.2)
                .foregroundStyle(Theme.Status.offline)
        }
    }

    private var liveClock: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.Brand.green)
                .frame(width: 8, height: 8)
                .shadow(color: Theme.Brand.green.opacity(pulse ? 0.9 : 0.4), radius: pulse ? 8 : 3)
                .opacity(pulse ? 1.0 : 0.55)
                .onAppear {
                    withAnimation(Theme.Motion.breath) { pulse.toggle() }
                }
            Text("LIVE \u{00B7} \(formatElapsed(elapsed))")
                .font(Theme.Typography.statusPill(10))
                .tracking(1.5)
                .foregroundStyle(Theme.Brand.green)
        }
        .padding(.horizontal, Theme.Space.small)
    }

    private var actions: some View {
        HStack(spacing: Theme.Space.small) {
            chromeButton("Pick Verse", action: onPickVerse, disabled: false)
            chromeButton("Import", action: onImport,
                          disabled: !appState.isProPresenterConnected || appState.presentationIndexer?.map.isEmpty != false)
            chromeButton(appState.isListening ? "Stop" : "Listen",
                         action: { Task { await appState.toggleListening() } },
                         disabled: false,
                         emphasis: appState.isListening ? .live : .accent)
            chromeButton("Clear", action: { appState.clearOutputFolders() }, disabled: false)
            chromeButton("Settings", action: { openSettings() }, disabled: false)
        }
    }

    private func chromeButton(_ title: String, action: @escaping () -> Void, disabled: Bool, emphasis: ChromeButtonEmphasis = .standard) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.statusPill(10))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(emphasis.foreground(disabled: disabled))
                .padding(.horizontal, Theme.Space.small)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - Clock

    private func startClock() {
        clockTimer?.invalidate()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            if let start = listenStart {
                elapsed = Date().timeIntervalSince(start)
            }
        }
        if let timer = clockTimer { RunLoop.main.add(timer, forMode: .common) }
    }
    private func stopClock() {
        clockTimer?.invalidate()
        clockTimer = nil
    }

    private func formatElapsed(_ t: TimeInterval) -> String {
        let total = Int(t)
        let h = total / 3600
        let m = (total / 60) % 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

private enum ChromeButtonEmphasis {
    case standard, accent, live

    func foreground(disabled: Bool) -> Color {
        if disabled { return Theme.Foreground.tertiary }
        switch self {
        case .standard: return Theme.Foreground.secondary
        case .accent:   return Theme.Brand.lightBlue
        case .live:     return Theme.Brand.green
        }
    }
}

/// Northwoods location-marker symbol — drop pin with center cross/plus.
/// The center is transparent so the surface behind it shows through.
struct NorthwoodsMarker: View {
    var color: Color = Theme.Brand.lightBlue
    var bg: Color = Theme.Surface.panel

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Drop pin shape
                Path { p in
                    p.move(to: CGPoint(x: w * 0.5, y: 0))
                    p.addCurve(
                        to: CGPoint(x: 0, y: h * 0.39),
                        control1: CGPoint(x: w * 0.22, y: 0),
                        control2: CGPoint(x: 0, y: h * 0.17)
                    )
                    p.addCurve(
                        to: CGPoint(x: w * 0.5, y: h),
                        control1: CGPoint(x: 0, y: h * 0.61),
                        control2: CGPoint(x: w * 0.5, y: h)
                    )
                    p.addCurve(
                        to: CGPoint(x: w, y: h * 0.39),
                        control1: CGPoint(x: w * 0.5, y: h),
                        control2: CGPoint(x: w, y: h * 0.61)
                    )
                    p.addCurve(
                        to: CGPoint(x: w * 0.5, y: 0),
                        control1: CGPoint(x: w, y: h * 0.17),
                        control2: CGPoint(x: w * 0.78, y: 0)
                    )
                    p.closeSubpath()
                }
                .fill(color)

                // Hollow center showing the background through
                Circle()
                    .fill(bg)
                    .frame(width: w * 0.55, height: w * 0.55)
                    .position(x: w * 0.5, y: h * 0.39)

                // Plus/cross inside the hollow
                Path { p in
                    let cx = w * 0.5
                    let cy = h * 0.39
                    let arm = w * 0.18
                    p.move(to: CGPoint(x: cx, y: cy - arm))
                    p.addLine(to: CGPoint(x: cx, y: cy + arm))
                    p.move(to: CGPoint(x: cx - arm, y: cy))
                    p.addLine(to: CGPoint(x: cx + arm, y: cy))
                }
                .stroke(color, style: StrokeStyle(lineWidth: max(1, w * 0.07), lineCap: .square))
            }
        }
    }
}
