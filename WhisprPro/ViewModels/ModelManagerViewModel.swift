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
