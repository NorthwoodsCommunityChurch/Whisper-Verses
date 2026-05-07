# Whisper Verses — Design

The brief: Sunday-morning operator tool that listens to a live sermon, identifies Bible verse references in real time, and pre-captures their slides from ProPresenter for the operator to fire. This is broadcast workflow, not a settings window.

---

## 1. Aesthetic direction

> **Industrial / Broadcast Cockpit** — Whisper Verses runs in a control room next to Pro7, ATEM, vMix, and Logic Pro. Its visual language has to match: warm-black panels, status lights, dense modular tiles, sharp brand-blue accents, monospaced numerics. Information density is a feature, because the operator is glancing — never reading — during a live service.

---

## 2. The unforgettable thing

> **A live "catch feed" of verse cards stacking up in real time, each one a full-bleed brand-blue numbered tile with the captured slide thumbnail underneath.** When the camera pans to your station and the projector shows your screen, the room sees a broadcast preview wall, not a transcription log.

---

## 3. Three reference apps as the bar

| App | Specific thing to learn |
|---|---|
| **OBS Studio** | Scene preview tiles as the central visual element. The thing on stage is a *grid of live thumbnails*, not text. Apply: detected verses become tiles with their slide image, not list rows. |
| **ATEM Software Control** | Tally lights and big physical-feeling primary actions. Apply: the listening indicator is a real tally (pulsing red bar at the panel edge); "Start Listening" is a chunky primary button with weight, not a text link. |
| **ProPresenter Operator** | Active vs. next-up slide states, label-led grid. Apply: the verse queue shows what was just captured (active, brand-blue solid) and what's pending detection (next, brand-blue outline) — the same operator language Pro7 already speaks. |

---

## 4. Visual system

### Type scale

