import Foundation
import CoreML

// No placeholder model is shipped. Both model and an explicit local approval are required.
final class LocalDetector {
    private var model: MLModel?
    private(set) var status = "Lernmodus: kein trainiertes Modell"
    init() {
        reload()
    }
    func reload() {
        let local = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SetEnd.mlmodelc")
        let candidate = local.deletingLastPathComponent().appendingPathComponent("SetEnd-next.mlmodelc")
        let hasCandidate = FileManager.default.fileExists(atPath: candidate.path)
        let source = hasCandidate ? candidate : local
        guard FileManager.default.fileExists(atPath: source.path) else {
            model = nil; status = "Lernmodus: kein trainiertes Modell"; return
        }
        do {
            let config = MLModelConfiguration(); config.computeUnits = .cpuOnly
            let loaded = try MLModel(contentsOf: source, configuration: config)
            let metadata = loaded.modelDescription.metadata[.creatorDefinedKey] as? [String: String]
            guard metadata?["feature_version"] == WindowFeatures.version,
                  metadata?["evaluation_passed"] == "true",
                  let input = loaded.modelDescription.inputDescriptionsByName["features"]?.multiArrayConstraint,
                  input.shape == [NSNumber(value: 12)],
                  loaded.modelDescription.outputDescriptionsByName["probability"]?.type == .multiArray else {
                model = nil; status = "Lernmodus: Modellformat unpassend"; return
            }
            if hasCandidate {
                model = nil
                if FileManager.default.fileExists(atPath: local.path) { try FileManager.default.removeItem(at: local) }
                try FileManager.default.moveItem(at: candidate, to: local)
                model = try MLModel(contentsOf: local, configuration: config)
            } else { model = loaded }
            status = "Trainiertes Modell vorhanden; Freigabe nötig"
        } catch { model = nil; status = "Lernmodus: Modell konnte nicht geladen werden" }
    }
    var available: Bool { model != nil }
    func probability(_ features: [Double]) throws -> Double? {
        guard let model else { return nil }
        let input = try MLMultiArray(shape: [NSNumber(value: features.count)], dataType: .double)
        for (i, value) in features.enumerated() { input[i] = NSNumber(value: value) }
        let provider = try MLDictionaryFeatureProvider(dictionary: ["features": MLFeatureValue(multiArray: input)])
        let result = try model.prediction(from: provider)
        guard let output = result.featureValue(for: "probability")?.multiArrayValue else { return nil }
        return output[0].doubleValue
    }
}
