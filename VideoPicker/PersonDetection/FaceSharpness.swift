//
//  FaceSharpness.swift
//  VideoPicker
//

import CoreGraphics

/// 8bitグレースケール画素列のラプラシアン分散を求める処理の抽象
protocol LaplacianVarianceComputing: Sendable {
    /// 動作確認用のログに出す実装名
    var engineName: String { get }
    /// 4近傍ラプラシアンの分散。値が大きいほど鮮明
    func variance(gray: [UInt8], width: Int, height: Int) -> Float
}

/// C++コアのcompute_sharpnessと同じ式（4近傍ラプラシアンの分散）のSwift実装
struct SwiftLaplacianVariance: LaplacianVarianceComputing {
    private static let minimumSide = 3

    let engineName = "Swift実装"

    func variance(gray: [UInt8], width: Int, height: Int) -> Float {
        guard width >= Self.minimumSide, height >= Self.minimumSide, gray.count >= width * height else {
            return 0
        }
        var sum = 0.0
        var sumSquares = 0.0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let index = y * width + x
                let neighbors = Int(gray[index - 1]) + Int(gray[index + 1])
                    + Int(gray[index - width]) + Int(gray[index + width])
                let laplacian = Double(neighbors - 4 * Int(gray[index]))
                sum += laplacian
                sumSquares += laplacian * laplacian
            }
        }
        let count = Double((width - 2) * (height - 2))
        let mean = sum / count
        return Float(max(0, sumSquares / count - mean * mean))
    }
}

/// OpenCV（cv::Laplacian）による実装。アプリ本体ではこちらを使う
struct OpenCVLaplacianVariance: LaplacianVarianceComputing {
    /// 実行時に動いているOpenCV（MediaPipeに同梱されたもの）のバージョン
    static let linkedVersion: String = VPOpenCVLaplacian.openCVVersion()
    /// コンパイルに使ったOpenCVヘッダのバージョン。linkedVersionと一致している必要がある
    static let headerVersion: String = VPOpenCVLaplacian.headerVersion()

    let engineName = "OpenCV \(OpenCVLaplacianVariance.linkedVersion)"

    func variance(gray: [UInt8], width: Int, height: Int) -> Float {
        // バッファ長が足りないままC++側へ渡すと範囲外を読むため、ここで弾く
        guard width > 0, height > 0, gray.count >= width * height else { return 0 }
        return gray.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            return VPOpenCVLaplacian.variance(ofGray: baseAddress, width: width, height: height)
        }
    }
}

/// 顔領域を固定サイズのグレースケール画像に揃えてから鮮明さを評価する
struct FaceSharpnessEvaluator: Sendable {
    /// 顔の大きさや動画の解像度で値が変わらないよう、評価前に揃える一辺のピクセル数
    static let patchSize = 64
    static let wholeFrame = CGRect(x: 0, y: 0, width: 1, height: 1)

    let laplacian: LaplacianVarianceComputing

    /// 最も大きく写っている顔の鮮明さ。顔がなければnil
    func sharpness(of faces: [DetectedFace], in cgImage: CGImage) -> Float? {
        let largest = faces.max { lhs, rhs in
            lhs.boundingBox.width * lhs.boundingBox.height < rhs.boundingBox.width * rhs.boundingBox.height
        }
        guard let largest else { return nil }
        return sharpness(ofRegion: largest.boundingBox, in: cgImage)
    }

    /// 正規化座標で指定した領域の鮮明さ。領域が画像外ならnil
    func sharpness(ofRegion region: CGRect, in cgImage: CGImage) -> Float? {
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let pixelRect = CGRect(
            x: region.minX * imageWidth,
            y: region.minY * imageHeight,
            width: region.width * imageWidth,
            height: region.height * imageHeight
        ).integral.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

        guard !pixelRect.isNull, pixelRect.width >= 1, pixelRect.height >= 1,
              let cropped = cgImage.cropping(to: pixelRect),
              let gray = grayPatch(from: cropped) else {
            return nil
        }
        return laplacian.variance(gray: gray, width: Self.patchSize, height: Self.patchSize)
    }

    private func grayPatch(from image: CGImage) -> [UInt8]? {
        let side = Self.patchSize
        var pixels = [UInt8](repeating: 0, count: side * side)
        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return didDraw ? pixels : nil
    }
}
