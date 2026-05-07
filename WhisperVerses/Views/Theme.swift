import SwiftUI

/// Whisper Verses design system — Industrial / Broadcast Cockpit aesthetic
/// against the Northwoods brand. Every color, font size, and spacing literal
/// in the app should source from this file.
///
/// See `DESIGN.md` at project root for the full design rationale.
enum Theme {

    // MARK: - Brand colors (Pantone-backed)

    enum Brand {
        /// Pantone 2945 — primary blue. Used as full-bleed color block only on dark
        /// surfaces (white reverses out for contrast). Never as text on dark — fails WCAG AA.
        static let blue       = Color(red: 0/255,   green: 76/255,  blue: 151/255)
        /// Pantone 292 — accent on dark. WCAG AA safe for text and fine lines.
        static let lightBlue  = Color(red: 0/255,   green: 156/255, blue: 222/255)
        /// Pantone 295 — dark navy. Used for button shadows / pressed states.
        static let navy       = Color(red: 0/255,   green: 40/255,  blue: 85/255)
        /// Pantone 142 — gold. Capture flash + caution.
        static let gold       = Color(red: 241/255, green: 190/255, blue: 72/255)
        /// Pantone 4212 — green. Healthy / connected / saved.
        static let green      = Color(red: 134/255, green: 173/255, blue: 63/255)
        /// Pantone 2345 — coral. Live tally / recording / offline. Warmer than pure red.
        static let coral      = Color(red: 255/255, green: 109/255, blue: 106/255)
        /// Brand black — warm, never `#000`.
        static let black      = Color(red: 45/255,  green: 41/255,  blue: 38/255)
    }

    // MARK: - Surface tiers (warm-black, not cool grey)

    enum Surface {
        /// Window backdrop — one tier darker than brand black.
        static let window  = Color(red: 27/255, green: 24/255, blue: 21/255)
        /// Panel surface — transcript backdrop, options column.
        static let panel   = Color(red: 34/255, green: 31/255, blue: 27/255)
        /// Card surface — verse tiles, status blocks. Equals Brand.black.
        static let card    = Brand.black
        /// Card surface, hovered.
        static let cardHi  = Color(red: 58/255, green: 54/255, blue: 49/255)
        /// Hairline divider — subtle, not stark.
        static let divider = Color.white.opacity(0.04)
    }

    // MARK: - Status colors (broadcast convention)

    enum Status {
        /// Connected, saved, ready.
        static let ready     = Brand.green
        /// Live / recording / listening — pulses at 1.4s.
        static let live      = Brand.coral
        /// Capturing / pending / caution.
        static let capturing = Brand.gold
        /// Last detected / queued / next.
        static let next      = Brand.lightBlue
        /// Disconnected / offline.
        static let offline   = Brand.coral
    }

    // MARK: - Foreground tiers

    enum Foreground {
        static let primary   = Color(red: 242/255, green: 238/255, blue: 232/255)
        static let secondary = Color(red: 181/255, green: 175/255, blue: 166/255)
        static let tertiary  = Color(red: 110/255, green: 104/255, blue: 98/255)
    }

    // MARK: - Spacing rhythm

    enum Space {
        static let tight:  CGFloat = 4
        static let small:  CGFloat = 8
        static let med:    CGFloat = 12
        static let lg:     CGFloat = 16
        static let xl:     CGFloat = 24
        static let xxl:    CGFloat = 36
    }

    // MARK: - Typography

    enum Typography {
        /// Display headline — replace with bundled Myriad Pro Light when available.
        static func display(_ size: CGFloat = 28) -> Font {
            .system(size: size, weight: .light, design: .default).leading(.tight)
        }

        /// ALL-CAPS section header. Pair with `.tracking(1.8)` and `.textCase(.uppercase)`.
        static func sectionHeader(_ size: CGFloat = 10) -> Font {
            .system(size: size, weight: .black, design: .default)
        }

        /// Big numeric — verse counters, LIVE clock, color-block reversed numbers.
        static func numeric(_ size: CGFloat = 22) -> Font {
            .system(size: size, weight: .black, design: .default).monospacedDigit()
        }

        /// Body sans — default UI text.
        static func body(_ size: CGFloat = 13) -> Font {
            .system(size: size, weight: .regular, design: .default)
        }

        /// Small caption / time stamp / meta.
        static func caption(_ size: CGFloat = 11) -> Font {
            .system(size: size, weight: .black, design: .default).monospacedDigit()
        }

        /// Status pill (LIVE / READY / OFFLINE).
        static func statusPill(_ size: CGFloat = 9) -> Font {
            .system(size: size, weight: .black, design: .default)
        }

        /// Verse text body — Minion Pro Italic when bundled, italic serif fallback now.
        static func verseBody(_ size: CGFloat = 14) -> Font {
            .system(size: size, weight: .regular, design: .serif).italic()
        }
    }

    // MARK: - Motion

    enum Motion {
        /// Broadcast-grade snap — instant transition, no spring.
        static let snap     = Animation.easeOut(duration: 0.12)
        /// Capture flash — gold → blue settle.
        static let flash    = Animation.easeOut(duration: 0.6)
        /// Tally breath — 1.4s symmetric pulse.
        static let breath   = Animation.easeInOut(duration: 0.7).repeatForever(autoreverses: true)
    }
}

// MARK: - Convenience modifiers

extension View {
    /// Apply the standard ALL-CAPS section-header treatment with a brand-blue rule on the leading edge.
    func sectionHeaderStyle() -> some View {
        self
            .font(Theme.Typography.sectionHeader())
            .tracking(1.8)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Foreground.secondary)
    }
}
