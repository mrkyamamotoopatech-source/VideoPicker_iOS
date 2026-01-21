import Foundation

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
        if code != VP_OK {
            throw VideoPickerScoringError.analyzeFailed(code: code)
        }
        let meanItems = (0..<Int(result.item_count)).map { index -> VideoQualityItem in
            let item = result.mean[index]
            let id = withUnsafePointer(to: item.id_str) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(VP_METRIC_ID_MAX_LEN)) {
                    String(cString: $0)
                }
            }
            return VideoQualityItem(id: id, score: item.score, raw: item.raw)
        }
        let worstItems = (0..<Int(result.item_count)).map { index -> VideoQualityItem in
            let item = result.worst[index]
            let id = withUnsafePointer(to: item.id_str) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(VP_METRIC_ID_MAX_LEN)) {
                    String(cString: $0)
                }
            }
            return VideoQualityItem(id: id, score: item.score, raw: item.raw)
        }
        return VideoQualityAggregate(mean: meanItems, worst: worstItems)
    }

    public static func defaultConfig() -> VpConfig {
        var config = VpConfig()
        vp_default_config(&config)
        return config
    }
}
