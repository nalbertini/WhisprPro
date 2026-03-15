# WhisprPro — Design Spec

**Date:** 2026-03-15
**Status:** Draft
**Type:** Native macOS app (Swift/SwiftUI)
**License:** Open Source

## Overview

WhisprPro is a native macOS application for audio/video transcription powered by whisper.cpp running locally. It provides file import, live recording, multi-format export, multilingual support with translation, an integrated transcript editor synced to audio playback, and speaker diarization via a Core ML model.

## Goals

- Transcribe audio/video files locally using Whisper models (tiny through large-v3-turbo)
- Record audio directly in the app and transcribe it
- Identify speakers via a dedicated diarization model (pyannote → Core ML)
- Provide an integrated editor for correcting transcriptions with audio sync
- Export to SRT, VTT, TXT, JSON, PDF
- Support all languages Whisper supports, with English translation option
- Zero cloud dependency — everything runs on-device
- Open source, community-friendly

## Architecture

Four-layer architecture:

### UI Layer (SwiftUI)
- Views and ViewModels
- MVVM pattern with `@Observable` ViewModels
- `NavigationSplitView` for sidebar + content layout

### Service Layer (Swift)
- **TranscriptionService** — orchestrates transcription jobs, manages queue, emits progress updates via `AsyncStream`
- **RecordingService** — captures audio via `AVAudioEngine`, produces WAV files (16kHz, mono)
- **ExportService** — generates output in SRT, VTT, TXT, JSON, PDF using template pattern
- **DiarizationService** — runs Core ML speaker detection model, maps speaker segments to Whisper timestamps

### Engine Layer (C Bridge + Core ML)
- **WhisperBridge** — Swift wrapper around whisper.cpp via C bridge. Handles model loading, transcription with progress callbacks, cancellation, and memory management. Packaged as a local SPM package (`WhisperCpp/`)
- Diarization uses Core ML directly (no C bridge needed) — the `DiarizationService` loads the `.mlmodel` via Apple's CoreML framework

### Data Layer (Swift)
- **SwiftData** for persistence
- **ModelManager** — downloads, caches, and manages Whisper model files in Application Support directory

## Data Model

### Transcription
| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| title | String | Display name (derived from filename or "Recording \(date)") |
| sourceURL | URL? | Path to original audio/video file |
| language | String | Detected or user-selected language code |
| modelName | String | Whisper model used (e.g. "large-v3") |
| duration | TimeInterval | Audio duration in seconds |
| createdAt | Date | Creation timestamp |
| status | Status | .pending / .transcribing / .diarizing / .completed / .failed |
| progress | Double | 0.0–1.0 progress indicator |
| errorMessage | String? | Error description if status == .failed |
| diarizationError | String? | Error description if diarization failed (transcription still completed) |
| segments | [Segment] | Relationship — ordered transcript segments |
| speakers | [Speaker] | Relationship — identified speakers |

### Segment
| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| startTime | TimeInterval | Segment start in seconds |
| endTime | TimeInterval | Segment end in seconds |
| text | String | Transcribed text (editable) |
| isEdited | Bool | Whether the user has manually edited this segment |
| transcription | Transcription | Inverse relationship |
| speaker | Speaker? | Assigned speaker (nil if diarization not run) |

### Speaker
| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| label | String | Display name ("Speaker 1" or user-assigned name) |
| color | String | Hex color for UI differentiation |
| transcription | Transcription | Inverse relationship |
| segments | [Segment] | Segments attributed to this speaker |

### MLModel
| Field | Type | Description |
|-------|------|-------------|
| name | String | Model identifier (e.g. "tiny", "large-v3", "diarization-pyannote") |
| kind | ModelKind | .whisper / .diarization |
| size | Int64 | File size in bytes |
| isDownloaded | Bool | Whether model file exists locally |
| localURL | URL? | Path to downloaded model file |
| downloadProgress | Double | 0.0–1.0 during download |

`ModelManager` handles both Whisper and diarization models. Whisper models stored in `~/Library/Application Support/WhisprPro/Models/whisper/`, diarization model in `~/Library/Application Support/WhisprPro/Models/diarization/`.

## User Interface

### Main Window — NavigationSplitView

**Sidebar (220pt):**
- List of transcriptions, sorted by date (newest first)
- Each row shows: title, status indicator (completed/in-progress with %), duration
- In-progress items show progress percentage
- Bottom section: "Import file" and "Record" action buttons
- Search field at top for filtering

**Content area:**
- **Header:** Title, metadata (duration, language, model, speaker count), Export and Share buttons
- **Audio player:** Play/pause, seekable progress bar, current time / total time, playback speed control (0.5x–2x)
- **Transcript editor:** Scrollable list of segments. Each segment shows:
  - Speaker label (colored) + timestamp
  - Editable text field
  - Currently playing segment highlighted
  - Click segment → seek audio to that timestamp
  - Click timestamp → seek to that time

### Recording Sheet (modal)
- Large red record button (toggles to stop)
- Timer display (MM:SS)
- Audio source selector (available input devices)
- Live waveform visualization
- Pause / "Stop and Transcribe" buttons
- On stop: dismisses sheet, creates new Transcription with .pending status

### Settings Window
- **Models tab:** List all available Whisper models with name, size, status (Downloaded/Download button), delete option. Download shows progress bar.
- **General tab:** Default language, default model, audio input device preference
- **Export tab:** Default export format, include timestamps toggle, include speaker labels toggle

## Key Flows

