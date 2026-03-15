# WhisprPro Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS transcription app using whisper.cpp locally, with recording, editing, diarization, and export.

**Architecture:** Four-layer SwiftUI app (UI → Services → Engine Bridge → Data) using MVVM, SwiftData persistence, whisper.cpp via SPM C bridge, and Core ML for speaker diarization.

**Tech Stack:** Swift, SwiftUI, SwiftData, whisper.cpp (C), AVFoundation, AVAudioEngine, CoreML, Accelerate

---

## Chunk 1: Project Scaffold + Data Model

### Task 1: Create Xcode Project Structure

**Files:**
- Create: `WhisprPro/App/WhisprProApp.swift`
- Create: `WhisprPro/App/ContentView.swift`

- [ ] **Step 1: Create Xcode project via command line**

Run:
```bash
mkdir -p WhisprPro/{App,Models,Views,ViewModels,Services,Bridge,Resources}
```

- [ ] **Step 2: Create app entry point**

Create `WhisprPro/App/WhisprProApp.swift`:
```swift
import SwiftUI
import SwiftData

@main
struct WhisprProApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Transcription.self,
            Segment.self,
            Speaker.self,
            MLModelInfo.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)

        Settings {
            SettingsView()
        }
        .modelContainer(sharedModelContainer)
    }
}
```

- [ ] **Step 3: Create placeholder ContentView**

Create `WhisprPro/App/ContentView.swift`:
```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            Text("Sidebar")
        } detail: {
            Text("Select a transcription")
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}
```

- [ ] **Step 4: Create placeholder SettingsView**

Create `WhisprPro/Views/SettingsView.swift`:
```swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Text("Models").tabItem { Label("Models", systemImage: "cpu") }
            Text("General").tabItem { Label("General", systemImage: "gear") }
            Text("Export").tabItem { Label("Export", systemImage: "square.and.arrow.up") }
        }
        .frame(width: 500, height: 300)
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add WhisprPro/
git commit -m "feat: scaffold Xcode project structure with app entry point"
```

### Task 2: SwiftData Models

**Files:**
- Create: `WhisprPro/Models/Transcription.swift`
- Create: `WhisprPro/Models/Segment.swift`
- Create: `WhisprPro/Models/Speaker.swift`
- Create: `WhisprPro/Models/MLModelInfo.swift`

- [ ] **Step 1: Write unit test for Transcription model**

Create `WhisprProTests/Models/TranscriptionTests.swift`:
```swift
import Testing
import SwiftData
@testable import WhisprPro

@Suite("Transcription Model Tests")
struct TranscriptionTests {
    @Test func createTranscription() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Transcription.self, Segment.self, Speaker.self,
            configurations: config
        )
        let context = ModelContext(container)

        let transcription = Transcription(
            title: "Test Recording",
            language: "en",
            modelName: "tiny",
            duration: 120.0
        )
        context.insert(transcription)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Transcription>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Test Recording")
        #expect(fetched.first?.status == .pending)
        #expect(fetched.first?.segments.isEmpty == true)
    }

    @Test func statusTransitions() {
        let t = Transcription(title: "Test", language: "en", modelName: "tiny", duration: 60)
        #expect(t.status == .pending)
        t.status = .transcribing
        #expect(t.status == .transcribing)
        t.status = .completed
        #expect(t.status == .completed)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme WhisprPro -destination 'platform=macOS'`
Expected: FAIL — models don't exist yet

- [ ] **Step 3: Create Transcription model**

Create `WhisprPro/Models/Transcription.swift`:
```swift
import Foundation
import SwiftData

enum TranscriptionStatus: String, Codable {
    case pending
    case transcribing
    case diarizing
    case completed
    case failed
}

@Model
final class Transcription {
    var id: UUID
    var title: String
    var sourceURL: URL?
    var language: String
    var modelName: String
    var duration: TimeInterval
    var createdAt: Date
    var status: TranscriptionStatus
    var progress: Double
    var errorMessage: String?
    var diarizationError: String?

    @Relationship(deleteRule: .cascade, inverse: \Segment.transcription)
    var segments: [Segment]

    @Relationship(deleteRule: .cascade, inverse: \Speaker.transcription)
    var speakers: [Speaker]

    init(
        title: String,
        sourceURL: URL? = nil,
        language: String,
        modelName: String,
        duration: TimeInterval
    ) {
        self.id = UUID()
        self.title = title
        self.sourceURL = sourceURL
        self.language = language
        self.modelName = modelName
        self.duration = duration
        self.createdAt = Date()
        self.status = .pending
        self.progress = 0.0
        self.segments = []
        self.speakers = []
    }
}
```

- [ ] **Step 4: Create Segment model**

Create `WhisprPro/Models/Segment.swift`:
```swift
import Foundation
import SwiftData

@Model
final class Segment {
    var id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String
    var isEdited: Bool
    var transcription: Transcription?
    var speaker: Speaker?

    init(startTime: TimeInterval, endTime: TimeInterval, text: String) {
        self.id = UUID()
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.isEdited = false
    }
}
```

- [ ] **Step 5: Create Speaker model**

Create `WhisprPro/Models/Speaker.swift`:
```swift
import Foundation
import SwiftData

@Model
final class Speaker {
    var id: UUID
    var label: String
    var color: String
    var transcription: Transcription?

    @Relationship(inverse: \Segment.speaker)
    var segments: [Segment]

    init(label: String, color: String) {
        self.id = UUID()
        self.label = label
        self.color = color
        self.segments = []
    }
}
```

- [ ] **Step 6: Create MLModelInfo model**

Create `WhisprPro/Models/MLModelInfo.swift`:
```swift
import Foundation
import SwiftData

enum ModelKind: String, Codable {
    case whisper
    case diarization
}

@Model
final class MLModelInfo {
    var name: String
    var kind: ModelKind
    var size: Int64
    var isDownloaded: Bool
    var localURL: URL?
    @Transient var downloadProgress: Double = 0.0

    init(name: String, kind: ModelKind, size: Int64) {
        self.name = name
        self.kind = kind
        self.size = size
        self.isDownloaded = false
    }
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `xcodebuild test -scheme WhisprPro -destination 'platform=macOS'`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add WhisprPro/Models/ WhisprProTests/
git commit -m "feat: add SwiftData models for Transcription, Segment, Speaker, MLModelInfo"
```

### Task 3: ModelManager Service

**Files:**
- Create: `WhisprPro/Services/ModelManager.swift`
- Create: `WhisprProTests/Services/ModelManagerTests.swift`

- [ ] **Step 1: Write test for ModelManager**

Create `WhisprProTests/Services/ModelManagerTests.swift`:
```swift
import Testing
import Foundation
@testable import WhisprPro

@Suite("ModelManager Tests")
struct ModelManagerTests {
    @Test func modelsDirectory() {
        let manager = ModelManager()
        let whisperDir = manager.modelsDirectory(for: .whisper)
        #expect(whisperDir.path().contains("WhisprPro/Models/whisper"))

        let diarizationDir = manager.modelsDirectory(for: .diarization)
        #expect(diarizationDir.path().contains("WhisprPro/Models/diarization"))
    }

    @Test func availableWhisperModels() {
        let models = ModelManager.availableWhisperModels
        #expect(models.count == 6)
        #expect(models.first?.name == "tiny")
        #expect(models.last?.name == "large-v3-turbo")
    }

    @Test func modelPath() {
        let manager = ModelManager()
        let path = manager.modelPath(name: "tiny", kind: .whisper)
        #expect(path.lastPathComponent == "ggml-tiny.bin")
    }

    @Test func isModelDownloaded() async {
        let manager = ModelManager()
        let result = await manager.isModelDownloaded(name: "nonexistent", kind: .whisper)
        #expect(result == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — ModelManager doesn't exist

- [ ] **Step 3: Implement ModelManager**

Create `WhisprPro/Services/ModelManager.swift`:
```swift
import Foundation

struct WhisperModelDefinition {
    let name: String
    let size: Int64
    let downloadURL: URL
}

final class ModelManager: Sendable {
    // Path helpers are nonisolated — no mutable state needed
    static let availableWhisperModels: [WhisperModelDefinition] = [
        WhisperModelDefinition(
            name: "tiny",
            size: 75_000_000,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin")!
        ),
        WhisperModelDefinition(
            name: "base",
            size: 142_000_000,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")!
        ),
        WhisperModelDefinition(
            name: "small",
            size: 466_000_000,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin")!
        ),
        WhisperModelDefinition(
            name: "medium",
            size: 1_500_000_000,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin")!
        ),
        WhisperModelDefinition(
            name: "large-v3",
            size: 2_900_000_000,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin")!
        ),
        WhisperModelDefinition(
            name: "large-v3-turbo",
            size: 1_600_000_000,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")!
        ),
    ]

    private let appSupportDir: URL

    init() {
        self.appSupportDir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("WhisprPro")
    }

    func modelsDirectory(for kind: ModelKind) -> URL {
        appSupportDir.appendingPathComponent("Models/\(kind.rawValue)")
    }

    func modelPath(name: String, kind: ModelKind) -> URL {
        let filename = kind == .whisper ? "ggml-\(name).bin" : "\(name).mlmodel"
        return modelsDirectory(for: kind).appendingPathComponent(filename)
    }

    func isModelDownloaded(name: String, kind: ModelKind) -> Bool {
        FileManager.default.fileExists(atPath: modelPath(name: name, kind: kind).path())
    }

