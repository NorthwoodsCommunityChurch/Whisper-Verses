import SwiftUI

/// The signature element of Whisper Verses. A horizontal tile with a
/// full-bleed brand-blue color block on the leading edge (verse number
/// reversed out in white), then the reference + slide thumbnail.
///
/// Three variants:
///   - `.captured` — verse has been saved; thumbnail visible; green checkmark
///   - `.capturing` — capture in progress; gold flash on the color block
///   - `.next` — pending detection (not yet captured); brand-blue outline only
struct VerseTile: View {
    enum Variant {
        case captured(thumbnail: NSImage?, savedAt: Date)
        case capturing
        case next
        case failed(String)
    }

    let number: Int
    let reference: String
    let variant: Variant

    @State private var hasFlashed = false

    var body: some View {
        HStack(spacing: 0) {
            colorBlock
            HStack(spacing: Theme.Space.med) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(reference)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.Foreground.primary)
                        .lineLimit(1)
                    metaLine
                }
                Spacer(minLength: Theme.Space.small)
                thumbnailView
            }
            .padding(.horizontal, Theme.Space.med)
            .padding(.vertical, Theme.Space.small)
        }
        .frame(height: 60)
        .background(Theme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    // MARK: - Pieces

    private var colorBlock: some View {
        ZStack {
            colorBlockFill
            Text(String(format: "%02d", number))
                .font(Theme.Typography.numeric(22))
                .foregroundStyle(colorBlockText)
                .tracking(-0.5)
        }
        .frame(width: 60)
    }

    @ViewBuilder
    private var colorBlockFill: some View {
        switch variant {
        case .next:
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(Theme.Brand.lightBlue, lineWidth: 2)
                .background(Theme.Surface.card)
        case .capturing:
            Theme.Brand.gold
        case .failed:
            Theme.Status.offline.opacity(0.85)
        case .captured:
            // Capture-flash animation: gold → blue settle on first appearance.
            ZStack {
                Theme.Brand.blue
                if !hasFlashed {
                    Theme.Brand.gold
                        .opacity(1)
                        .onAppear {
                            withAnimation(Theme.Motion.flash) {
                                hasFlashed = true
                            }
                        }
                        .opacity(hasFlashed ? 0 : 1)
                        .animation(Theme.Motion.flash, value: hasFlashed)
                }
            }
        }
    }

    private var colorBlockText: Color {
        switch variant {
        case .next:      return Theme.Brand.lightBlue
        case .capturing: return Theme.Brand.black
        case .failed:    return .white
        case .captured:  return .white
        }
    }

    @ViewBuilder
    private var metaLine: some View {
        switch variant {
        case .captured(_, let savedAt):
            HStack(spacing: 4) {
                Text("✓")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Theme.Brand.green)
                Text(timeFormatter.string(from: savedAt))
                    .font(Theme.Typography.caption(10))
                    .foregroundStyle(Theme.Foreground.tertiary)
                Text("· saved")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Foreground.tertiary)
            }
        case .capturing:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.4).frame(width: 10, height: 10)
                Text("capturing…")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Brand.gold)
            }
        case .next:
            HStack(spacing: 4) {
                // Pointer symbol — Northwoods brand device, "next-up" indicator
                Text("▸")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Theme.Brand.lightBlue)
                Text("queued")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Foreground.tertiary)
            }
        case .failed(let msg):
            Text(msg)
                .font(.system(size: 10))
                .foregroundStyle(Theme.Status.offline)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        switch variant {
        case .captured(let image, _):
            ZStack {
                CheckerboardView()
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(2)
                }
            }
            .frame(width: 80, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
            }

        case .capturing, .next, .failed:
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.Surface.window)
                .frame(width: 80, height: 44)
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Theme.Surface.divider, lineWidth: 1)
                }
        }
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }
}
