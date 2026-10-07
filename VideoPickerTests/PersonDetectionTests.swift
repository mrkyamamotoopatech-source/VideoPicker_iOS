//
//  PersonDetectionTests.swift
//  VideoPickerTests
//

import Testing
import UIKit
@testable import VideoPicker

private let unitRect = CGRect(x: 0, y: 0, width: 1, height: 1)

struct MediaPipeFaceDetectorTests {

    @Test func detectsOneFaceInPortraitPhoto() throws {
        // Arrange
        let detector = try MediaPipeFaceDetector.makeBundled()
        let image = try TestImages.portrait()

        // Act
        let faces = try detector.detectFaces(in: image)

        // Assert
        #expect(faces.count == 1)
        let face = try #require(faces.first)
        #expect(face.confidence >= 0.5)
        #expect(unitRect.contains(face.boundingBox))
        #expect(face.boundingBox.width > 0.05)
    }

    @Test func returnsNoFacesForFlatImage() throws {
        let detector = try MediaPipeFaceDetector.makeBundled()

        let faces = try detector.detectFaces(in: TestImages.flat())

        #expect(faces.isEmpty)
    }

    @Test func detectsFaceInPixelBuffer() throws {
        let detector = try MediaPipeFaceDetector.makeBundled()
        let buffer = try TestImages.pixelBuffer(from: TestImages.portrait())

        let faces = try detector.detectFaces(in: buffer, orientation: .up)

        #expect(faces.count == 1)
    }

    @Test func detectsFaceInSidewaysImageAndReportsBoxInStoredPixelCoordinates() throws {
        // Arrange: 縦向き動画のフレームと同じ、画素データが横倒しで向き情報が.rightの画像
        let detector = try MediaPipeFaceDetector.makeBundled()
        let upright = try TestImages.portrait()
        let uprightFace = try #require(try detector.detectFaces(in: upright).first)
        let expected = TestImages.sidewaysRect(fromUpright: uprightFace.boundingBox)
        let sideways = UIImage(cgImage: try TestImages.sidewaysPixels(of: upright), scale: 1, orientation: .right)

        // Act
        let face = try #require(try detector.detectFaces(in: sideways).first)

        // Assert: 切り出しにそのまま使えるよう、画素データ上の座標で返る
        let box = face.boundingBox
        #expect(abs(box.midX - expected.midX) < 0.06, "actual=\(box) expected=\(expected)")
        #expect(abs(box.midY - expected.midY) < 0.06, "actual=\(box) expected=\(expected)")
        #expect(abs(box.width - expected.width) < 0.1, "actual=\(box) expected=\(expected)")
    }

    @Test func detectsFaceInSidewaysPixelBufferWhenOrientationIsGiven() throws {
        let detector = try MediaPipeFaceDetector.makeBundled()
        let upright = try TestImages.portrait()
        let uprightFace = try #require(try detector.detectFaces(in: upright).first)
        let expected = TestImages.sidewaysRect(fromUpright: uprightFace.boundingBox)
        let buffer = try TestImages.pixelBuffer(from: UIImage(cgImage: try TestImages.sidewaysPixels(of: upright)))

        let face = try #require(try detector.detectFaces(in: buffer, orientation: .right).first)

        let box = face.boundingBox
        #expect(abs(box.midX - expected.midX) < 0.06, "actual=\(box) expected=\(expected)")
        #expect(abs(box.midY - expected.midY) < 0.06, "actual=\(box) expected=\(expected)")
    }

    @Test func throwsWhenModelFileIsMissing() {
        #expect(throws: (any Error).self) {
            _ = try MediaPipeFaceDetector(modelPath: "/nonexistent/model.tflite")
        }
    }
}

struct SwiftLaplacianVarianceTests {

    @Test func returnsZeroForFlatPatch() {
        let gray = [UInt8](repeating: 128, count: 64 * 64)

        let variance = SwiftLaplacianVariance().variance(gray: gray, width: 64, height: 64)

        #expect(variance == 0)
    }

