# WhisprPro

Native macOS transcription app powered by [whisper.cpp](https://github.com/ggerganov/whisper.cpp). Open source alternative to MacWhisper.

Everything runs locally on your Mac — no cloud, no API keys, no costs.

## Features

- **File transcription** — import MP3, WAV, M4A, MP4, MOV, AAC, FLAC, OGG
- **Live recording** — record from any microphone and transcribe
- **Whisper models** — choose from tiny (75 MB) to large-v3 (2.9 GB)
- **Multilingual** — supports all languages Whisper supports, with English translation
- **Speaker diarization** — identify who's speaking (via Core ML)
- **Integrated editor** — edit transcriptions synced to audio playback
- **Export** — SRT, VTT, TXT, JSON, PDF
- **Drag & drop** — drop audio files directly onto the window

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16+
- Apple Silicon recommended (Intel supported but slower)

## Setup

```bash
# Clone
git clone https://github.com/nalbertini/WhisprPro.git
cd WhisprPro

# Build whisper.cpp
cd Packages/WhisperCpp
git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git vendor-whisper
cd vendor-whisper
cmake -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DGGML_METAL=ON
cmake --build build --config Release -j$(sysctl -n hw.ncpu)
cd ..

# Create xcframework
mkdir -p lib include
libtool -static -o lib/libwhisper-all.a \
  vendor-whisper/build/src/libwhisper.a \
  vendor-whisper/build/ggml/src/libggml.a \
  vendor-whisper/build/ggml/src/libggml-base.a \
  vendor-whisper/build/ggml/src/libggml-cpu.a \
  vendor-whisper/build/ggml/src/ggml-metal/libggml-metal.a \
  vendor-whisper/build/ggml/src/ggml-blas/libggml-blas.a
cp vendor-whisper/include/whisper.h include/
cp vendor-whisper/ggml/include/ggml*.h vendor-whisper/ggml/include/gguf.h include/
xcodebuild -create-xcframework -library lib/libwhisper-all.a -headers include -output libwhisper.xcframework
cd ../..

# Generate Xcode project
brew install xcodegen  # if not installed
xcodegen generate

# Open and build
open WhisprPro.xcodeproj
```

## Usage

1. **Download a model** — go to WhisprPro > Settings > Models and download at least "tiny"
2. **Import audio** — click "Import File" or drag a file onto the window
3. **Record** — click "Record" to capture from your microphone
4. **Edit** — click any segment to edit text, click speaker labels to rename
5. **Export** — use the Export menu to save as SRT, VTT, TXT, JSON, or PDF

## Architecture

```
WhisprPro/
├── App/           Entry point, main window
├── Models/        SwiftData models (Transcription, Segment, Speaker)
├── Views/         SwiftUI views
├── ViewModels/    MVVM view models
├── Services/      Business logic (transcription, recording, export, diarization)
├── Bridge/        Swift ↔ whisper.cpp interface
Packages/
└── WhisperCpp/    Local SPM package wrapping whisper.cpp
```

**Four-layer architecture:**
- **UI** — SwiftUI + MVVM with `@Observable`
- **Services** — TranscriptionService (actor), RecordingService, ExportService, DiarizationService
- **Engine** — WhisperBridge (C bridge to whisper.cpp via xcframework)
- **Data** — SwiftData persistence, ModelManager for model downloads

## Models

| Model | Size | Quality | Speed |
|-------|------|---------|-------|
| tiny | 75 MB | Basic | Fastest |
| base | 142 MB | Good | Fast |
| small | 466 MB | Better | Moderate |
| medium | 1.5 GB | High | Slower |
| large-v3 | 2.9 GB | Best | Slowest |
| large-v3-turbo | 1.6 GB | Near-best | Fast |

Models are downloaded from Hugging Face and stored in `~/Library/Application Support/WhisprPro/Models/`.

## License

MIT
