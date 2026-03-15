# Whisper Verses

macOS app that transcribes live audio using WhisperKit, detects Bible verse references in the transcript, and captures slide images from ProPresenter 7.

## Architecture

- **WhisperKit** for speech-to-text transcription (large-v3_turbo model)
- **ProPresenter 7 REST API** for slide image capture
- **SwiftUI** with `@Observable` pattern for state management
- **XcodeGen** for project generation (`project.yml`)

## ProPresenter 7 Integration

### API Endpoints Used
- `GET /version` - Connection check
- `GET /v1/libraries` - List all libraries
- `GET /v1/library/{id}` - List presentations in a library
- `GET /v1/presentation/{uuid}` - Get presentation details including slide labels
- `GET /v1/presentation/{uuid}/thumbnail/{index}?quality=N` - Get slide image

### Lazy Loading for Bible Libraries
The Bible library has ~30,000 slides across 66 books. Loading all slide labels upfront is slow.

**Solution: Two-phase indexing**
1. **Initial index (fast)** - Store book name → presentation UUID mapping only
2. **On-demand loading** - Fetch a book's slide labels when first verse from that book is detected

This makes indexing nearly instant while still supporting accurate verse-to-slide lookups.

### Verse-to-Slide Mapping
Different Bible translations have different verse numbering. The NIV omits verses that KJV includes (e.g., Matthew 17:21, 18:11, 23:14).

**Solution: Label-based lookup**
- Fetch actual slide labels from Pro7 (e.g., "Matthew 28:19")
- Store label → slide index mapping
- Look up verses by constructing the label string, not by calculating indices

This makes lookups translation-independent and always accurate.

## Verse Detection

### Duplicate Prevention
When processing streaming transcription segments, the same verse can be re-detected multiple times:
- Same verse mentioned multiple times in speech
- Cross-segment detection re-finding verses from combined text windows

**Solution: Track all previously detected verse keys**
```swift
let previouslyDetectedKeys = Set(detectedVerses.map { $0.reference.displayString })
let newDetected = detected.filter { !previouslyDetectedKeys.contains($0.reference.displayString) }
```

Check against ALL previously detected verses, not just current segment's detections.

### Cross-Segment Detection
Verse references can span segment boundaries (e.g., "2 Peter 1" in one segment, "verses 20 to 21" in next).

Combine recent segments for detection, but only add truly NEW verses that weren't found in any previous segment.

## Build & Run

```bash
# Generate Xcode project
xcodegen generate

# Build release
xcodebuild -scheme WhisperVerses -configuration Release -derivedDataPath build

# Run
open build/Build/Products/Release/WhisperVerses.app
```

## Deployment

### Production Machine — RUBI (10.10.11.80)
- **User:** `mediaadmin`
- **SSH key:** `~/.ssh/id_ed25519`
- **App location:** `/Applications/Canopy/WhisperVerses.app`
- **Audio input:** Dante Virtual Soundcard (4 channels, 48kHz) — requires WhisperKit fork with multi-channel fallback
- **ProPresenter 7:** Running on separate machine at 10.10.11.77:52554
- **Deploy workflow:**
  ```bash
  # Kill running app and remove old bundle (rsync fails due to OneDrive xattrs)
  ssh -i ~/.ssh/id_ed25519 mediaadmin@10.10.11.80 "pkill -x WhisperVerses; sleep 1; rm -rf '/Applications/Canopy/WhisperVerses.app'"
  # Copy new build
  scp -r -i ~/.ssh/id_ed25519 "build/Build/Products/Release/WhisperVerses.app" "mediaadmin@10.10.11.80:/Applications/Canopy/WhisperVerses.app"
  # Launch
  ssh -i ~/.ssh/id_ed25519 mediaadmin@10.10.11.80 "open '/Applications/Canopy/WhisperVerses.app'"
  ```
- **IMPORTANT:** Do NOT use rsync — OneDrive extended attributes cause silent failures where the binary doesn't update. Always `rm -rf` then `scp -r`.
- Debug log: `/tmp/whisper_debug.log` on RUBI (audio processor RMS, VAD state, transcription errors)

## Key Files

- `AppState.swift` - Main app state, verse capture pipeline
- `PresentationIndexer.swift` - Pro7 library indexing with lazy loading
- `ProPresentationMap.swift` - Verse → slide location mapping
- `ProPresenterAPI.swift` - REST API client for Pro7
- `VerseDetector.swift` - Bible verse reference detection in text