    @Test func returnsHighValueForCheckerboard() {
        let gray = checkerboardGray(size: 64, cell: 4)

        let variance = SwiftLaplacianVariance().variance(gray: gray, width: 64, height: 64)

        #expect(variance > 1000)
    }

    @Test func returnsZeroWhenPatchIsTooSmall() {
        let variance = SwiftLaplacianVariance().variance(gray: [10, 200, 30, 90], width: 2, height: 2)

        #expect(variance == 0)
    }
}

struct OpenCVLaplacianVarianceTests {
    private let tolerance: Float = 0.01

    @Test func returnsZeroForFlatPatch() {
        let gray = [UInt8](repeating: 128, count: 64 * 64)

        let variance = OpenCVLaplacianVariance().variance(gray: gray, width: 64, height: 64)

        #expect(variance == 0)
    }

    @Test func matchesSwiftImplementationOnCheckerboard() {
        let gray = checkerboardGray(size: 64, cell: 4)

        let openCV = OpenCVLaplacianVariance().variance(gray: gray, width: 64, height: 64)
        let swift = SwiftLaplacianVariance().variance(gray: gray, width: 64, height: 64)

        #expect(abs(openCV - swift) <= swift * tolerance)
    }

    @Test func matchesSwiftImplementationOnNonSquareGradient() {
        // 幅と高さの取り違えを検出できるよう、縦横で大きさの違う画素列を使う
        let width = 48
        let height = 20
        let gray = (0..<width * height).map { index in
            UInt8(truncatingIfNeeded: (index % width) * (index / width) * 7)
        }

        let openCV = OpenCVLaplacianVariance().variance(gray: gray, width: width, height: height)
        let swift = SwiftLaplacianVariance().variance(gray: gray, width: width, height: height)

        #expect(swift > 0)
        #expect(abs(openCV - swift) <= swift * tolerance)
    }

    @Test func returnsZeroWhenPatchIsTooSmallOrBufferIsShort() {
        #expect(OpenCVLaplacianVariance().variance(gray: [10, 200, 30, 90], width: 2, height: 2) == 0)
        #expect(OpenCVLaplacianVariance().variance(gray: [1, 2, 3], width: 64, height: 64) == 0)
    }
}

struct FaceSharpnessEvaluatorTests {
    private let evaluator = FaceSharpnessEvaluator(laplacian: SwiftLaplacianVariance())

    @Test func returnsNilWhenNoFaces() throws {
        let cgImage = try #require(TestImages.portrait().cgImage)

        #expect(evaluator.sharpness(of: [], in: cgImage) == nil)
    }

    @Test func blurredFaceScoresLowerThanSharpFace() throws {
        // Arrange
        let sharp = try TestImages.portrait()
        let blurred = try TestImages.blurred(sharp, radius: 8)
        let face = DetectedFace(boundingBox: CGRect(x: 0.25, y: 0.2, width: 0.5, height: 0.4), confidence: 0.9)
        let sharpCG = try #require(sharp.cgImage)
        let blurredCG = try #require(blurred.cgImage)

        // Act
        let sharpScore = try #require(evaluator.sharpness(of: [face], in: sharpCG))
        let blurredScore = try #require(evaluator.sharpness(of: [face], in: blurredCG))

        // Assert
        #expect(sharpScore > blurredScore * 2)
    }

    @Test func usesLargestFaceWhenMultipleFacesExist() throws {
        // 左半分が市松模様、右半分が単色の画像を作る
        let size = CGSize(width: 200, height: 100)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            for y in stride(from: 0, to: 100, by: 10) {
                for x in stride(from: 0, to: 100, by: 10) where ((x + y) / 10).isMultiple(of: 2) {
                    context.fill(CGRect(x: x, y: y, width: 10, height: 10))
                }
            }
        }
        let cgImage = try #require(image.cgImage)
        let largeTextured = DetectedFace(boundingBox: CGRect(x: 0, y: 0, width: 0.5, height: 1), confidence: 0.6)
        let smallFlat = DetectedFace(boundingBox: CGRect(x: 0.7, y: 0.3, width: 0.2, height: 0.4), confidence: 0.9)