| Role | Font + weight | Size | Notes |
|---|---|---|---|
| App wordmark | Myriad Pro Black, ALL-CAPS | 13pt | tracking +2.0; placed top-left in chrome bar |
| Section header | Myriad Pro Black, ALL-CAPS | 10pt | tracking +1.8; with brand-blue 2px rule beneath (Apple-News-style) |
| Display number (verse #, count) | Myriad Pro Black, monospaced digits | 32–48pt | reversed out of full-bleed brand-blue color block |
| Body / transcript | Myriad Pro Regular | 13pt | line-spacing 1.4× |
| Verse text (when shown) | Minion Pro Italic | 14pt | with reference label in Myriad Pro Black above |
| Time stamps & counters | Myriad Pro Black, `.monospacedDigit()` | 11pt | tertiary foreground |
| Status pill (LIVE / READY / OFFLINE) | Myriad Pro Black, ALL-CAPS | 9pt | tracking +1.5 |

### Color usage rules

- **Window background:** warm-black `#1B1815` — derived from brand black `#2D2926`, one tier darker. **Never** cool grey.
- **Panel surface (transcript / right column):** `#221F1B` — one tier up from window
- **Card surface (verse tiles, status block):** `#2D2926` — brand black exactly
- **Primary accent (interactive, active states):** light blue `#009CDE` — primary blue `#004C97` reserved for full-bleed color blocks where contrast is set by reversal, not by foreground
- **Color block device:** full-bleed brand-blue `#004C97` strip on every verse card with the verse number reversed out in white. This is the Northwoods signature device.
- **Status colors:**
  - 🟢 green `#86AD3F` — Pro7 connected, model loaded, ready
  - 🔴 coral `#FF6D6A` — listening (live tally) — warmer than pure red, pulses at 1.4s
  - 🟡 gold `#F1BE48` — capturing slide (transient flash on each catch)
  - 🔵 light blue `#009CDE` — last-detected verse, queued, pending
- **Forbidden:** primary blue `#004C97` as text on dark (fails WCAG AA). Pure `#000` anywhere. Cool grey panels (`#2A2A2A`-ish).

### Spacing rhythm

`tight 4 / small 8 / medium 12 / large 16 / xlarge 24 / xxlarge 36`. No raw literals in views.

### Motion personality

> **Snap.** Broadcast convention: state transitions are instant, not eased. Capture flash 0.12s. Tally pulse 1.4s breathing while listening. No bounces, no spring. The only "soft" motion is the tally LED breathing — everything else is crisp.

### Iconography stance

- **Hero illustrations** — custom for the two empty states (idle / disconnected). Generated via `nano-banana` in next iteration; for the demo, use bold geometric SVG built inline (broadcast-grade simple shapes — concentric tally rings + a Pro7-style slide stack).
- **Northwoods location marker** — appears in the chrome top-left next to "WHISPER VERSES" wordmark. Small, in light blue.
- **Pointer symbol** (Northwoods brand device) — used as the "next-up" indicator on the most-recently-detected (not-yet-captured) verse row. Direction: pointing right toward the slide thumbnail.
- **Utility icons** — SF Symbols are fine for toolbar (gear, doc, etc.) but **never** for hero / feature illustrations.

---

## 5. Surfaces — sketches

### Idle / not listening (first impression)
```
┌──────────────────────────────────────────────────────────────┐
│ ◆ WHISPER VERSES   ⬤Pro7 connected · 66/66       [⚙]         │
├──────────────────────────────────────────────────────────────┤
│                                       │  AUDIO INPUT         │
│                                       │  [ Audio Loop  ▾ ]   │
│         ┌───────────────────┐         │  ▁▁▁▂▂▃▂▁▁ -36dB     │
│         │  ◯  ◯  ◯           │         │                       │
│         │     ●              │         │  GAIN  1.0×          │
│         │  (concentric       │         │  ━━━━━●━━━━━━━━      │
│         │   broadcast        │         │                       │
│         │   tally rings)     │         │ ────────────────────  │
│         └───────────────────┘         │  CATCH FEED           │
│                                       │  No verses yet —     │
│         READY TO LISTEN               │  press LISTEN to     │
│         Press ⌘L to begin             │  begin live capture. │
│                                       │                       │
│   ┌───────────────────────┐           │                       │
│   │      ▶  LISTEN        │           │                       │
│   └───────────────────────┘           │                       │
└──────────────────────────────────────────────────────────────┘
```

- Hero illustration: concentric broadcast tally rings (5 circles, only the center is a brand-light-blue dot) — communicates "broadcast", "ready", "centered"
- Primary action: a chunky `LISTEN` button with the brand-blue color block treatment, not a system text button
- Right column shows the panel skeleton already populated — operator sees where things will go before they happen

### Live / actively capturing
```
┌──────────────────────────────────────────────────────────────┐
│ ◆ WHISPER VERSES   ⬤Pro7 · 66/66    🔴 LIVE 04:12   [⚙]      │
├──────────────────────────────────────────────────────────────┤
│ ▍ TRANSCRIPT                          │  AUDIO  ━▃▅▇▆▄▂      │
│                                       │  ──────────────────   │
│  10:14:22                             │                       │
│  ...so when Paul writes in            │  CATCH FEED   3       │
│  »2 Corinthians 5:17«, he's saying  ─┼→ ┌───┐                │
│  the believer is now a new...         │  │ 03│  2 Cor 5:17   │
│                                       │  │   │  [thumbnail]  │
│  10:13:55                             │  └───┘  10:14:22 ✓   │
│  ...turn with me to                   │                       │
│  »Romans 8:28«, this is one of...    ─┼→ ┌───┐                │
│                                       │  │ 02│  Romans 8:28  │
│  10:11:09                             │  │   │  [thumbnail]  │
│  ...the gospel as it stands in        │  └───┘  10:13:55 ✓   │
│  »John 3:16«...                      ─┼→ ┌───┐                │
│                                       │  │ 01│  John 3:16    │
│                                       │  │   │  [thumbnail]  │
│                                       │  └───┘  10:11:09 ✓   │
│  ┌──────╢Listening...                 │                       │
│  red                                  │                       │
│  edge                                  │                       │
└──────────────────────────────────────────────────────────────┘
```

- Verse references inside the transcript are wrapped in `»« ` brackets, set in light-blue, with a thin pointer arrow connecting them to the corresponding tile on the right
- Each verse tile is a 60pt-tall row: a full-bleed brand-blue square with reversed-out verse number, the reference + thumbnail to its right, and a checkmark + capture-time stamp
- The red `LIVE 04:12` with mono numerals in the chrome is the broadcast clock — borrowed straight from ATEM
- Left edge of the transcript pane shows a 3pt coral `#FF6D6A` rule that pulses at 1.4s while listening

### Pro7 disconnected (status-only, never a takeover)

**Decision:** disconnected does NOT take over the app. The operator may still want to listen, build a transcript, run document import, or work offline. Pro7's state is communicated by the chrome bar status indicator alone:

```
│ ◆ WHISPER VERSES   ⬤ Pro7 OFFLINE     ⚙ │   ← chrome bar
```

- Connection LED switches from green to coral
- Label text reads `Pro7 OFFLINE` in coral, ALL-CAPS, slightly bolder than the connected state
- Clicking the indicator opens the Pro7 connection settings
- The catch feed continues to show whatever was already captured; new verses queue with a `pending` state and re-attempt when Pro7 comes back

This matches broadcast convention — switcher source rows show OFFLINE on a single source, they don't hide the rest of the panel.

---

## 6. Custom components inventory

| Stock control | Replacement | Notes |
|---|---|---|
| `ContentUnavailableView` (idle state) | `IdleHero` — concentric tally rings + READY label + chunky LISTEN button | Forbidden by skill for first-impression |
| `ContentUnavailableView` (no captures) | `CatchFeedEmpty` — three ghost tile outlines stacked, "no verses yet" label | Lives in the right column |
| Default `Picker` for audio device | `DeviceMenu` — labelled left, animated waveform inline right, level dB readout | Same component; just styled |
| Default `Slider` for input gain | `GainSlider` — slim track, brand-blue thumb, monospaced "1.0×" readout | |
| Toolbar text buttons | `ChromeButton` — small ALL-CAPS, brand-blue underline on hover | Chrome bar reads as broadcast labels |
| `Button("Start Listening")` (toolbar) | **Removed from toolbar.** Promoted to a primary in-canvas button (`ListenButton`) — chunky, brand-blue color block, with shortcut hint. | This is the demo moment — make it unmissable |
| The whole "Pro7 Capture" right panel header | `CatchFeedHeader` — section label + counter pill + small "clear all" affordance | |
| Verse list row | `VerseTile` — 60pt tall, full-bleed brand-blue square with verse number reversed out, reference + thumbnail to its right | The signature element |
| Listening edge indicator (current red rectangle) | `TallyBar` — 3pt coral rule that *breathes* (pulse 1.4s) while live | Real broadcast tally idiom |

---

## 7. Animation / motion

| Surface | Trigger | Animation |
|---|---|---|
| Tally bar (left edge of transcript) | listening on/off | breathing pulse 1.4s while live; instant fade in/out on toggle |
| Connection LED | always | 1.4s breath while connected; solid coral while offline |
| Verse tile | first appearance | gold flash on the color-block square (0.12s), then settles to brand-blue solid |
| Listening / Stop button | tap | snap, no easing — broadcast convention |
| LIVE clock | always | mono numerals tick once per second |

---

## 8. Implementation gates

- [ ] Brand fonts (Myriad Pro / Minion Pro) bundled and registered at launch
- [ ] All hex literals removed from view code; centralized in `Theme.Brand` / `Theme.Surface` / `Theme.Status`
- [ ] All raw spacing literals replaced with `Theme.Space.*`
- [x] No `ContentUnavailableView` in any first-impression surface (replaced by `IdleHero` + `CatchFeedEmpty`)
- [ ] At least one custom illustration in the running app (concentric tally rings; the Pro7-disconnected slide-stack)
- [ ] Northwoods location marker appears in chrome top-left
- [ ] Color block device used on every verse tile (full-bleed brand-blue with reversed verse number)
- [x] Three reference apps documented (OBS, ATEM, Pro7 Operator)
- [x] Aesthetic committed (Industrial / Broadcast Cockpit) and unforgettable thing named (live catch-feed of brand-blue numbered tiles)

---

## 9. Demo-readiness scope (24-hour cut)

What ships before the conference:

1. **Theme module** — colors, type, spacing constants. ~30min
2. **`VerseTile` component** — replaces existing capture row. The signature element. ~45min
3. **`IdleHero` + `CatchFeedEmpty`** — replaces both `ContentUnavailableView`s. ~45min
4. **Chrome bar** — wordmark + connection LED + LIVE clock when listening. ~30min
5. **Tally bar** — replaces the existing red rectangle on the transcript edge. ~15min
6. **`ListenButton`** — promoted from toolbar, placed in idle hero. ~30min

Total: ~3 hours of focused work. Stops short of:
- Bundling brand fonts (uses system equivalents — close enough for a demo screenshot)
- Custom-generated nano-banana illustrations (uses inline SVG geometric placeholders)
- Reworking Settings or Onboarding
- Any audio pipeline / chroma key changes (those are done and stable)

After the demo, finish: brand font bundling, generated illustrations, settings redesign.
