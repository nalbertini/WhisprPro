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
            print("[ModelManager] No definition found for model: \(model.name)")
            return
        }

        print("[ModelManager] Starting download of \(definition.name) from \(definition.downloadURL)")
        model.downloadProgress = 0.01 // Show progress bar immediately

        do {
            let url = try await modelManager.downloadModel(definition: definition) { progress in
                Task { @MainActor in
                    model.downloadProgress = progress
                    print("[ModelManager] Download progress: \(Int(progress * 100))%")
                }
            }
            await MainActor.run {
                model.isDownloaded = true
                model.localURL = url
                model.downloadProgress = 1.0
                try? modelContext.save()
            }
            print("[ModelManager] Download complete: \(url)")
        } catch {
            print("[ModelManager] Download failed: \(error)")
            await MainActor.run {
                model.downloadProgress = 0
            }
        }
    }

    func deleteModel(_ model: MLModelInfo) {
        do {
            try modelManager.deleteModel(name: model.name, kind: model.kind)
            model.isDownloaded = false
            model.localURL = nil
            try? modelContext.save()
        } catch {
            print("[ModelManager] Delete failed: \(error)")
        }
    }
}
