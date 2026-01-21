import Foundation
import VideoPickerScoringCore

public struct VideoQualityItem {
    public let id: String
    public let score: Float
    public let raw: Float
}

public struct VideoQualityAggregate {
    public let mean: [VideoQualityItem]
    public let worst: [VideoQualityItem]
}

public enum VideoPickerScoringError: Error {
    case createFailed
    case analyzeFailed(code: Int32)
}

public final class VideoPickerScoring {
    private let analyzer: OpaquePointer

    public init(config: VpConfig = VideoPickerScoring.defaultConfig()) throws {
        var mutableConfig = config
        guard let analyzer = vp_create(&mutableConfig) else {
            throw VideoPickerScoringError.createFailed
        }
        self.analyzer = analyzer
    }

    deinit {
        vp_destroy(analyzer)
    }

    public func analyze(url: URL) throws -> VideoQualityAggregate {
        var result = VpAggregateResult()
        let code = url.path.withCString { path in
            vp_analyze_video_file(analyzer, path, &result)
        }
        if code != 0 {
            throw VideoPickerScoringError.analyzeFailed(code: code)
        }
        let meanItems = withUnsafePointer(to: &result.mean) { pointer in
            pointer.withMemoryRebound(to: VpItemResult.self, capacity: Int(result.item_count)) { buffer in
                (0..<Int(result.item_count)).map { index -> VideoQualityItem in
                    let item = buffer[index]
                    let id = withUnsafePointer(to: item.id_str) {
                        $0.withMemoryRebound(to: CChar.self, capacity: Int(VP_METRIC_ID_MAX_LEN)) {
                            String(cString: $0)
                        }
                    }
                    return VideoQualityItem(id: id, score: item.score, raw: item.raw)
                }
            }
        }
        let worstItems = withUnsafePointer(to: &result.worst) { pointer in
            pointer.withMemoryRebound(to: VpItemResult.self, capacity: Int(result.item_count)) { buffer in
                (0..<Int(result.item_count)).map { index -> VideoQualityItem in
                    let item = buffer[index]
                    let id = withUnsafePointer(to: item.id_str) {
                        $0.withMemoryRebound(to: CChar.self, capacity: Int(VP_METRIC_ID_MAX_LEN)) {
                            String(cString: $0)
                        }
                    }
                    return VideoQualityItem(id: id, score: item.score, raw: item.raw)
                }
            }
        }
        return VideoQualityAggregate(mean: meanItems, worst: worstItems)
    }

    public static func weightedScore(for aggregate: VideoQualityAggregate) -> Float? {
        let weights: [String: Float] = [
            "sharpness": 0.25,
            "exposure": 0.25,
            "motion_blur": 0.2,
            "noise": 0.15,
            "person_blur": 0.15
        ]
        let scoreById = Dictionary(uniqueKeysWithValues: aggregate.mean.map { ($0.id, $0.score) })
        var weightedSum: Float = 0.0
        var weightSum: Float = 0.0
        for (id, weight) in weights {
            if let score = scoreById[id] {
                weightedSum += score * weight
                weightSum += weight
            }
        }
        guard weightSum > 0 else {
            return nil
        }
        return weightedSum / weightSum
    }

    public static func defaultConfig() -> VpConfig {
        var config = VpConfig()
        vp_default_config(&config)
        return config
    }
}
