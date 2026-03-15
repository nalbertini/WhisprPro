import Foundation
import SwiftData

@Observable
final class ModelManagerViewModel {
    var models: [MLModelInfo] = []
    var downloadProgress: [String: Double] = [:]
    private let modelManager = ModelManager()
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadModels()
    }

    func loadModels() {
        let descriptor = FetchDescriptor<MLModelInfo>()
        models = (try? modelContext.fetch(descriptor)) ?? []

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

    func isDownloading(_ model: MLModelInfo) -> Bool {
        (downloadProgress[model.name] ?? 0) > 0 && !model.isDownloaded
    }

    func progress(for model: MLModelInfo) -> Double {
        downloadProgress[model.name] ?? 0
    }

    func downloadModel(_ model: MLModelInfo) async {
        guard let definition = ModelManager.availableWhisperModels.first(where: { $0.name == model.name }) else {
            return
        }

        downloadProgress[model.name] = 0.01

        do {
            let url = try await modelManager.downloadModel(definition: definition) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.downloadProgress[definition.name] = progress
                }
            }
            await MainActor.run {
                model.isDownloaded = true
                model.localURL = url
                downloadProgress[model.name] = 0
                try? modelContext.save()
            }
        } catch {
            print("[ModelManager] Download failed: \(error)")
            await MainActor.run {
                downloadProgress[model.name] = 0
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
