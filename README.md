# Whisper Verses

Real-time Bible verse detection and ProPresenter slide capture for live services.

<!-- TODO: Add screenshot after first production use -->
<!-- ![Whisper Verses](docs/images/whisper-verses-main.png) -->

## Features

- **Live audio transcription** via WhisperKit (large-v3_turbo model) with Voice Activity Detection
- **Bible verse detection** using regex, spoken-form normalization, and fuzzy book name matching
- **ProPresenter 7 integration** — indexes Bible presentations and captures slide images via REST API
- **Transparent PNG output** at full 1080p resolution, saved to a folder Pro7 watches
- **Live slide preview** showing the current Pro7 output with computed verse reference labels
- **Sequential file naming** (`001_John_3_16.png`) for chronological order in Pro7 folder playlists
- **Automatic Pro7 connection** and library indexing on app launch
- **Persistent settings** for audio device, Pro7 host/port, library name, and output folder

## Requirements

- macOS 14.0+ (Sonoma)
- Apple Silicon Mac (M1 or later)
- [AudioLoop](https://github.com/Levin-Li/AudioLoop) or similar virtual audio driver
- ProPresenter 7 with Network API enabled
- Bible presentations pre-generated in Pro7 (one per book, transparent background template)

## Installation

1. Download the latest `.zip` from [Releases](../../releases)
2. Extract the zip
3. Right-click `Whisper Verses.app` and select **Open** (required for ad-hoc signed apps)
4. On first launch, the WhisperKit model (~1.5 GB) will download automatically

## Usage / Quick Start

1. **Set up ProPresenter**: Generate Bible verse slides for all 66 books using a transparent background template. Place them in a Pro7 library (default: "Default").
2. **Create a Folder Playlist** in Pro7 pointing to the output folder (default: `~/Documents/ProPresenter/WhisperVerses/`)
3. **Launch Whisper Verses** and configure:
   - Select your audio input device (e.g., AudioLoop for system audio capture)
   - Enter your Pro7 host IP and port
   - Click **Connect**, then **Index** to build the verse-to-slide mapping
4. **Click Start Listening** — the app transcribes audio, detects verse references, and saves slide PNGs to the output folder
5. In Pro7, the folder playlist updates automatically — the operator triggers verses as needed

## Configuration

| Setting | Description | Default |
|---------|-------------|---------|
| Audio Device | Input device for audio capture | System default |
| Pro7 Host | ProPresenter machine IP address | `127.0.0.1` |
| Pro7 Port | ProPresenter API port | `1025` |
| ProPresenter Library | Library name containing Bible presentations | `Default` |
| Output Folder | Where captured PNGs are saved | `~/Documents/ProPresenter/WhisperVerses/` |

## Building from Source

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone https://github.com/NorthwoodsCommunityChurch/whisper-verses.git
cd whisper-verses
xcodegen generate
open WhisperVerses.xcodeproj
```

Build and run from Xcode, or from the command line:

```bash
xcodebuild -project WhisperVerses.xcodeproj -scheme WhisperVerses -configuration Release build
```

Ad-hoc code sign for distribution:

```bash
codesign --force --deep --sign - build/Release/WhisperVerses.app
```

## Project Structure

```
WhisperVerses/
├── WhisperVerses.xcodeproj
├── project.yml                          # XcodeGen project definition
├── Icons/                               # Source icon assets (SVG)
├── WhisperVerses/
│   ├── App/
│   │   ├── WhisperVersesApp.swift       # @main entry point
│   │   └── AppState.swift               # Global observable state
│   ├── Models/
│   │   ├── BibleReference.swift         # Parsed verse reference
│   │   ├── BibleBook.swift              # Book metadata + aliases
│   │   ├── DetectedVerse.swift          # Detection result with timestamp
│   │   ├── TranscriptSegment.swift      # Timestamped transcript chunk
│   │   └── ProPresentationMap.swift     # Verse ↔ slide index mapping
│   ├── Services/
│   │   ├── Audio/
│   │   │   ├── AudioDeviceManager.swift # CoreAudio device enumeration
│   │   │   └── TranscriptionService.swift # WhisperKit streaming
│   │   ├── Detection/
│   │   │   ├── VerseDetector.swift      # Main detection pipeline
│   │   │   ├── SpokenFormNormalizer.swift
│   │   │   ├── BookNameMatcher.swift
│   │   │   └── NumberWordConverter.swift
│   │   └── ProPresenter/
│   │       ├── ProPresenterAPI.swift    # REST API client
│   │       ├── PresentationIndexer.swift
│   │       └── SlideImageCapture.swift
│   ├── Views/
│   │   ├── MainView.swift               # Three-panel HSplitView
│   │   ├── TranscriptPanelView.swift    # Live transcript (left)
│   │   ├── OptionsPanelView.swift       # Controls (top-right)
│   │   ├── CapturePreviewPanelView.swift # Slide preview (bottom-right)
│   │   ├── ConnectionStatusView.swift
│   │   └── AudioLevelView.swift
│   ├── Utilities/
│   │   └── ImageConverter.swift         # TIFF/JPEG → PNG conversion
│   └── Resources/
│       ├── BibleBooks.json              # 66 books with verse counts
│       └── Assets.xcassets
└── WhisperVersesTests/
```

## License

See [LICENSE](LICENSE) for details.

## Credits

See [CREDITS.md](CREDITS.md) for third-party attributions.
