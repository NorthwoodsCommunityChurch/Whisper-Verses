import SwiftUI

// MARK: - Hashable Conformance for Navigation

extension BibleBook: Hashable {
    public static func == (lhs: BibleBook, rhs: BibleBook) -> Bool { lhs.code == rhs.code }
    public func hash(into hasher: inout Hasher) { hasher.combine(code) }
}

// MARK: - Navigation Destination

private enum PickerDestination: Hashable {
    case chapters(BibleBook)
    case verses(BibleBook, chapter: Int)
}

// MARK: - Button Style

private struct GridButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// MARK: - Main View

struct ManualVersePicker: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var path = NavigationPath()

    private let bookIndex = BibleBookIndex.load()

    var body: some View {
        NavigationStack(path: $path) {
            BooksView(bookIndex: bookIndex, path: $path)
                .navigationDestination(for: PickerDestination.self) { destination in
                    switch destination {
                    case .chapters(let book):
                        ChaptersView(book: book, path: $path)
                    case .verses(let book, let chapter):
                        VersesView(book: book, chapter: chapter, dismissSheet: { dismiss() })
                    }
                }
        }
        .frame(minWidth: 380, minHeight: 480)
    }
}

// MARK: - Books Screen

private struct BooksView: View {
    let bookIndex: BibleBookIndex
    @Binding var path: NavigationPath

    var body: some View {
        List {
            Section("Old Testament") {
                ForEach(Array(bookIndex.books.prefix(39))) { book in
                    Button(book.name) {
                        path.append(PickerDestination.chapters(book))
                    }
                    .buttonStyle(.plain)
                }
            }
            Section("New Testament") {
                ForEach(Array(bookIndex.books.dropFirst(39))) { book in
                    Button(book.name) {
                        path.append(PickerDestination.chapters(book))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Pick a Verse")
    }
}

// MARK: - Chapters Screen

private struct ChaptersView: View {
    let book: BibleBook
    @Binding var path: NavigationPath

    private let columns = Array(repeating: GridItem(.flexible()), count: 3)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(1...book.chapterCount, id: \.self) { chapter in
                    Button("\(chapter)") {
                        path.append(PickerDestination.verses(book, chapter: chapter))
                    }
                    .buttonStyle(GridButtonStyle(isSelected: false))
                }
            }
            .padding()
        }
        .navigationTitle(book.name)
    }
}

// MARK: - Verses Screen

private struct VersesView: View {
    @Environment(AppState.self) private var appState

    let book: BibleBook
    let chapter: Int
    let dismissSheet: () -> Void

    @State private var startVerse: Int? = nil
    @State private var endVerse: Int? = nil

    private let columns = Array(repeating: GridItem(.flexible()), count: 5)

    private var verseCount: Int {
        book.verseCount(forChapter: chapter) ?? 0
    }

    private var captureLabel: String {
        guard let start = startVerse else { return "Capture" }
        if let end = endVerse, end != start {
            let lo = min(start, end)
            let hi = max(start, end)
            return "Capture \(book.name) \(chapter):\(lo)–\(hi)"
        }
        return "Capture \(book.name) \(chapter):\(start)"
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(1...max(verseCount, 1), id: \.self) { verse in
                    Button("\(verse)") {
                        handleVerseTap(verse)
                    }
                    .buttonStyle(GridButtonStyle(isSelected: isSelected(verse)))
                }
            }
            .padding()
            .padding(.bottom, startVerse != nil ? 60 : 0)
        }
        .safeAreaInset(edge: .bottom) {
            if startVerse != nil {
                Button(captureLabel) {
                    captureSelection()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.bar)
            }
        }
        .navigationTitle("\(book.name) Ch. \(chapter)")
    }

    private func handleVerseTap(_ verse: Int) {
        if startVerse == nil {
            startVerse = verse
        } else if endVerse == nil {
            if verse == startVerse {
                startVerse = nil
            } else {
                endVerse = verse
            }
        } else {
            startVerse = verse
            endVerse = nil
        }
    }

    private func isSelected(_ verse: Int) -> Bool {
        guard let start = startVerse else { return false }
        if let end = endVerse {
            let lo = min(start, end)
            let hi = max(start, end)
            return verse >= lo && verse <= hi
        }
        return verse == start
    }

    private func captureSelection() {
        guard let start = startVerse else { return }
        let lo: Int
        let hi: Int?
        if let end = endVerse, end != start {
            lo = min(start, end)
            hi = max(start, end)
        } else {
            lo = start
            hi = nil
        }

        let reference = BibleReference(
            bookCode: book.code,
            bookName: book.name,
            chapter: chapter,
            verseStart: lo,
            verseEnd: hi
        )
        let detectedVerse = DetectedVerse(
            reference: reference,
            confidence: .high,
            detectedAt: Date(),
            sourceText: "Manually selected"
        )
        appState.detectedVerses.append(detectedVerse)
        Task {
            await appState.captureVerseSlide(detectedVerse)
        }
        dismissSheet()
    }
}