### Flow 1: File Import → Transcription
1. User drags file onto window or uses file picker (supported: mp3, wav, m4a, mp4, mov, aac, flac, ogg)
2. App creates `Transcription` record with `.pending` status
3. Audio is converted to WAV 16kHz mono via AVFoundation if needed. If conversion fails (corrupt file, unsupported codec), status is set to `.failed` with descriptive `errorMessage`
4. `TranscriptionService` loads selected Whisper model via `WhisperBridge`
5. whisper.cpp processes audio with progress callback updating `Transcription.progress`
6. On completion: segments are created from whisper output
7. If diarization enabled: `DiarizationService` runs Core ML model, creates `Speaker` records, assigns speakers to segments
8. Status set to `.completed`, transcript displayed in editor

### Flow 2: Live Recording → Transcription
1. User clicks "Record", recording sheet appears
2. `RecordingService` starts `AVAudioEngine` capture from selected input device
3. Audio buffer written to temporary WAV file, waveform data sent to UI
4. User clicks "Stop and Transcribe"
5. Recording stops, WAV file finalized and moved to `~/Library/Application Support/WhisprPro/Recordings/` for permanent storage
6. Proceeds to Flow 1 step 2 with the recorded file

### Flow 3: Export
1. User clicks "Export" dropdown, selects format
2. `ExportService` generates output:
   - **SRT/VTT:** Segments with sequential numbering, timestamps, speaker labels as prefix
   - **TXT:** Plain text with optional speaker labels and timestamps
   - **JSON:** Structured output with all metadata, segments, speakers
   - **PDF:** Formatted document with title, metadata, speaker-labeled transcript
3. Save dialog presented, file written

### Flow 4: Edit Transcript
1. User clicks on segment text in the editor
2. Text becomes editable (inline editing)
3. On commit: `Segment.text` updated, `isEdited` set to true
4. User can rename speakers by clicking speaker labels
5. User can merge/split segments via context menu:
   - **Merge:** Select two adjacent segments → combines text, takes earliest startTime and latest endTime. If speakers differ, keeps the speaker of the first segment.
   - **Split:** Cursor position in text determines the split point. Text is divided at cursor. Timestamps are interpolated linearly based on character position within the segment. Both new segments inherit the original speaker.
6. All edits persisted immediately via SwiftData

## Technical Decisions

### whisper.cpp Integration
- Included as a local SPM package with C sources
- Bridge exposes: `loadModel(path:)`, `transcribe(audioPath:language:translate:progress:) -> [WhisperSegment]`, `cancel()`
- Runs on a background thread, progress reported via callback
- Model files stored in `~/Library/Application Support/WhisprPro/Models/`
- Models downloaded from Hugging Face (ggml format)

### Speaker Diarization
- pyannote segmentation model converted to Core ML format (.mlmodel)
- Shipped as a separate downloadable model (not bundled with app), managed via `ModelManager` alongside Whisper models, stored in `~/Library/Application Support/WhisprPro/Models/diarization/`
- Pipeline: pyannote model performs voice activity detection and outputs speaker embedding segments → agglomerative clustering (auto-detect number of speakers, no user input required) → assign speaker labels to Whisper segments by timestamp overlap
- Clustering implemented in Swift using Accelerate framework for distance matrix computation
- Fallback: if diarization model not available, feature is disabled gracefully (transcription completes without speaker labels)
- If diarization fails after transcription succeeds: status is set to `.completed` (not `.failed`), an optional `diarizationError` message is stored, and the transcript is shown without speaker labels. The user can retry diarization later.

### Audio Processing
- AVFoundation for format conversion and metadata extraction
- AVAudioEngine for live recording
- Target format: WAV, 16kHz, mono, 16-bit PCM (whisper.cpp requirement)
- Supported input formats: mp3, wav, m4a, mp4, mov, aac, flac, ogg

### Concurrency
- Swift structured concurrency (async/await, actors)
- `TranscriptionService` as an actor to serialize transcription jobs (one at a time; additional imports are queued with `.pending` status)
- Progress updates via `AsyncStream<Double>`
- UI updates on `@MainActor`

### macOS Requirements
- Minimum: macOS 14 (Sonoma) — for SwiftData and latest SwiftUI features
- Recommended: Apple Silicon for optimal whisper.cpp performance
- Intel Macs supported but slower

## Project Structure

```
WhisprPro/
├── App/
│   ├── WhisprProApp.swift
│   └── ContentView.swift
├── Models/
│   ├── Transcription.swift
│   ├── Segment.swift
│   ├── Speaker.swift
│   └── WhisperModel.swift
├── Views/
│   ├── SidebarView.swift
│   ├── TranscriptView.swift
│   ├── EditorView.swift
│   ├── RecordingView.swift
│   ├── SettingsView.swift
│   ├── AudioPlayerView.swift
│   └── ModelManagerView.swift
├── ViewModels/
│   ├── TranscriptionViewModel.swift
│   ├── RecordingViewModel.swift
│   └── ModelManagerViewModel.swift
├── Services/
│   ├── TranscriptionService.swift
│   ├── RecordingService.swift
│   ├── ExportService.swift
│   ├── DiarizationService.swift
│   └── ModelManager.swift
├── Bridge/
│   └── WhisperBridge.swift      (Swift interface to WhisperCpp SPM package)
├── Resources/
│   └── Assets.xcassets
├── Packages/
│   └── WhisperCpp/        (local SPM package: C sources, whisper_wrapper.c/h, bridging header)
└── WhisprPro.xcodeproj
```

## Out of Scope (v1)

- Cloud/API-based transcription
- Real-time streaming transcription (transcribe while recording)
- Batch processing (multiple files at once)
- Custom vocabulary / prompt engineering
- Integration with third-party apps (Shortcuts, AppleScript)
- Automatic updates