    func ensureDirectoriesExist() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: modelsDirectory(for: .whisper), withIntermediateDirectories: true)
        try fm.createDirectory(at: modelsDirectory(for: .diarization), withIntermediateDirectories: true)
    }

    func downloadModel(
        definition: WhisperModelDefinition,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try ensureDirectoriesExist()
        let destination = modelPath(name: definition.name, kind: .whisper)

        let delegate = DownloadProgressDelegate(progressHandler: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let (tempURL, response) = try await session.download(from: definition.downloadURL)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ModelManagerError.downloadFailed
        }

        if FileManager.default.fileExists(atPath: destination.path()) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        progress(1.0)
        return destination
    }

    func deleteModel(name: String, kind: ModelKind) throws {
        let path = modelPath(name: name, kind: kind)
        if FileManager.default.fileExists(atPath: path.path()) {
            try FileManager.default.removeItem(at: path)
        }
    }
}

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progressHandler: (Double) -> Void

    init(progressHandler: @escaping (Double) -> Void) {
        self.progressHandler = progressHandler
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progressHandler(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Handled by the async download call
    }
}

enum ModelManagerError: Error, LocalizedError {
    case downloadFailed
    case modelNotFound

    var errorDescription: String? {
        switch self {
        case .downloadFailed: "Failed to download model"
        case .modelNotFound: "Model file not found"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme WhisprPro -destination 'platform=macOS'`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add WhisprPro/Services/ModelManager.swift WhisprProTests/Services/
git commit -m "feat: add ModelManager for Whisper model download and storage"
```

---

## Chunk 2: WhisperBridge + Audio Processing

### Task 4: whisper.cpp SPM Package

**Files:**
- Create: `Packages/WhisperCpp/Package.swift`
- Create: `Packages/WhisperCpp/Sources/WhisperCpp/whisper_wrapper.h`
- Create: `Packages/WhisperCpp/Sources/WhisperCpp/whisper_wrapper.c`
- Create: `Packages/WhisperCpp/Sources/WhisperCpp/include/module.modulemap`

- [ ] **Step 1: Create SPM package structure**

```bash
mkdir -p Packages/WhisperCpp/Sources/WhisperCpp/include
```

- [ ] **Step 2: Create Package.swift**

Create `Packages/WhisperCpp/Package.swift`:
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhisperCpp",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WhisperCpp", targets: ["WhisperCpp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ggerganov/whisper.cpp.git", from: "1.7.2"),
    ],
    targets: [
        .target(
            name: "WhisperCpp",
            dependencies: [
                .product(name: "whisper", package: "whisper.cpp"),
            ],
            path: "Sources/WhisperCpp",
            publicHeadersPath: "include"
        ),
    ]
)
```

- [ ] **Step 3: Create C wrapper header**

Create `Packages/WhisperCpp/Sources/WhisperCpp/include/whisper_wrapper.h`:
```c
#ifndef WHISPER_WRAPPER_H
#define WHISPER_WRAPPER_H

#include <stdbool.h>
#include <stdint.h>

typedef struct whisper_context whisper_context;

typedef struct {
    int64_t start_ms;
    int64_t end_ms;
    const char *text;
} whisper_segment_result;

typedef void (*whisper_progress_callback)(float progress, void *user_data);

whisper_context *wrapper_init(const char *model_path);
void wrapper_free(whisper_context *ctx);

int wrapper_transcribe(
    whisper_context *ctx,
    const char *audio_path,
    const char *language,
    bool translate,
    whisper_progress_callback progress_cb,
    void *user_data
);

int wrapper_get_segment_count(whisper_context *ctx);
whisper_segment_result wrapper_get_segment(whisper_context *ctx, int index);

#endif
```

- [ ] **Step 4: Create C wrapper implementation**

Create `Packages/WhisperCpp/Sources/WhisperCpp/whisper_wrapper.c`:
```c
#include "include/whisper_wrapper.h"
#include "whisper.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

// Audio loading helper — reads WAV 16kHz mono PCM
// Note: Assumes standard 44-byte PCM WAV header produced by AudioConverter.
// AudioConverter always outputs canonical WAV format, so this is safe.
static bool load_wav_file(const char *path, float **data, int *n_samples) {
    FILE *f = fopen(path, "rb");
    if (!f) return false;

    // Read "data" chunk offset from WAV header for robustness
    // For standard PCM WAV from AudioConverter, data starts at byte 44
    fseek(f, 0, SEEK_END);
    long file_size = ftell(f);
    fseek(f, 44, SEEK_SET);

    long data_size = file_size - 44;
    int n = (int)(data_size / sizeof(int16_t));

    int16_t *pcm = (int16_t *)malloc(data_size);
    if (!pcm) { fclose(f); return false; }

    fread(pcm, sizeof(int16_t), n, f);
    fclose(f);

    float *float_data = (float *)malloc(n * sizeof(float));
    if (!float_data) { free(pcm); return false; }

    for (int i = 0; i < n; i++) {
        float_data[i] = (float)pcm[i] / 32768.0f;
    }

    free(pcm);
    *data = float_data;
    *n_samples = n;
    return true;
}

struct progress_user_data {
    whisper_progress_callback cb;
    void *user_data;
};

static void internal_progress_cb(struct whisper_context *ctx, struct whisper_state *state, int progress, void *user_data) {
    struct progress_user_data *pud = (struct progress_user_data *)user_data;
    if (pud && pud->cb) {
        pud->cb((float)progress / 100.0f, pud->user_data);
    }
}

whisper_context *wrapper_init(const char *model_path) {
    struct whisper_context_params cparams = whisper_context_default_params();
    return whisper_init_from_file_with_params(model_path, cparams);
}

void wrapper_free(whisper_context *ctx) {
    if (ctx) whisper_free(ctx);
}

int wrapper_transcribe(
    whisper_context *ctx,
    const char *audio_path,
    const char *language,
    bool translate,
    whisper_progress_callback progress_cb,
    void *user_data
) {
    float *audio_data = NULL;
    int n_samples = 0;

    if (!load_wav_file(audio_path, &audio_data, &n_samples)) {
        return -1;
    }

    struct whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.language = language;
    params.translate = translate;
    params.print_progress = false;
    params.print_timestamps = false;

    struct progress_user_data pud = { progress_cb, user_data };
    params.progress_callback = internal_progress_cb;
    params.progress_callback_user_data = &pud;

    int result = whisper_full(ctx, params, audio_data, n_samples);
    free(audio_data);
    return result;
}

int wrapper_get_segment_count(whisper_context *ctx) {
    return whisper_full_n_segments(ctx);
}

whisper_segment_result wrapper_get_segment(whisper_context *ctx, int index) {
    whisper_segment_result seg;
    seg.start_ms = whisper_full_get_segment_t0(ctx, index) * 10;
    seg.end_ms = whisper_full_get_segment_t1(ctx, index) * 10;
    seg.text = whisper_full_get_segment_text(ctx, index);
    return seg;
}
```

- [ ] **Step 5: Create module map**

Create `Packages/WhisperCpp/Sources/WhisperCpp/include/module.modulemap`:
```
module WhisperCpp {
    header "whisper_wrapper.h"
    export *
}
```

- [ ] **Step 6: Commit**

```bash
git add Packages/
git commit -m "feat: add WhisperCpp SPM package with C bridge"
```

### Task 5: WhisperBridge Swift Interface

**Files:**
- Create: `WhisprPro/Bridge/WhisperBridge.swift`
- Create: `WhisprProTests/Bridge/WhisperBridgeTests.swift`

- [ ] **Step 1: Write test for WhisperBridge**

Create `WhisprProTests/Bridge/WhisperBridgeTests.swift`:
```swift
import Testing
@testable import WhisprPro

@Suite("WhisperBridge Tests")
struct WhisperBridgeTests {
    @Test func segmentResultConversion() {
        let segment = WhisperSegment(
            startTime: 1.5,
            endTime: 3.2,
            text: "Hello world"
        )
        #expect(segment.startTime == 1.5)
        #expect(segment.endTime == 3.2)
        #expect(segment.text == "Hello world")
    }

