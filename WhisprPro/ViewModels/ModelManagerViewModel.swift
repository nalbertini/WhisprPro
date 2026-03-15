import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.whisprpro", category: "ModelManager")

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
            // Seed whisper models
            for def in ModelManager.availableWhisperModels {
                let model = MLModelInfo(name: def.name, kind: .whisper, size: def.size)
                model.isDownloaded = modelManager.isModelDownloaded(name: def.name, kind: .whisper)
                modelContext.insert(model)
            }
            // Seed diarization model
            let diarizationDef = ModelManager.diarizationModel
            let diaModel = MLModelInfo(name: diarizationDef.name, kind: .diarization, size: diarizationDef.size)
            diaModel.isDownloaded = modelManager.isModelDownloaded(name: diarizationDef.name, kind: .diarization)
            modelContext.insert(diaModel)

            do { try modelContext.save() } catch { logger.error("Failed to save context: \(error)") }
            models = (try? modelContext.fetch(descriptor)) ?? []
        }

        // Ensure diarization model entry exists even if whisper models were already seeded
        if !models.contains(where: { $0.kind == .diarization }) {
            let diarizationDef = ModelManager.diarizationModel
            let diaModel = MLModelInfo(name: diarizationDef.name, kind: .diarization, size: diarizationDef.size)
            diaModel.isDownloaded = modelManager.isModelDownloaded(name: diarizationDef.name, kind: .diarization)
            modelContext.insert(diaModel)
            do { try modelContext.save() } catch { logger.error("Failed to save context: \(error)") }
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
        let definition: WhisperModelDefinition?
        if model.kind == .whisper {
            definition = ModelManager.availableWhisperModels.first(where: { $0.name == model.name })
        } else {
            definition = model.name == ModelManager.diarizationModel.name ? ModelManager.diarizationModel : nil
        }

        guard let definition else {
            logger.error("No definition found for model: \(model.name)")
            return
        }

        downloadProgress[model.name] = 0.01

        do {
            let url = try await modelManager.downloadModel(definition: definition, kind: model.kind) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.downloadProgress[definition.name] = progress
                }
            }
            await MainActor.run {
                model.isDownloaded = true
                model.localURL = url
                downloadProgress[model.name] = 0
                do {
                    try modelContext.save()
                } catch {
                    logger.error("Failed to save context: \(error)")
                }
            }
        } catch {
            logger.error("Download failed: \(error)")
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
            do {
                try modelContext.save()
            } catch {
                logger.error("Failed to save context: \(error)")
            }
        } catch {
            logger.error("Delete failed: \(error)")
        }
    }
}
