import CoreMedia
import CoreVideo
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
    case emptyFrames
    case invalidFrame
    case unsupportedInput
    case unsupportedPixelFormat(OSType)
}

public struct FrameInput {
    public let pixelBuffer: CVPixelBuffer
    public let timestamp: CMTime

    public init(pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        self.pixelBuffer = pixelBuffer
        self.timestamp = timestamp
    }
}

public final class VideoPickerScoring {
    private let analyzer: OpaquePointer

    public convenience init() throws {
        try self.init(config: Self.defaultConfig())
    }

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
        _ = url
        throw VideoPickerScoringError.unsupportedInput
    }

    public func analyze(frames: [FrameInput]) throws -> VideoQualityAggregate {
        guard !frames.isEmpty else {
            throw VideoPickerScoringError.emptyFrames
        }

        var vpFrames: [VpFrame] = []
        vpFrames.reserveCapacity(frames.count)
        var lockedBuffers: [CVPixelBuffer] = []
        lockedBuffers.reserveCapacity(frames.count)

        do {
            for frame in frames {
                let pixelBuffer = frame.pixelBuffer
                guard !CVPixelBufferIsPlanar(pixelBuffer) else {
                    throw VideoPickerScoringError.unsupportedPixelFormat(
                        CVPixelBufferGetPixelFormatType(pixelBuffer)
                    )
                }

                CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
                lockedBuffers.append(pixelBuffer)

                guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
                    throw VideoPickerScoringError.invalidFrame
                }

                let formatType = CVPixelBufferGetPixelFormatType(pixelBuffer)
                guard let vpFormat = Self.vpPixelFormat(for: formatType) else {
                    throw VideoPickerScoringError.unsupportedPixelFormat(formatType)
                }

                let width = CVPixelBufferGetWidth(pixelBuffer)
                let height = CVPixelBufferGetHeight(pixelBuffer)
                let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

                let vpFrame = VpFrame(
                    width: Int32(width),
                    height: Int32(height),
                    stride_bytes: Int32(bytesPerRow),
                    format: vpFormat,
                    data: baseAddress.assumingMemoryBound(to: UInt8.self)
                )
                vpFrames.append(vpFrame)
            }
        } catch {
            for buffer in lockedBuffers {
                CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
            }
            throw error
        }

        defer {
            for buffer in lockedBuffers {
                CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
            }
        }

        var result = VpAggregateResult()
        let code = vpFrames.withUnsafeBufferPointer { buffer in
            vp_analyze_frames(analyzer, buffer.baseAddress, Int32(buffer.count), &result)
        }
        if code != 0 {
            throw VideoPickerScoringError.analyzeFailed(code: code)
        }
        return Self.aggregate(from: result)
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

    private static func vpPixelFormat(for type: OSType) -> VpPixelFormat? {
        switch type {
        case kCVPixelFormatType_OneComponent8:
            return VP_PIXEL_GRAY8
        case kCVPixelFormatType_32RGBA:
            return VP_PIXEL_RGBA8888
        case kCVPixelFormatType_32BGRA:
            return VP_PIXEL_BGRA8888
        default:
            return nil
        }
    }

    private static func aggregate(from result: VpAggregateResult) -> VideoQualityAggregate {
        let meanItems = withUnsafePointer(to: result.mean) { pointer in
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
        let worstItems = withUnsafePointer(to: result.worst) { pointer in
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
}
