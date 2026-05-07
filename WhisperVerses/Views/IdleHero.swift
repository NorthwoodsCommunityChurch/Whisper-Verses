import SwiftUI

/// First-impression hero for the transcript pane when the app is idle and
/// not yet listening. Concentric "tally rings" (broadcast-style) plus the
/// chunky LISTEN button — the demo moment.
struct IdleHero: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: Theme.Space.xl) {
            TallyRings()
                .frame(width: 140, height: 140)
            VStack(spacing: 8) {
                Text("READY TO LISTEN")
                    .font(Theme.Typography.statusPill(11))
                    .tracking(2.5)
                    .foregroundStyle(Theme.Foreground.secondary)
                Text("Whisper Verses will catch every Bible reference the speaker reads or quotes, and pre-load its slide into ProPresenter.")
                    .font(Theme.Typography.body(13))
                    .foregroundStyle(Theme.Foreground.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            ListenButton(action: onStart)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Space.xxl)
    }
}

/// Concentric broadcast tally rings — five circles with a glowing brand-light-blue core.
struct TallyRings: View {
    @State private var coreOn = false

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().strokeBorder(Color.white.opacity(0.06), lineWidth: 1.5)
                Circle().strokeBorder(Color.white.opacity(0.07), lineWidth: 1.5)
                    .padding(s * 0.13)
                Circle().strokeBorder(Color.white.opacity(0.09), lineWidth: 1.5)
                    .padding(s * 0.27)
                Circle().strokeBorder(Theme.Brand.lightBlue.opacity(0.35), lineWidth: 1.5)
                    .padding(s * 0.40)
                Circle()
                    .fill(Theme.Brand.lightBlue)
                    .padding(s * 0.46)
                    .shadow(color: Theme.Brand.lightBlue.opacity(coreOn ? 0.85 : 0.45), radius: coreOn ? 20 : 8)
                    .opacity(coreOn ? 1.0 : 0.75)
            }
            .frame(width: s, height: s)
            .onAppear {
                withAnimation(Theme.Motion.breath) { coreOn.toggle() }
            }
        }
    }
}

/// The signature primary-action button. Brand-blue color block with a hard navy
/// drop shadow that gives it physical weight, like an ATEM panel button.
struct ListenButton: View {
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.med) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .heavy))
                Text("LISTEN")
                    .font(.system(size: 14, weight: .heavy))
                    .tracking(1.5)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 44)
            .padding(.vertical, 18)
            .background(Theme.Brand.blue)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.Brand.navy)
                    .frame(height: 6)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .offset(y: 6)
                    .opacity(pressed ? 0 : 1)
            }
            .offset(y: pressed ? 3 : 0)
            .shadow(color: Theme.Brand.blue.opacity(0.3), radius: 14, y: pressed ? 6 : 14)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("l", modifiers: .command)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, perform: {}) { isPressing in
            withAnimation(.easeOut(duration: 0.08)) { pressed = isPressing }
        }
    }
}

/// Empty state for the catch feed (right column) — three ghost tile outlines stacked,
/// with the explanation underneath. Replaces `ContentUnavailableView`.
struct CatchFeedEmpty: View {
    var body: some View {
        VStack(spacing: Theme.Space.small) {
            ghostTile(opacity: 1.0)
            ghostTile(opacity: 0.6)
            ghostTile(opacity: 0.3)
            Text("Detected verses will appear here as the sermon progresses.")
                .font(Theme.Typography.body(11))
                .foregroundStyle(Theme.Foreground.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
                .padding(.top, Theme.Space.small)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.top, Theme.Space.lg)
    }

    private func ghostTile(opacity: Double) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Theme.Brand.blue.opacity(0.07))
                .frame(width: 60)
            Rectangle()
                .fill(Color.clear)
            Spacer()
        }
        .frame(height: 60)
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.white.opacity(0.05), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .opacity(opacity)
    }
}