        let score = try #require(evaluator.sharpness(of: [smallFlat, largeTextured], in: cgImage))

        #expect(score > 100)
    }

    @Test func returnsNilForRegionOutsideImage() throws {
        let cgImage = try #require(TestImages.flat().cgImage)

        #expect(evaluator.sharpness(ofRegion: CGRect(x: 2, y: 2, width: 0.5, height: 0.5), in: cgImage) == nil)
    }
}

struct PersonScoringTests {

    @Test func normalizedSharpnessClampsToUnitRange() {
        #expect(PersonScoring.normalizedSharpness(0) == 0)
        #expect(PersonScoring.normalizedSharpness(PersonScoring.sharpnessBadThreshold) == 0)
        #expect(PersonScoring.normalizedSharpness(PersonScoring.sharpnessGoodThreshold) == 1)
        #expect(PersonScoring.normalizedSharpness(10_000) == 1)
    }

    @Test func frameWithSharpFaceScoresAboveAnyFrameWithoutFace() {
        let withFace = PersonScoring.presenceScore(faceSharpness: PersonScoring.sharpnessGoodThreshold, heuristicScore: 0.1)
        let withoutFace = PersonScoring.presenceScore(faceSharpness: nil, heuristicScore: 1.0)

        #expect(withFace == 1.0)
        #expect(withoutFace == PersonScoring.noFaceScoreCeiling)
        #expect(withFace > withoutFace)
    }

    @Test func frameWithoutFaceKeepsHeuristicOrdering() {
        let low = PersonScoring.presenceScore(faceSharpness: nil, heuristicScore: 0.1)
        let high = PersonScoring.presenceScore(faceSharpness: nil, heuristicScore: 0.4)

        #expect(low < high)
    }
}

/// 顔検出の結果を固定で返すテスト用の検出器
private struct StubFaceDetector: FaceDetecting {
    let faces: [DetectedFace]
    var shouldThrow = false
    let engineName = "Stub"

    struct StubError: Error {}

    func detectFaces(in image: UIImage) throws -> [DetectedFace] {
        if shouldThrow { throw StubError() }
        return faces
    }

    func detectFaces(in pixelBuffer: CVPixelBuffer, orientation: UIImage.Orientation) throws -> [DetectedFace] {
        if shouldThrow { throw StubError() }
        return faces
    }
}

struct PersonBlurScorerTests {
    private let evaluator = FaceSharpnessEvaluator(laplacian: SwiftLaplacianVariance())
    private let centerFace = DetectedFace(boundingBox: CGRect(x: 0.25, y: 0.2, width: 0.5, height: 0.4), confidence: 0.9)

    @Test func reportsFaceSharpnessWhenFaceIsDetected() throws {
        let scorer = PersonBlurScorer(detector: StubFaceDetector(faces: [centerFace]), evaluator: evaluator)

        let analysis = try #require(scorer.analyze(try TestImages.portrait()))

        #expect(analysis.hasFace)
        #expect((analysis.faceSharpness ?? 0) > 0)
    }

    @Test func reportsNoFaceWhenDetectorFindsNothing() throws {
        let scorer = PersonBlurScorer(detector: StubFaceDetector(faces: []), evaluator: evaluator)

        let analysis = try #require(scorer.analyze(try TestImages.portrait()))

        #expect(analysis == .noFace)
    }

    @Test func returnsNilWhenDetectorFailsSoCallerCanFallBackToHeuristic() throws {
        // 「検出できたが顔がない」と「検出自体に失敗した」を区別できること
        let scorer = PersonBlurScorer(
            detector: StubFaceDetector(faces: [centerFace], shouldThrow: true),
            evaluator: evaluator
        )

        #expect(scorer.analyze(try TestImages.portrait()) == nil)
    }

