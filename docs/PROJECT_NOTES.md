# Project Notes

## Feature Ideas

### Pastor Notes Extraction (Sunday Morning Slide Walkthrough)

**Context:** Every Sunday morning, the production team walks through slides with the pastor on stage. During this walkthrough, the pastor often gives notes about specific slides (timing cues, emphasis points, things to skip, etc.). It would be valuable to automatically capture these notes from the transcript.

**Challenge:** Distinguishing what is a "note" vs. regular conversation or verse reading requires semantic understanding.

#### Possible Approaches

**1. Keyword/Phrase Triggers (Low complexity)**
- Detect phrases that signal notes: "make a note", "on this slide", "skip this", "hold here longer", "I'll pause here", "remember to", "don't forget"
- Pro: Simple regex/pattern matching, works offline
- Con: May miss notes that don't use trigger phrases; false positives on similar phrases in scripture

**2. Operator-Triggered Marking (Low complexity)**
- Add a "Capture Note" button the operator presses when pastor starts giving a note
- Could be a toggle (start/stop) or a timed window (next 10 seconds = note)
- Pro: High accuracy, user is already watching the transcript
- Con: Requires active operator attention, might miss notes if operator is distracted

**3. Slide Context Association (Medium complexity)**
- When a note is captured (manually or automatically), associate it with the current ProPresenter slide
- Export notes as a list keyed by slide number/title
- Could integrate with the existing `PresentationIndexer` and `SlideImageCapture` services

**4. LLM Classification (High complexity)**
- Send transcript segments to an LLM to classify as "note" vs. "content"
- Could use a local model or API
- Pro: Could handle nuanced notes without explicit trigger phrases
- Con: Latency, cost, complexity; may be overkill for the use case

**5. Heuristic: Non-Verse Content During Walkthrough (Medium complexity)**
- During slide walkthrough mode, anything that isn't a detected Bible verse could be treated as a potential note
- Combine with keyword boosting for higher confidence
- Pro: Builds on existing `VerseDetector` infrastructure
- Con: Would capture all conversation, not just notes

#### Recommended Approach

Start with **Option 2 (Operator-Triggered)** as the primary mechanism:
- Add a "Note" button in the UI
- When pressed, capture the next N seconds of transcript as a note
- Associate with current slide from ProPresenter

Add **Option 1 (Keyword Triggers)** as an optional enhancement:
- Highlight potential notes in the transcript with a different color
- Let operator confirm/dismiss with one click

This gives accuracy through human judgment while reducing friction with smart suggestions.

#### Data Model Considerations

```swift
struct PastorNote {
    let id: UUID
    let text: String
    let timestamp: Date
    let slideUUID: String?      // ProPresenter slide UUID if available
    let slideIndex: Int?        // Slide number in presentation
    let presentationName: String?
    let confidence: NoteConfidence  // .manual, .keywordDetected, .inferred
}

enum NoteConfidence {
    case manual           // Operator pressed the Note button
    case keywordDetected  // Matched a trigger phrase
    case inferred         // Heuristic detection
}
```

#### UI Considerations

- Notes panel alongside or below the verse capture panel
- Export notes as markdown or text file, grouped by slide
- Option to show notes overlaid on slide thumbnails