    @Test func bridgeInitWithInvalidPath() async {
        let bridge = WhisperBridge()
        do {
            try await bridge.loadModel(path: URL(filePath: "/nonexistent/model.bin"))
            Issue.record("Should have thrown")
        } catch {
            #expect(error is WhisperBridgeError)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — WhisperBridge doesn't exist

- [ ] **Step 3: Implement WhisperBridge**

Create `WhisprPro/Bridge/WhisperBridge.swift`:
```swift
import Foundation
import WhisperCpp

struct WhisperSegment {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}

enum WhisperBridgeError: Error, LocalizedError {
    case modelLoadFailed
    case transcriptionFailed
    case noModelLoaded
    case cancelled

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed: "Failed to load Whisper model"
        case .transcriptionFailed: "Transcription failed"
        case .noModelLoaded: "No model loaded"
        case .cancelled: "Transcription cancelled"
        }
    }
}

actor WhisperBridge {
    private var context: OpaquePointer?
    private var isCancelled = false

    func loadModel(path: URL) throws {
        if let ctx = context {
            wrapper_free(ctx)
        }
        guard let ctx = wrapper_init(path.path()) else {
            throw WhisperBridgeError.modelLoadFailed
        }
        self.context = ctx
    }

    func transcribe(
        audioPath: URL,
        language: String = "auto",
        translate: Bool = false,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [WhisperSegment] {
        guard let ctx = context else {
            throw WhisperBridgeError.noModelLoaded
        }

        isCancelled = false

        let audioPathStr = audioPath.path()
        let languageStr = language

        let result = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let progressCallback: whisper_progress_callback = { progressValue, userData in
                    guard let ptr = userData else { return }
                    let callback = Unmanaged<ProgressCallbackBox>.fromOpaque(ptr)
                        .takeUnretainedValue()
                    callback.callback(Double(progressValue))
                }

                let box = ProgressCallbackBox(callback: progress)
                let boxPtr = Unmanaged.passRetained(box).toOpaque()

                let res = wrapper_transcribe(
                    ctx,
                    audioPathStr,
                    languageStr,
                    translate,
                    progressCallback,
                    boxPtr
                )

                Unmanaged<ProgressCallbackBox>.fromOpaque(boxPtr).release()
                continuation.resume(returning: res)
            }
        }

        if isCancelled {
            throw WhisperBridgeError.cancelled
        }

        guard result == 0 else {
            throw WhisperBridgeError.transcriptionFailed
        }

        let segmentCount = wrapper_get_segment_count(ctx)
        var segments: [WhisperSegment] = []

        for i in 0..<segmentCount {
            let seg = wrapper_get_segment(ctx, Int32(i))
            let text = String(cString: seg.text)
            segments.append(WhisperSegment(
                startTime: Double(seg.start_ms) / 1000.0,
                endTime: Double(seg.end_ms) / 1000.0,
                text: text.trimmingCharacters(in: .whitespaces)
            ))
        }

        return segments
    }

    /// Request cancellation. Note: whisper.cpp does not support mid-transcription
    /// abort, so this flag is checked after the current transcription completes.
    /// A future improvement could use whisper_abort_callback for true cancellation.
    func cancel() {
        isCancelled = true
    }

    deinit {
        if let ctx = context {
            wrapper_free(ctx)
        }
    }
}

private final class ProgressCallbackBox: @unchecked Sendable {
    let callback: (Double) -> Void
    init(callback: @escaping (Double) -> Void) {
        self.callback = callback
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme WhisprPro -destination 'platform=macOS'`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add WhisprPro/Bridge/ WhisprProTests/Bridge/
git commit -m "feat: add WhisperBridge Swift interface to whisper.cpp"
```

### Task 6: Audio Conversion Service

**Files:**
- Create: `WhisprPro/Services/AudioConverter.swift`
- Create: `WhisprProTests/Services/AudioConverterTests.swift`

- [ ] **Step 1: Write test for AudioConverter**

Create `WhisprProTests/Services/AudioConverterTests.swift`:
```swift
import Testing
import Foundation
@testable import WhisprPro

@Suite("AudioConverter Tests")
struct AudioConverterTests {
    @Test func supportedFormats() {
        let supported = AudioConverter.supportedExtensions
        #expect(supported.contains("mp3"))
        #expect(supported.contains("wav"))
        #expect(supported.contains("m4a"))
        #expect(supported.contains("mp4"))
        #expect(supported.contains("mov"))
        #expect(supported.contains("aac"))
        #expect(supported.contains("flac"))
        #expect(supported.contains("ogg"))
    }

    @Test func isSupportedFile() {
        #expect(AudioConverter.isSupported(URL(filePath: "/test/file.mp3")) == true)
        #expect(AudioConverter.isSupported(URL(filePath: "/test/file.txt")) == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL

- [ ] **Step 3: Implement AudioConverter**

Create `WhisprPro/Services/AudioConverter.swift`:
```swift
import Foundation
import AVFoundation

enum AudioConverterError: Error, LocalizedError {
    case unsupportedFormat(String)
    case conversionFailed(String)
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext): "Unsupported audio format: \(ext)"
        case .conversionFailed(let msg): "Audio conversion failed: \(msg)"
        case .fileNotFound: "Audio file not found"
        }
    }
}

struct AudioConverter {
    static let supportedExtensions: Set<String> = [
        "mp3", "wav", "m4a", "mp4", "mov", "aac", "flac", "ogg"
    ]

    static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func convertToWAV(input: URL, output: URL) async throws {
        guard FileManager.default.fileExists(atPath: input.path()) else {
            throw AudioConverterError.fileNotFound
        }

        guard isSupported(input) else {
            throw AudioConverterError.unsupportedFormat(input.pathExtension)
        }

        // If already WAV 16kHz mono, check and possibly skip conversion
        let asset = AVURLAsset(url: input)

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioConverterError.conversionFailed("No audio track found")
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        guard let reader = try? AVAssetReader(asset: asset) else {
            throw AudioConverterError.conversionFailed("Cannot create asset reader")
        }

        let readerOutput = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: outputSettings
        )
        reader.add(readerOutput)

        guard let writer = try? AVAssetWriter(outputURL: output, fileType: .wav) else {
            throw AudioConverterError.conversionFailed("Cannot create asset writer")
        }

        let writerInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: outputSettings
        )
        writer.add(writerInput)

        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        await withCheckedContinuation { continuation in
            writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "audio-converter")) {
                while writerInput.isReadyForMoreMediaData {
                    guard let buffer = readerOutput.copyNextSampleBuffer() else {
                        writerInput.markAsFinished()
                        writer.finishWriting {
                            continuation.resume()
                        }
                        return
                    }
                    writerInput.append(buffer)
                }
            }
        }

        guard writer.status == .completed else {
            throw AudioConverterError.conversionFailed(
                writer.error?.localizedDescription ?? "Unknown error"
            )
        }
    }

    static func duration(of url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return duration.seconds
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme WhisprPro -destination 'platform=macOS'`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add WhisprPro/Services/AudioConverter.swift WhisprProTests/Services/
git commit -m "feat: add AudioConverter for WAV 16kHz mono conversion"
```

### Task 7: TranscriptionService

**Files:**
- Create: `WhisprPro/Services/TranscriptionService.swift`
- Create: `WhisprProTests/Services/TranscriptionServiceTests.swift`

- [ ] **Step 1: Write test for TranscriptionService**

Create `WhisprProTests/Services/TranscriptionServiceTests.swift`:
```swift
import Testing
import SwiftData
import Foundation
@testable import WhisprPro

@Suite("TranscriptionService Tests")
struct TranscriptionServiceTests {
    @Test func createTranscriptionFromFile() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Transcription.self, Segment.self, Speaker.self, MLModelInfo.self,
            configurations: config
        )
        let context = ModelContext(container)

        let service = TranscriptionService(modelContext: context)

        let transcription = service.createTranscription(
            title: "Test File",
            sourceURL: URL(filePath: "/tmp/test.mp3"),
            language: "en",
            modelName: "tiny",
            duration: 60.0
        )

        #expect(transcription.title == "Test File")
        #expect(transcription.status == .pending)
        #expect(transcription.language == "en")
    }

    @Test func enqueueSetsStatusToPending() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Transcription.self, Segment.self, Speaker.self, MLModelInfo.self,
            configurations: config
        )
        let context = ModelContext(container)
        let service = TranscriptionService(modelContext: context)

        let transcription = service.createTranscription(
            title: "Queue Test",
            sourceURL: nil,
            language: "en",
            modelName: "tiny",
            duration: 30.0
        )
        #expect(transcription.status == .pending)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL

- [ ] **Step 3: Implement TranscriptionService**

Create `WhisprPro/Services/TranscriptionService.swift`:
```swift
import Foundation
import SwiftData

actor TranscriptionService {
    private let modelContext: ModelContext
    private let whisperBridge = WhisperBridge()
    private let modelManager = ModelManager()
    private var isProcessing = false
    private var pendingQueue: [Transcription] = []

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    nonisolated func createTranscription(
        title: String,
        sourceURL: URL?,
        language: String,
        modelName: String,
        duration: TimeInterval
    ) -> Transcription {
        let transcription = Transcription(
            title: title,
            sourceURL: sourceURL,
            language: language,
            modelName: modelName,
            duration: duration
        )
        return transcription
    }

    func enqueue(_ transcription: Transcription) async {
        modelContext.insert(transcription)
        try? modelContext.save()
        pendingQueue.append(transcription)
        await processNextIfIdle()
    }

    private func processNextIfIdle() async {
        guard !isProcessing, let transcription = pendingQueue.first else { return }
        pendingQueue.removeFirst()
        isProcessing = true

        do {
            try await processTranscription(transcription)
        } catch {
            transcription.status = .failed
            transcription.errorMessage = error.localizedDescription
        }

        isProcessing = false
        try? modelContext.save()

        if !pendingQueue.isEmpty {
            await processNextIfIdle()
        }
    }

    private func processTranscription(_ transcription: Transcription) async throws {
        // Step 1: Convert audio to WAV
        transcription.status = .transcribing
        transcription.progress = 0.0
        try? modelContext.save()

        let tempDir = FileManager.default.temporaryDirectory
        let wavURL = tempDir.appendingPathComponent("\(transcription.id.uuidString).wav")

        if let sourceURL = transcription.sourceURL {
            try await AudioConverter.convertToWAV(input: sourceURL, output: wavURL)
        }

        // Step 2: Load model
        let modelPath = modelManager.modelPath(
            name: transcription.modelName,
            kind: .whisper
        )
        try await whisperBridge.loadModel(path: modelPath)

        // Step 3: Transcribe
        let segments = try await whisperBridge.transcribe(
            audioPath: wavURL,
            language: transcription.language,
            translate: false
        ) { progress in
            Task { @MainActor in
                transcription.progress = progress
            }
        }

        // Step 4: Create segment records
        for whisperSeg in segments {
            let segment = Segment(
                startTime: whisperSeg.startTime,
                endTime: whisperSeg.endTime,
                text: whisperSeg.text
            )
            segment.transcription = transcription
            modelContext.insert(segment)
        }

        // Step 5: Diarization (if model available)
        // Integrated in Task 17 (Chunk 5) — hooks into DiarizationService here
        if modelManager.isModelDownloaded(name: "diarization-pyannote", kind: .diarization) {
            transcription.status = .diarizing
            try? modelContext.save()

            let diarizationService = DiarizationService()
            let diarizationModelPath = modelManager.modelPath(name: "diarization-pyannote", kind: .diarization)
            do {
                let results = try await diarizationService.diarize(
                    audioURL: wavURL,
                    segments: transcription.segments,
                    modelURL: diarizationModelPath
                )

                let speakerCount = Set(results.map(\.speakerIndex)).count
                var speakers: [Int: Speaker] = [:]
                for i in 0..<speakerCount {
                    let speaker = Speaker(
                        label: "Speaker \(i + 1)",
                        color: DiarizationService.speakerColors[i % DiarizationService.speakerColors.count]
                    )
                    speaker.transcription = transcription
                    modelContext.insert(speaker)
                    speakers[i] = speaker
                }
                for result in results {
                    if let segment = transcription.segments.first(where: { $0.id == result.segmentID }) {
                        segment.speaker = speakers[result.speakerIndex]
                    }
                }
            } catch {
                // Diarization failure does not fail the transcription
                transcription.diarizationError = error.localizedDescription
            }
        }

        transcription.status = .completed
        transcription.progress = 1.0
        try? modelContext.save()

        // Cleanup temp file
        try? FileManager.default.removeItem(at: wavURL)
    }

    func cancelCurrent() async {
        await whisperBridge.cancel()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme WhisprPro -destination 'platform=macOS'`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add WhisprPro/Services/TranscriptionService.swift WhisprProTests/Services/
git commit -m "feat: add TranscriptionService with queue and audio conversion pipeline"
```

---

## Chunk 3: Core UI — Sidebar + Transcript View + Audio Player

### Task 8: SidebarView

**Files:**
- Create: `WhisprPro/Views/SidebarView.swift`
- Create: `WhisprPro/ViewModels/TranscriptionViewModel.swift`

- [ ] **Step 1: Create TranscriptionViewModel**

Create `WhisprPro/ViewModels/TranscriptionViewModel.swift`:
```swift
import Foundation
import SwiftData
import SwiftUI

@Observable
final class TranscriptionViewModel {
    var selectedTranscription: Transcription?
    var searchText = ""
    var showRecordingSheet = false
    var showFileImporter = false

    private let modelContext: ModelContext
    private(set) var transcriptionService: TranscriptionService

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.transcriptionService = TranscriptionService(modelContext: modelContext)
    }

    func importFile(url: URL) async {
        let title = url.deletingPathExtension().lastPathComponent
        let defaultLanguage = UserDefaults.standard.string(forKey: "defaultLanguage") ?? "auto"
        let defaultModel = UserDefaults.standard.string(forKey: "defaultModel") ?? "tiny"
        do {
            let duration = try await AudioConverter.duration(of: url)
            let transcription = transcriptionService.createTranscription(
                title: title,
                sourceURL: url,
                language: defaultLanguage,
                modelName: defaultModel,
                duration: duration
            )
            selectedTranscription = transcription
            Task {
                await transcriptionService.enqueue(transcription)
            }
        } catch {
            print("Import failed: \(error)")
        }
    }

    func deleteTranscription(_ transcription: Transcription) {
        if selectedTranscription == transcription {
            selectedTranscription = nil
        }
        modelContext.delete(transcription)
        try? modelContext.save()
    }
}
```

- [ ] **Step 2: Create SidebarView**

Create `WhisprPro/Views/SidebarView.swift`:
```swift
import SwiftUI
import SwiftData

struct SidebarView: View {
    @Query(sort: \Transcription.createdAt, order: .reverse)
    private var transcriptions: [Transcription]

    @Bindable var viewModel: TranscriptionViewModel

    var body: some View {
        VStack(spacing: 0) {
            List(filteredTranscriptions, selection: $viewModel.selectedTranscription) { transcription in
                TranscriptionRow(transcription: transcription)
                    .tag(transcription)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            viewModel.deleteTranscription(transcription)
                        }
                    }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search")

            Divider()

            VStack(spacing: 8) {
                Button {
                    viewModel.showFileImporter = true
                } label: {
                    Label("Import File", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.showRecordingSheet = true
                } label: {
                    Label("Record", systemImage: "record.circle")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
    }

    private var filteredTranscriptions: [Transcription] {
        if viewModel.searchText.isEmpty {
            return transcriptions
        }
        return transcriptions.filter {
            $0.title.localizedCaseInsensitiveContains(viewModel.searchText)
        }
    }
}

struct TranscriptionRow: View {
    let transcription: Transcription

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(transcription.title)
                .font(.body)
                .lineLimit(1)

            HStack {
                statusIndicator
                Text(formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch transcription.status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .transcribing, .diarizing:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("\(Int(transcription.progress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private var formattedDuration: String {
        let minutes = Int(transcription.duration) / 60
        let seconds = Int(transcription.duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add WhisprPro/Views/SidebarView.swift WhisprPro/ViewModels/TranscriptionViewModel.swift
git commit -m "feat: add SidebarView with transcription list and import/record actions"
```

### Task 9: AudioPlayerView

**Files:**
- Create: `WhisprPro/Views/AudioPlayerView.swift`
- Create: `WhisprPro/ViewModels/AudioPlayerViewModel.swift`

- [ ] **Step 1: Create AudioPlayerViewModel**

Create `WhisprPro/ViewModels/AudioPlayerViewModel.swift`:
```swift
import Foundation
import AVFoundation

@Observable
final class AudioPlayerViewModel {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var playbackRate: Float = 1.0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func loadAudio(url: URL) {
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.enableRate = true
            player?.prepareToPlay()
            duration = player?.duration ?? 0
        } catch {
            print("Failed to load audio: \(error)")
        }
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            stopTimer()
        } else {
            player.rate = playbackRate
            player.play()
            startTimer()
        }
        isPlaying = !isPlaying
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        player?.rate = rate
    }

    func stop() {
        player?.stop()
        stopTimer()
        isPlaying = false
        currentTime = 0
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            self.currentTime = player.currentTime
            if !player.isPlaying {
                self.isPlaying = false
                self.stopTimer()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        stopTimer()
    }
}
```

- [ ] **Step 2: Create AudioPlayerView**

Create `WhisprPro/Views/AudioPlayerView.swift`:
```swift
import SwiftUI

struct AudioPlayerView: View {
    @Bindable var viewModel: AudioPlayerViewModel

    var body: some View {
        HStack(spacing: 12) {
            Button(action: viewModel.togglePlayback) {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)

            Slider(
                value: Binding(
                    get: { viewModel.currentTime },
                    set: { viewModel.seek(to: $0) }
                ),
                in: 0...max(viewModel.duration, 0.01)
            )

            Text("\(formatTime(viewModel.currentTime)) / \(formatTime(viewModel.duration))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 100)

            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                    Button("\(rate, specifier: "%.2g")x") {
                        viewModel.setRate(Float(rate))
                    }
                }
            } label: {
                Text("\(viewModel.playbackRate, specifier: "%.2g")x")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary)
                    .cornerRadius(4)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding()
        .background(.bar)
        .cornerRadius(8)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add WhisprPro/Views/AudioPlayerView.swift WhisprPro/ViewModels/AudioPlayerViewModel.swift
git commit -m "feat: add AudioPlayerView with playback controls and speed selector"
```

### Task 10: TranscriptView + EditorView

**Files:**
- Create: `WhisprPro/Views/TranscriptView.swift`
- Create: `WhisprPro/Views/EditorView.swift`

- [ ] **Step 1: Create EditorView (segment editor)**

Create `WhisprPro/Views/EditorView.swift`:
```swift
import SwiftUI

struct EditorView: View {
    @Bindable var segment: Segment
    let isActive: Bool
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let speaker = segment.speaker {
                    SpeakerLabelView(speaker: speaker)
                }

                Button {
                    onSeek(segment.startTime)
                } label: {
                    Text(formatTimestamp(segment.startTime))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if segment.isEdited {
                    Image(systemName: "pencil")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("", text: $segment.text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .onChange(of: segment.text) {
                    segment.isEdited = true
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isActive ? Color.accentColor.opacity(0.1) : .clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            onSeek(segment.startTime)
        }
    }

    private func formatTimestamp(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct SpeakerLabelView: View {
    @Bindable var speaker: Speaker
    @State private var isEditing = false
    @State private var editText = ""

    var body: some View {
        if isEditing {
            TextField("Name", text: $editText, onCommit: {
                speaker.label = editText
                isEditing = false
            })
            .textFieldStyle(.plain)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(Color(hex: speaker.color) ?? .primary)
            .frame(width: 100)
        } else {
            Text(speaker.label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color(hex: speaker.color) ?? .primary)
                .onTapGesture {
                    editText = speaker.label
                    isEditing = true
                }
        }
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6,
              let rgb = UInt64(hexSanitized, radix: 16) else {
            return nil
        }

        self.init(
            red: Double((rgb & 0xFF0000) >> 16) / 255.0,
            green: Double((rgb & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgb & 0x0000FF) / 255.0
        )
    }
}
```

- [ ] **Step 2: Create TranscriptView**

Create `WhisprPro/Views/TranscriptView.swift`:
```swift
import SwiftUI

struct TranscriptView: View {
    let transcription: Transcription
    @Bindable var playerViewModel: AudioPlayerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(transcription.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 12) {
                    Label(formatDuration(transcription.duration), systemImage: "clock")
                    Label(transcription.language, systemImage: "globe")
                    Label(transcription.modelName, systemImage: "cpu")
                    if !transcription.speakers.isEmpty {
                        Label("\(transcription.speakers.count) speakers", systemImage: "person.2")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            // Audio player
            if let sourceURL = transcription.sourceURL {
                AudioPlayerView(viewModel: playerViewModel)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .onAppear {
                        playerViewModel.loadAudio(url: sourceURL)
                    }

                Divider()
            }

            // Segments
            if transcription.status == .completed {
                ScrollViewReader { proxy in
                    List {
                        ForEach(sortedSegments) { segment in
                            EditorView(
                                segment: segment,
                                isActive: isSegmentActive(segment),
                                onSeek: { time in
                                    playerViewModel.seek(to: time)
                                }
                            )
                            .id(segment.id)
                            .contextMenu {
                                segmentContextMenu(for: segment)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            } else if transcription.status == .transcribing || transcription.status == .diarizing {
                VStack(spacing: 12) {
                    ProgressView(value: transcription.progress)
                    Text(transcription.status == .transcribing ? "Transcribing..." : "Identifying speakers...")
                        .foregroundStyle(.secondary)
                    Text("\(Int(transcription.progress * 100))%")
                        .font(.title2)
                        .monospacedDigit()
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if transcription.status == .failed {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text(transcription.errorMessage ?? "Transcription failed")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Waiting...")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var sortedSegments: [Segment] {
        transcription.segments.sorted { $0.startTime < $1.startTime }
    }

    private func isSegmentActive(_ segment: Segment) -> Bool {
        playerViewModel.currentTime >= segment.startTime &&
        playerViewModel.currentTime < segment.endTime
    }

    @ViewBuilder
    private func segmentContextMenu(for segment: Segment) -> some View {
        if let index = sortedSegments.firstIndex(where: { $0.id == segment.id }) {
            if index < sortedSegments.count - 1 {
                Button("Merge with Next") {
                    mergeSegments(segment, with: sortedSegments[index + 1])
                }
            }
            Button("Split at Midpoint") {
                splitSegment(segment)
            }
        }
    }

    private func mergeSegments(_ first: Segment, with second: Segment) {
        first.text = first.text + " " + second.text
        first.endTime = second.endTime
        first.isEdited = true
        if let context = second.transcription?.modelContext {
            context.delete(second)
        }
    }

    private func splitSegment(_ segment: Segment) {
        let text = segment.text
        let midIndex = text.index(text.startIndex, offsetBy: text.count / 2)
        // Find nearest space to split cleanly
        let splitIndex = text[..<midIndex].lastIndex(of: " ") ?? midIndex

        let firstText = String(text[..<splitIndex])
        let secondText = String(text[splitIndex...]).trimmingCharacters(in: .whitespaces)

        // Interpolate timestamp linearly
        let ratio = Double(text.distance(from: text.startIndex, to: splitIndex)) / Double(text.count)
        let splitTime = segment.startTime + (segment.endTime - segment.startTime) * ratio

        // Update existing segment
        segment.text = firstText
        segment.endTime = splitTime
        segment.isEdited = true

        // Create new segment
        let newSegment = Segment(startTime: splitTime, endTime: segment.endTime, text: secondText)
        newSegment.speaker = segment.speaker
        newSegment.transcription = segment.transcription
        newSegment.isEdited = true
        if let context = segment.transcription?.modelContext {
            context.insert(newSegment)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
```

- [ ] **Step 3: Update ContentView to wire everything together**

Update `WhisprPro/App/ContentView.swift`:
```swift
import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: TranscriptionViewModel?
    @State private var playerViewModel = AudioPlayerViewModel()

    var body: some View {
        Group {
            if let viewModel {
                mainContent(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = TranscriptionViewModel(modelContext: modelContext)
            }
        }
    }

    @ViewBuilder
    private func mainContent(viewModel: TranscriptionViewModel) -> some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
                .frame(minWidth: 220)
        } detail: {
            if let transcription = viewModel.selectedTranscription {
                TranscriptView(
                    transcription: transcription,
                    playerViewModel: playerViewModel
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 48))
                        .foregroundStyle(.quaternary)
                    Text("Select or import a transcription")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .fileImporter(
            isPresented: Binding(
                get: { viewModel.showFileImporter },
                set: { viewModel.showFileImporter = $0 }
            ),
            allowedContentTypes: [.audio, .movie],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await viewModel.importFile(url: url) }
            }
        }
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add WhisprPro/Views/ WhisprPro/App/ContentView.swift
git commit -m "feat: add TranscriptView, EditorView, and wire up main NavigationSplitView"
```

---

## Chunk 4: Recording + Export + Settings

### Task 11: RecordingService

**Files:**
- Create: `WhisprPro/Services/RecordingService.swift`

- [ ] **Step 1: Write test for RecordingService**

Create `WhisprProTests/Services/RecordingServiceTests.swift`:
```swift
import Testing
import Foundation
@testable import WhisprPro

@Suite("RecordingService Tests")
struct RecordingServiceTests {
    @Test func recordingsDirectory() {
        let service = RecordingService()
        let dir = service.recordingsDirectory
        #expect(dir.path().contains("WhisprPro/Recordings"))
    }

    @Test func initialState() {
        let service = RecordingService()
        #expect(service.isRecording == false)
        #expect(service.elapsedTime == 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL

- [ ] **Step 3: Implement RecordingService**

Create `WhisprPro/Services/RecordingService.swift`:
```swift
import Foundation
import AVFoundation

@Observable
final class RecordingService {
    var isRecording = false
    var isPaused = false
    var elapsedTime: TimeInterval = 0
    var audioLevel: Float = 0

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var timer: Timer?
    private var tempFileURL: URL?

    let recordingsDirectory: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("WhisprPro/Recordings")
    }()

    func availableInputDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    func startRecording(deviceID: String? = nil) throws {
        let engine = AVAudioEngine()

        let inputNode = engine.inputNode
        let format = AVAudioFormat(
            standardFormatWithSampleRate: 16000,
            channels: 1
        )!

        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("\(UUID().uuidString).wav")
        tempFileURL = tempFile

        let audioFile = try AVAudioFile(
            forWriting: tempFile,
            settings: format.settings
        )
        self.audioFile = audioFile

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputNode.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            guard let self, !self.isPaused else { return }

            // Calculate audio level
            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            if let data = channelData {
                for i in 0..<frameLength {
                    sum += abs(data[i])
                }
            }
            self.audioLevel = sum / Float(frameLength)

            // Write to file (convert format if needed)
            do {
                try audioFile.write(from: buffer)
            } catch {
                print("Error writing audio: \(error)")
            }
        }

        try engine.start()
        self.audioEngine = engine
        isRecording = true
        isPaused = false
        elapsedTime = 0

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, !self.isPaused else { return }
            self.elapsedTime += 1.0
        }
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        isPaused = false
    }

    func stopRecording() throws -> URL {
        timer?.invalidate()
        timer = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil

        isRecording = false
        isPaused = false

        // Move to permanent storage
        guard let tempFile = tempFileURL else {
            throw RecordingError.noRecording
        }

        let fm = FileManager.default
        try fm.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "Recording_\(formatter.string(from: Date())).wav"
        let destination = recordingsDirectory.appendingPathComponent(filename)

        try fm.moveItem(at: tempFile, to: destination)
        tempFileURL = nil

        return destination
    }
}

enum RecordingError: Error, LocalizedError {
    case noRecording
    case deviceNotAvailable

    var errorDescription: String? {
        switch self {
        case .noRecording: "No recording in progress"
        case .deviceNotAvailable: "Audio input device not available"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add WhisprPro/Services/RecordingService.swift WhisprProTests/Services/RecordingServiceTests.swift
git commit -m "feat: add RecordingService with AVAudioEngine capture"
```

### Task 12: RecordingView

**Files:**
- Create: `WhisprPro/Views/RecordingView.swift`
- Create: `WhisprPro/ViewModels/RecordingViewModel.swift`

- [ ] **Step 1: Create RecordingViewModel**

Create `WhisprPro/ViewModels/RecordingViewModel.swift`:
```swift
import Foundation
import AVFoundation

@Observable
final class RecordingViewModel {
    let recordingService = RecordingService()
    var selectedDeviceID: String?
    var errorMessage: String?

    var availableDevices: [AVCaptureDevice] {
        recordingService.availableInputDevices()
    }

    func startRecording() {
        do {
            try recordingService.startRecording(deviceID: selectedDeviceID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopAndGetFile() -> URL? {
        do {
            return try recordingService.stopRecording()
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
```

- [ ] **Step 2: Create RecordingView**

Create `WhisprPro/Views/RecordingView.swift`:
```swift
import SwiftUI
import AVFoundation

struct RecordingView: View {
    @Bindable var viewModel: RecordingViewModel
    let onComplete: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Text("Recording")
                .font(.headline)

            // Record button
            Button(action: toggleRecording) {
                Circle()
                    .fill(viewModel.recordingService.isRecording ? .red : .red.opacity(0.8))
                    .frame(width: 80, height: 80)
                    .overlay {
                        if viewModel.recordingService.isRecording {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.white)
                                .frame(width: 28, height: 28)
                        } else {
                            Circle()
                                .fill(.white)
                                .frame(width: 28, height: 28)
                        }
                    }
            }
            .buttonStyle(.plain)

            // Timer
            Text(formatTime(viewModel.recordingService.elapsedTime))
                .font(.system(size: 32, weight: .light, design: .monospaced))

            // Audio level
            if viewModel.recordingService.isRecording {
                WaveformView(level: viewModel.recordingService.audioLevel)
                    .frame(height: 40)
            }

            // Device selector
            if !viewModel.availableDevices.isEmpty {
                Picker("Input:", selection: $viewModel.selectedDeviceID) {
                    Text("Default").tag(nil as String?)
                    ForEach(viewModel.availableDevices, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(device.uniqueID as String?)
                    }
                }
                .frame(width: 300)
            }

            // Actions
            HStack(spacing: 16) {
                Button("Cancel") {
                    if viewModel.recordingService.isRecording {
                        _ = viewModel.stopAndGetFile()
                    }
                    dismiss()
                }

                if viewModel.recordingService.isRecording {
                    Button(viewModel.recordingService.isPaused ? "Resume" : "Pause") {
                        if viewModel.recordingService.isPaused {
                            viewModel.recordingService.resume()
                        } else {
                            viewModel.recordingService.pause()
                        }
                    }

                    Button("Stop & Transcribe") {
                        if let url = viewModel.stopAndGetFile() {
                            onComplete(url)
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding(32)
        .frame(width: 400, height: 350)
    }

    private func toggleRecording() {
        if viewModel.recordingService.isRecording {
            if let url = viewModel.stopAndGetFile() {
                onComplete(url)
                dismiss()
            }
        } else {
            viewModel.startRecording()
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct WaveformView: View {
    let level: Float
    private let barCount = 20

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.red.opacity(0.7))
                    .frame(width: 3, height: barHeight(for: i))
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let normalized = CGFloat(min(level * 10, 1.0))
        let randomFactor = CGFloat.random(in: 0.3...1.0)
        return max(4, normalized * 36 * randomFactor)
    }
}
```

- [ ] **Step 3: Wire RecordingView into ContentView**

Update the `mainContent` function in `WhisprPro/App/ContentView.swift` to add:
```swift
.sheet(isPresented: Binding(
    get: { viewModel.showRecordingSheet },
    set: { viewModel.showRecordingSheet = $0 }
)) {
    RecordingView(viewModel: RecordingViewModel()) { recordedURL in
        Task { await viewModel.importFile(url: recordedURL) }
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add WhisprPro/Views/RecordingView.swift WhisprPro/ViewModels/RecordingViewModel.swift WhisprPro/App/ContentView.swift
git commit -m "feat: add RecordingView with waveform, timer, and device selection"
```

### Task 13: ExportService

**Files:**
- Create: `WhisprPro/Services/ExportService.swift`
- Create: `WhisprProTests/Services/ExportServiceTests.swift`

- [ ] **Step 1: Write tests for ExportService**

Create `WhisprProTests/Services/ExportServiceTests.swift`:
```swift
import Testing
import Foundation
@testable import WhisprPro

@Suite("ExportService Tests")
struct ExportServiceTests {
    private func makeSampleSegments() -> [(start: TimeInterval, end: TimeInterval, text: String, speaker: String?)] {
        [
            (0.0, 2.5, "Hello world", "Speaker 1"),
            (2.5, 5.0, "How are you", "Speaker 2"),
            (5.0, 8.0, "I am fine", "Speaker 1"),
        ]
    }

    @Test func exportSRT() {
        let segments = makeSampleSegments()
        let srt = ExportService.toSRT(segments: segments)

        #expect(srt.contains("1\n00:00:00,000 --> 00:00:02,500"))
        #expect(srt.contains("[Speaker 1] Hello world"))
        #expect(srt.contains("2\n00:00:02,500 --> 00:00:05,000"))
    }

    @Test func exportVTT() {
        let segments = makeSampleSegments()
        let vtt = ExportService.toVTT(segments: segments)

        #expect(vtt.hasPrefix("WEBVTT"))
        #expect(vtt.contains("00:00:00.000 --> 00:00:02.500"))
    }

    @Test func exportTXT() {
        let segments = makeSampleSegments()
        let txt = ExportService.toTXT(segments: segments, includeSpeakers: true, includeTimestamps: true)

        #expect(txt.contains("[00:00:00] Speaker 1: Hello world"))
    }

    @Test func exportJSON() throws {
        let segments = makeSampleSegments()
        let json = ExportService.toJSON(
            title: "Test",
            language: "en",
            segments: segments
        )
        #expect(json.contains("\"title\":\"Test\""))
        #expect(json.contains("\"text\":\"Hello world\""))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL

- [ ] **Step 3: Implement ExportService**

Create `WhisprPro/Services/ExportService.swift`:
```swift
import Foundation
import AppKit
import PDFKit

struct ExportService {
    typealias ExportSegment = (start: TimeInterval, end: TimeInterval, text: String, speaker: String?)

    static func toSRT(segments: [ExportSegment]) -> String {
        var output = ""
        for (index, seg) in segments.enumerated() {
            output += "\(index + 1)\n"
            output += "\(srtTimestamp(seg.start)) --> \(srtTimestamp(seg.end))\n"
            if let speaker = seg.speaker {
                output += "[\(speaker)] "
            }
            output += "\(seg.text)\n\n"
        }
        return output
    }

    static func toVTT(segments: [ExportSegment]) -> String {
        var output = "WEBVTT\n\n"
        for (index, seg) in segments.enumerated() {
            output += "\(index + 1)\n"
            output += "\(vttTimestamp(seg.start)) --> \(vttTimestamp(seg.end))\n"
            if let speaker = seg.speaker {
                output += "<v \(speaker)>"
            }
            output += "\(seg.text)\n\n"
        }
        return output
    }

    static func toTXT(
        segments: [ExportSegment],
        includeSpeakers: Bool = true,
        includeTimestamps: Bool = true
    ) -> String {
        segments.map { seg in
            var line = ""
            if includeTimestamps {
                line += "[\(simpleTimestamp(seg.start))] "
            }
            if includeSpeakers, let speaker = seg.speaker {
                line += "\(speaker): "
            }
            line += seg.text
            return line
        }.joined(separator: "\n")
    }

    static func toJSON(
        title: String,
        language: String,
        segments: [ExportSegment]
    ) -> String {
        struct JSONOutput: Encodable {
            let title: String
            let language: String
            let segments: [JSONSegment]
        }
        struct JSONSegment: Encodable {
            let start: Double
            let end: Double
            let text: String
            let speaker: String?
        }

        let output = JSONOutput(
            title: title,
            language: language,
            segments: segments.map {
                JSONSegment(start: $0.start, end: $0.end, text: $0.text, speaker: $0.speaker)
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(output) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func toPDF(
        title: String,
        language: String,
        duration: TimeInterval,
        segments: [ExportSegment]
    ) -> Data? {
        let text = NSMutableAttributedString()

        // Title
        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .bold),
            .paragraphStyle: {
                let p = NSMutableParagraphStyle()
                p.lineSpacing = 8
                return p
            }()
        ]
        text.append(NSAttributedString(string: "\(title)\n", attributes: titleAttr))

        // Metadata
        let metaAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let durationStr = "\(Int(duration) / 60):\(String(format: "%02d", Int(duration) % 60))"
        text.append(NSAttributedString(
            string: "Language: \(language) | Duration: \(durationStr)\n\n",
            attributes: metaAttr
        ))

        // Segments
        let bodyAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .paragraphStyle: {
                let p = NSMutableParagraphStyle()
                p.lineSpacing = 4
                p.paragraphSpacing = 8
                return p
            }()
        ]
        let speakerAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.controlAccentColor
        ]
        let timeAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]

        for seg in segments {
            text.append(NSAttributedString(string: simpleTimestamp(seg.start) + " ", attributes: timeAttr))
            if let speaker = seg.speaker {
                text.append(NSAttributedString(string: speaker + ": ", attributes: speakerAttr))
            }
            text.append(NSAttributedString(string: seg.text + "\n", attributes: bodyAttr))
        }

        // Generate PDF
        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: 595, height: 842) // A4
        printInfo.topMargin = 50
        printInfo.bottomMargin = 50
        printInfo.leftMargin = 50
        printInfo.rightMargin = 50

        let textView = NSTextView(
            frame: NSRect(
                x: 0, y: 0,
                width: printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin,
                height: printInfo.paperSize.height - printInfo.topMargin - printInfo.bottomMargin
            )
        )
        textView.textStorage?.setAttributedString(text)

        return textView.dataWithPDF(inside: textView.bounds)
    }

    // MARK: - Helpers

    private static func srtTimestamp(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        let millis = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, millis)
    }

    private static func vttTimestamp(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        let millis = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, millis)
    }

    private static func simpleTimestamp(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme WhisprPro -destination 'platform=macOS'`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add WhisprPro/Services/ExportService.swift WhisprProTests/Services/ExportServiceTests.swift
git commit -m "feat: add ExportService with SRT, VTT, TXT, JSON, PDF output"
```

### Task 14: Export UI Integration

**Files:**
- Modify: `WhisprPro/Views/TranscriptView.swift`

- [ ] **Step 1: Add export menu to TranscriptView header**

Add to header area in TranscriptView, after the metadata HStack:
```swift
HStack(spacing: 8) {
    Menu("Export") {
        Button("SRT (.srt)") { exportAs(.srt) }
        Button("VTT (.vtt)") { exportAs(.vtt) }
        Button("Text (.txt)") { exportAs(.txt) }
        Button("JSON (.json)") { exportAs(.json) }
        Button("PDF (.pdf)") { exportAs(.pdf) }
    }
    .fixedSize()

    ShareLink(
        item: transcription.title,
        preview: SharePreview(transcription.title)
    ) {
        Label("Share", systemImage: "square.and.arrow.up")
    }
}
```

Add supporting enum and method:
```swift
enum ExportFormat { case srt, vtt, txt, json, pdf }

private func exportAs(_ format: ExportFormat) {
    let segments: [ExportService.ExportSegment] = sortedSegments.map { seg in
        (seg.startTime, seg.endTime, seg.text, seg.speaker?.label)
    }

    let panel = NSSavePanel()
    switch format {
    case .srt: panel.allowedContentTypes = [.init(filenameExtension: "srt")!]
    case .vtt: panel.allowedContentTypes = [.init(filenameExtension: "vtt")!]
    case .txt: panel.allowedContentTypes = [.plainText]
    case .json: panel.allowedContentTypes = [.json]
    case .pdf: panel.allowedContentTypes = [.pdf]
    }
    panel.nameFieldStringValue = transcription.title

    guard panel.runModal() == .OK, let url = panel.url else { return }

    let content: String
    var data: Data?

    switch format {
    case .srt: content = ExportService.toSRT(segments: segments)
    case .vtt: content = ExportService.toVTT(segments: segments)
    case .txt: content = ExportService.toTXT(segments: segments)
    case .json: content = ExportService.toJSON(
        title: transcription.title,
        language: transcription.language,
        segments: segments
    )
    case .pdf:
        data = ExportService.toPDF(
            title: transcription.title,
            language: transcription.language,
            duration: transcription.duration,
            segments: segments
        )
        content = ""
    }

    do {
        if let data {
            try data.write(to: url)
        } else {
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
    } catch {
        print("Export failed: \(error)")
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add WhisprPro/Views/TranscriptView.swift
git commit -m "feat: add export menu to TranscriptView with save dialog"
```

### Task 15: Settings Window

**Files:**
- Modify: `WhisprPro/Views/SettingsView.swift`
- Create: `WhisprPro/Views/ModelManagerView.swift`
- Create: `WhisprPro/ViewModels/ModelManagerViewModel.swift`

- [ ] **Step 1: Create ModelManagerViewModel**

Create `WhisprPro/ViewModels/ModelManagerViewModel.swift`:
```swift
import Foundation
import SwiftData

@Observable
final class ModelManagerViewModel {
    var models: [MLModelInfo] = []
    private let modelManager = ModelManager()
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadModels()
    }

    func loadModels() {
        let descriptor = FetchDescriptor<MLModelInfo>()
        models = (try? modelContext.fetch(descriptor)) ?? []

        // Seed default models if empty
        if models.isEmpty {
            for def in ModelManager.availableWhisperModels {
                let model = MLModelInfo(name: def.name, kind: .whisper, size: def.size)
                model.isDownloaded = modelManager.isModelDownloaded(name: def.name, kind: .whisper)
                modelContext.insert(model)
            }
            try? modelContext.save()
            models = (try? modelContext.fetch(descriptor)) ?? []
        }
    }

    func downloadModel(_ model: MLModelInfo) async {
        guard let definition = ModelManager.availableWhisperModels.first(where: { $0.name == model.name }) else {
            return
        }

        do {
            let url = try await modelManager.downloadModel(definition: definition) { progress in
                Task { @MainActor in
                    model.downloadProgress = progress
                }
            }
            model.isDownloaded = true
            model.localURL = url
            model.downloadProgress = 1.0
            try? modelContext.save()
        } catch {
            print("Download failed: \(error)")
        }
    }

    func deleteModel(_ model: MLModelInfo) async {
        do {
            try await modelManager.deleteModel(name: model.name, kind: model.kind)
            model.isDownloaded = false
            model.localURL = nil
            try? modelContext.save()
        } catch {
            print("Delete failed: \(error)")
        }
    }
}
```

- [ ] **Step 2: Create ModelManagerView**

Create `WhisprPro/Views/ModelManagerView.swift`:
```swift
import SwiftUI

struct ModelManagerView: View {
    @Bindable var viewModel: ModelManagerViewModel

    var body: some View {
        List(viewModel.models) { model in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name)
                        .fontWeight(.semibold)
                    Text(formatSize(model.size))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if model.isDownloaded {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Delete", role: .destructive) {
                            Task { await viewModel.deleteModel(model) }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .font(.caption)
                    }
                } else if model.downloadProgress > 0 && model.downloadProgress < 1 {
                    ProgressView(value: model.downloadProgress)
                        .frame(width: 100)
                } else {
                    Button("Download") {
                        Task { await viewModel.downloadModel(model) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
```

- [ ] **Step 3: Update SettingsView**

Replace `WhisprPro/Views/SettingsView.swift`:
```swift
import SwiftUI
import SwiftData
import AVFoundation

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("defaultLanguage") private var defaultLanguage = "auto"
    @AppStorage("defaultModel") private var defaultModel = "tiny"
    @AppStorage("defaultExportFormat") private var defaultExportFormat = "srt"
    @AppStorage("exportIncludeTimestamps") private var includeTimestamps = true
    @AppStorage("exportIncludeSpeakers") private var includeSpeakers = true
    @AppStorage("defaultAudioInput") private var defaultAudioInput = ""

    var body: some View {
        TabView {
            modelsTab
                .tabItem { Label("Models", systemImage: "cpu") }

            generalTab
                .tabItem { Label("General", systemImage: "gear") }

            exportTab
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }
        }
        .frame(width: 500, height: 350)
    }

    private var modelsTab: some View {
        ModelManagerView(
            viewModel: ModelManagerViewModel(modelContext: modelContext)
        )
    }

    private var generalTab: some View {
        Form {
            Picker("Default Language", selection: $defaultLanguage) {
                Text("Auto-detect").tag("auto")
                Text("English").tag("en")
                Text("Italian").tag("it")
                Text("Spanish").tag("es")
                Text("French").tag("fr")
                Text("German").tag("de")
                Text("Portuguese").tag("pt")
                Text("Japanese").tag("ja")
                Text("Chinese").tag("zh")
                Text("Korean").tag("ko")
                Text("Russian").tag("ru")
                Text("Arabic").tag("ar")
                Text("Hindi").tag("hi")
                Text("Dutch").tag("nl")
                Text("Polish").tag("pl")
                Text("Turkish").tag("tr")
                Text("Swedish").tag("sv")
                Text("Ukrainian").tag("uk")
            }

            Picker("Default Model", selection: $defaultModel) {
                Text("tiny").tag("tiny")
                Text("base").tag("base")
                Text("small").tag("small")
                Text("medium").tag("medium")
                Text("large-v3").tag("large-v3")
                Text("large-v3-turbo").tag("large-v3-turbo")
            }

            Picker("Audio Input", selection: $defaultAudioInput) {
                Text("System Default").tag("")
                ForEach(availableInputDevices, id: \.uniqueID) { device in
                    Text(device.localizedName).tag(device.uniqueID)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var availableInputDevices: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    private var exportTab: some View {
        Form {
            Picker("Default Format", selection: $defaultExportFormat) {
                Text("SRT").tag("srt")
                Text("VTT").tag("vtt")
                Text("Text").tag("txt")
                Text("JSON").tag("json")
                Text("PDF").tag("pdf")
            }
            Toggle("Include timestamps", isOn: $includeTimestamps)
            Toggle("Include speaker labels", isOn: $includeSpeakers)
        }
        .formStyle(.grouped)
        .padding()
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add WhisprPro/Views/SettingsView.swift WhisprPro/Views/ModelManagerView.swift WhisprPro/ViewModels/ModelManagerViewModel.swift
git commit -m "feat: add Settings window with model manager, language, and export preferences"
```

---

## Chunk 5: Diarization + Final Integration

### Task 16: DiarizationService

**Files:**
- Create: `WhisprPro/Services/DiarizationService.swift`
- Create: `WhisprProTests/Services/DiarizationServiceTests.swift`

- [ ] **Step 1: Write test for DiarizationService helpers**

Create `WhisprProTests/Services/DiarizationServiceTests.swift`:
```swift
import Testing
import Foundation
@testable import WhisprPro

@Suite("DiarizationService Tests")
struct DiarizationServiceTests {
    @Test func assignSpeakersToSegments() {
        let speakerTimeline: [(start: TimeInterval, end: TimeInterval, speakerIndex: Int)] = [
            (0.0, 3.0, 0),
            (3.0, 6.0, 1),
            (6.0, 9.0, 0),
        ]

        let segments = [
            (start: 0.5, end: 2.5),
            (start: 3.5, end: 5.5),
            (start: 6.5, end: 8.5),
        ]

        let assignments = DiarizationService.assignSpeakers(
            speakerTimeline: speakerTimeline,
            segments: segments
        )

        #expect(assignments.count == 3)
        #expect(assignments[0] == 0)
        #expect(assignments[1] == 1)
        #expect(assignments[2] == 0)
    }

    @Test func speakerColors() {
        let colors = DiarizationService.speakerColors
        #expect(colors.count >= 6)
        #expect(colors[0].hasPrefix("#"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL

- [ ] **Step 3: Implement DiarizationService**

Create `WhisprPro/Services/DiarizationService.swift`:
```swift
import Foundation
import CoreML
import Accelerate

actor DiarizationService {
    static let speakerColors = [
        "#007AFF", "#FF9500", "#34C759", "#FF3B30",
        "#AF52DE", "#FF2D55", "#5AC8FA", "#FFCC00",
    ]

    /// Assign speaker indices to transcript segments based on a speaker timeline
    static func assignSpeakers(
        speakerTimeline: [(start: TimeInterval, end: TimeInterval, speakerIndex: Int)],
        segments: [(start: TimeInterval, end: TimeInterval)]
    ) -> [Int] {
        segments.map { seg in
            // Find the speaker timeline entry with maximum overlap
            var bestSpeaker = 0
            var bestOverlap: TimeInterval = 0

            for entry in speakerTimeline {
                let overlapStart = max(seg.start, entry.start)
                let overlapEnd = min(seg.end, entry.end)
                let overlap = max(0, overlapEnd - overlapStart)

                if overlap > bestOverlap {
                    bestOverlap = overlap
                    bestSpeaker = entry.speakerIndex
                }
            }

            return bestSpeaker
        }
    }

    /// Perform agglomerative clustering on embedding vectors
    static func agglomerativeClustering(
        embeddings: [[Float]],
        threshold: Float = 0.5
    ) -> [Int] {
        let n = embeddings.count
        guard n > 0 else { return [] }
        if n == 1 { return [0] }

        // Compute cosine distance matrix
        var distances = [[Float]](repeating: [Float](repeating: 0, count: n), count: n)
        for i in 0..<n {
            for j in (i+1)..<n {
                let dist = cosineDistance(embeddings[i], embeddings[j])
                distances[i][j] = dist
                distances[j][i] = dist
            }
        }

        // Each point starts as its own cluster
        var clusterAssignment = Array(0..<n)
        var nextClusterID = n

        // Merge until no pair is below threshold
        while true {
            var minDist: Float = Float.infinity
            var mergeA = -1
            var mergeB = -1

            let activeClusters = Set(clusterAssignment)
            let clusterList = Array(activeClusters).sorted()

            for i in 0..<clusterList.count {
                for j in (i+1)..<clusterList.count {
                    let cA = clusterList[i]
                    let cB = clusterList[j]
                    let dist = averageLinkageDistance(
                        clusterA: cA, clusterB: cB,
                        assignments: clusterAssignment,
                        distances: distances
                    )
                    if dist < minDist {
                        minDist = dist
                        mergeA = cA
                        mergeB = cB
                    }
                }
            }

            if minDist > threshold || mergeA == -1 { break }

            // Merge clusterB into clusterA
            for i in 0..<n {
                if clusterAssignment[i] == mergeB {
                    clusterAssignment[i] = mergeA
                }
            }
        }

        // Renumber clusters to 0, 1, 2, ...
        let unique = Array(Set(clusterAssignment)).sorted()
        let mapping = Dictionary(uniqueKeysWithValues: unique.enumerated().map { ($1, $0) })
        return clusterAssignment.map { mapping[$0]! }
    }

    private static func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        vDSP_dotpr(a, 1, a, 1, &normA, vDSP_Length(a.count))
        vDSP_dotpr(b, 1, b, 1, &normB, vDSP_Length(b.count))

        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return 1.0 }
        return 1.0 - (dotProduct / denom)
    }

    private static func averageLinkageDistance(
        clusterA: Int, clusterB: Int,
        assignments: [Int], distances: [[Float]]
    ) -> Float {
        var sum: Float = 0
        var count: Float = 0

        for i in 0..<assignments.count {
            guard assignments[i] == clusterA else { continue }
            for j in 0..<assignments.count {
                guard assignments[j] == clusterB else { continue }
                sum += distances[i][j]
                count += 1
            }
        }

        return count > 0 ? sum / count : Float.infinity
    }

    /// Run diarization on a transcription.
    /// Pipeline: load audio → split into windows → extract embeddings via Core ML → cluster → assign speakers.
    func diarize(
        audioURL: URL,
        segments: [Segment],
        modelURL: URL
    ) async throws -> [(speakerIndex: Int, segmentID: UUID)] {
        // Step 1: Load Core ML model
        let config = MLModelConfiguration()
        config.computeUnits = .all

        guard let model = try? MLModel(contentsOf: modelURL, configuration: config) else {
            throw DiarizationError.modelLoadFailed
        }

        // Step 2: Load audio as float array
        let audioData = try loadAudioAsFloats(url: audioURL)

        // Step 3: Split into overlapping windows and extract embeddings
        let windowSize = 16000 * 3  // 3-second windows at 16kHz
        let hopSize = 16000 * 1     // 1-second hop
        var windowEmbeddings: [(midTime: TimeInterval, embedding: [Float])] = []

        var offset = 0
        while offset + windowSize <= audioData.count {
            let window = Array(audioData[offset..<(offset + windowSize)])
            let midTime = Double(offset + windowSize / 2) / 16000.0

            // Create MLMultiArray input for Core ML model
            let inputArray = try MLMultiArray(shape: [1, NSNumber(value: windowSize)], dataType: .float32)
            for i in 0..<windowSize {
                inputArray[i] = NSNumber(value: window[i])
            }

            let inputFeatures = try MLDictionaryFeatureProvider(
                dictionary: ["audio": MLFeatureValue(multiArray: inputArray)]
            )
            let prediction = try model.prediction(from: inputFeatures)

            // Extract embedding vector from model output
            guard let embeddingValue = prediction.featureValue(for: "embedding"),
                  let embeddingArray = embeddingValue.multiArrayValue else {
                throw DiarizationError.processingFailed("Model output missing embedding")
            }

            var embedding = [Float](repeating: 0, count: embeddingArray.count)
            for i in 0..<embeddingArray.count {
                embedding[i] = embeddingArray[i].floatValue
            }

            windowEmbeddings.append((midTime: midTime, embedding: embedding))
            offset += hopSize
        }

        guard !windowEmbeddings.isEmpty else {
            throw DiarizationError.processingFailed("No audio windows to process")
        }

        // Step 4: Cluster embeddings
        let embeddings = windowEmbeddings.map(\.embedding)
        let clusterLabels = Self.agglomerativeClustering(embeddings: embeddings, threshold: 0.5)

        // Step 5: Build speaker timeline from clustered windows
        var speakerTimeline: [(start: TimeInterval, end: TimeInterval, speakerIndex: Int)] = []
        for (i, windowEmb) in windowEmbeddings.enumerated() {
            let start = max(0, windowEmb.midTime - 1.5)  // half window before midpoint
            let end = windowEmb.midTime + 1.5              // half window after midpoint
            speakerTimeline.append((start: start, end: end, speakerIndex: clusterLabels[i]))
        }

        // Step 6: Assign speakers to transcript segments
        let segmentRanges = segments.map { (start: $0.startTime, end: $0.endTime) }
        let assignments = Self.assignSpeakers(
            speakerTimeline: speakerTimeline,
            segments: segmentRanges
        )

        return zip(assignments, segments).map { (speakerIndex, segment) in
            (speakerIndex: speakerIndex, segmentID: segment.id)
        }
    }

    /// Load a WAV file as an array of Float samples
    private func loadAudioAsFloats(url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        guard data.count > 44 else {
            throw DiarizationError.processingFailed("Audio file too small")
        }
        // Skip 44-byte WAV header (standard PCM format from AudioConverter)
        let pcmData = data.dropFirst(44)
        let sampleCount = pcmData.count / 2  // 16-bit samples
        var floats = [Float](repeating: 0, count: sampleCount)

        pcmData.withUnsafeBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                floats[i] = Float(int16Buffer[i]) / 32768.0
            }
        }

        return floats
    }
}

enum DiarizationError: Error, LocalizedError {
    case modelLoadFailed
    case modelNotAvailable
    case processingFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed: "Failed to load diarization model"
        case .modelNotAvailable: "Diarization model not available"
        case .processingFailed(let msg): "Diarization failed: \(msg)"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme WhisprPro -destination 'platform=macOS'`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add WhisprPro/Services/DiarizationService.swift WhisprProTests/Services/DiarizationServiceTests.swift
git commit -m "feat: add DiarizationService with agglomerative clustering and speaker assignment"
```

### Task 17: Drag & Drop Support

**Files:**
- Modify: `WhisprPro/App/ContentView.swift`

- [ ] **Step 1: Add onDrop modifier to ContentView**

Add to the NavigationSplitView in ContentView:
```swift
.onDrop(of: [.fileURL], isTargeted: nil) { providers in
    guard let provider = providers.first else { return false }
    _ = provider.loadObject(ofClass: URL.self) { url, _ in
        guard let url, AudioConverter.isSupported(url) else { return }
        Task { @MainActor in
            await viewModel?.importFile(url: url)
        }
    }
    return true
}
```

- [ ] **Step 2: Commit**

```bash
git add WhisprPro/App/ContentView.swift
git commit -m "feat: add drag & drop file import support"
```

### Task 18: Final Build Verification

- [ ] **Step 1: Build the project**

Run: `xcodebuild build -scheme WhisprPro -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Run all tests**

Run: `xcodebuild test -scheme WhisprPro -destination 'platform=macOS'`
Expected: All tests pass

- [ ] **Step 3: Final commit**

```bash
git add WhisprPro/ WhisprProTests/ Packages/
git commit -m "chore: final build verification and cleanup"
```