    @Test func statsCountDetectionsFacesAndSharpnessEvaluations() throws {
        // Arrange
        let image = try TestImages.portrait()
        let withFace = PersonBlurScorer(detector: StubFaceDetector(faces: [centerFace]), evaluator: evaluator)
        let withoutFace = PersonBlurScorer(detector: StubFaceDetector(faces: []), evaluator: evaluator)

        // Act
        _ = withFace.analyze(image)
        _ = withFace.analyze(image)
        _ = withoutFace.analyze(image)

        // Assert: 顔ありは検出と鮮明さ評価の両方、顔なしは検出だけが数えられる
        #expect(withFace.stats.snapshot() == PersonDetectionStats.Snapshot(
            detections: 2, framesWithFace: 2, sharpnessEvaluations: 2, failures: 0
        ))
        #expect(withoutFace.stats.snapshot() == PersonDetectionStats.Snapshot(
            detections: 1, framesWithFace: 0, sharpnessEvaluations: 0, failures: 0
        ))
    }

    @Test func statsCountFailuresWhenDetectorThrows() throws {
        let scorer = PersonBlurScorer(
            detector: StubFaceDetector(faces: [centerFace], shouldThrow: true),
            evaluator: evaluator
        )

        _ = scorer.analyze(try TestImages.portrait())

        #expect(scorer.stats.snapshot() == PersonDetectionStats.Snapshot(
            detections: 0, framesWithFace: 0, sharpnessEvaluations: 0, failures: 1
        ))
    }

    @Test func defaultScorerReportsMediaPipeAndOpenCVAsItsEngines() throws {
        let scorer = try #require(PersonBlurScorer.makeDefault())

        #expect(scorer.detector.engineName.contains("MediaPipe"))
        #expect(scorer.evaluator.laplacian.engineName == "OpenCV \(OpenCVLaplacianVariance.linkedVersion)")
    }

    @Test func openCVHeadersMatchTheLibraryBundledWithMediaPipe() {
        // OpenCVの実体はMediaPipeに同梱されたものを使っている。MediaPipeの更新で同梱版が変わると
        // ヘッダと実体がずれるので、ここで検知して scripts/fetch_opencv_headers.sh のバージョンを合わせる
        #expect(OpenCVLaplacianVariance.linkedVersion == OpenCVLaplacianVariance.headerVersion)
        #expect(OpenCVLaplacianVariance.linkedVersion == "4.5.3")
    }

    @Test func sharpnessDistributionTracksRangeMeanAndBuckets() {
        // Arrange: 閾値（2と20）の前後と、上限のないバケットに入る値
        let values: [Float] = [1, 10, 30, 150, 400]

        // Act
        let distribution = values.reduce(SharpnessDistribution.empty) { $0.adding($1) }

        // Assert
        #expect(distribution.count == 5)
        #expect(distribution.minimum == 1)
        #expect(distribution.maximum == 400)
        #expect(distribution.mean == 118.2)
        #expect(distribution.bucketCounts == [1, 1, 1, 0, 1, 1, 0])
        #expect(SharpnessDistribution.empty.mean == nil)
    }

    @Test func statsCollectFaceSharpnessDistribution() throws {
        let scorer = PersonBlurScorer(detector: StubFaceDetector(faces: [centerFace]), evaluator: evaluator)
        let noFaceScorer = PersonBlurScorer(detector: StubFaceDetector(faces: []), evaluator: evaluator)
        let image = try TestImages.portrait()

        _ = scorer.analyze(image)
        _ = scorer.analyze(image)
        _ = noFaceScorer.analyze(image)

        // 顔が見つかったフレームの値だけを集める
        #expect(scorer.stats.faceSharpnessDistribution().count == 2)
        #expect(noFaceScorer.stats.faceSharpnessDistribution().count == 0)
    }

    @Test func personBlurRawIsNilWhenDetectorFails() throws {
        let scorer = PersonBlurScorer(
            detector: StubFaceDetector(faces: [centerFace], shouldThrow: true),
            evaluator: evaluator
        )
        let buffer = try TestImages.pixelBuffer(from: TestImages.portrait())

        #expect(scorer.personBlurRawScore(for: buffer, orientation: .up) == nil)
    }

    @Test func realDetectorGivesConsistentResultsWhenCalledConcurrently() async throws {
        // Arrange: 採点時と同じく、共有の検出器を複数タスクから同時に呼ぶ
        let scorer = try #require(PersonBlurScorer.makeDefault())
        let image = try TestImages.portrait()
        let expected = try #require(scorer.analyze(image))
        let concurrentCalls = 16

        // Act
        let results = await withTaskGroup(of: FrameFaceAnalysis?.self) { group in
            for _ in 0..<concurrentCalls {
                group.addTask { scorer.analyze(image) }
            }
            var collected: [FrameFaceAnalysis?] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        // Assert
        #expect(results.count == concurrentCalls)
        #expect(results.allSatisfy { $0 == expected })
    }

    @Test func personBlurRawDropsWhenFaceIsBlurred() throws {
        // Arrange
        let scorer = PersonBlurScorer(detector: StubFaceDetector(faces: [centerFace]), evaluator: evaluator)
        let sharp = try TestImages.portrait()
        let sharpBuffer = try TestImages.pixelBuffer(from: sharp)
        let blurredBuffer = try TestImages.pixelBuffer(from: TestImages.blurred(sharp, radius: 8))

        // Act
        let sharpRaw = try #require(scorer.personBlurRawScore(for: sharpBuffer, orientation: .up))
        let blurredRaw = try #require(scorer.personBlurRawScore(for: blurredBuffer, orientation: .up))

        // Assert
        #expect(sharpRaw > blurredRaw * 2)
    }

    @Test func realDetectorRatesSharpFaceAsGoodAndBlurredFaceLower() throws {
        // Arrange: 実際のMediaPipe検出器と採点用の閾値の組み合わせを確認する
        let scorer = try #require(PersonBlurScorer.makeDefault())
        let sharp = try TestImages.portrait()
        let blurred = try TestImages.blurred(sharp, radius: 8)

        // Act
        let sharpValue = try #require(scorer.analyze(sharp)?.faceSharpness)
        let blurredValue = try #require(scorer.analyze(blurred)?.faceSharpness)

        // Assert: 素材やモデルの更新で絶対値は変わりうるので、相対関係と「ぼけは低評価」だけを確認する
        #expect(sharpValue > blurredValue * 2)
        #expect(PersonScoring.normalizedSharpness(sharpValue) > PersonScoring.normalizedSharpness(blurredValue))
        #expect(PersonScoring.normalizedSharpness(blurredValue) < 0.5)
    }

    @Test func thresholdsSpreadScoresAcrossSharpnessValuesMeasuredOnDevice() {
        // 実機計測（顔あり6775フレーム）では20未満が0.1%、200以上が約3割だった。
        // その範囲の中で採点に差がつくこと
        let blurred = PersonScoring.normalizedSharpness(30)
        let average = PersonScoring.normalizedSharpness(120)
        let sharp = PersonScoring.normalizedSharpness(250)

        #expect(blurred < 0.2)
        #expect(average > 0.4 && average < 0.7)
        #expect(sharp == 1)
    }

    @Test func personBlurRawFallsBackToWholeFrameWithoutFace() throws {
        let scorer = PersonBlurScorer(detector: StubFaceDetector(faces: []), evaluator: evaluator)
        let buffer = try TestImages.pixelBuffer(from: TestImages.portrait())

        let raw = try #require(scorer.personBlurRawScore(for: buffer, orientation: .up))

        #expect(raw > 0)
    }
}
