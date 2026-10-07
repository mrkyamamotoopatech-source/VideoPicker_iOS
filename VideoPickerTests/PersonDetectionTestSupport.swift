//
//  PersonDetectionTestSupport.swift
//  VideoPickerTests
//

import CoreImage
import CoreVideo
import UIKit

/// テストバンドルの場所を特定するためだけのクラス
private final class TestBundleToken {}

enum TestImageError: Error {
    case fixtureNotFound(String)
    case renderingFailed
}

enum TestImages {
    /// 顔が1つ写っているポートレート写真（MediaPipe公式のテスト素材）
    static func portrait() throws -> UIImage {
        let bundle = Bundle(for: TestBundleToken.self)
        guard let url = bundle.url(forResource: "portrait", withExtension: "jpg"),
              let image = UIImage(contentsOfFile: url.path) else {
            throw TestImageError.fixtureNotFound("portrait.jpg")
        }
        return image
    }

    /// 顔を含まない単色画像
    static func flat(size: CGSize = CGSize(width: 256, height: 256), color: UIColor = .gray) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// 画素データを反時計回りに90度回した画像。縦向き動画のフレームと同じく、
    /// 表示時に `.right` を指定すると正立する
    static func sidewaysPixels(of image: UIImage) throws -> CGImage {
        guard let cgImage = image.cgImage else { throw TestImageError.renderingFailed }
        let rotatedSize = CGSize(width: cgImage.height, height: cgImage.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: rotatedSize, format: format).image { _ in
            UIImage(cgImage: cgImage, scale: 1, orientation: .left)
                .draw(in: CGRect(origin: .zero, size: rotatedSize))
        }
        guard let rotated = rendered.cgImage else { throw TestImageError.renderingFailed }
        return rotated
    }

    /// 正立画像上の正規化矩形を、sidewaysPixels後の画素データ上の正規化矩形に変換する
    static func sidewaysRect(fromUpright rect: CGRect) -> CGRect {
        CGRect(x: rect.minY, y: 1 - rect.maxX, width: rect.height, height: rect.width)
    }

    /// ガウスぼかしをかけた画像（元画像と同じ範囲を切り出す）
    static func blurred(_ image: UIImage, radius: Double) throws -> UIImage {
        guard let cgImage = image.cgImage else { throw TestImageError.renderingFailed }
        let input = CIImage(cgImage: cgImage)
        let output = input.clampedToExtent()
            .applyingGaussianBlur(sigma: radius)
            .cropped(to: input.extent)
        guard let rendered = CIContext().createCGImage(output, from: input.extent) else {
            throw TestImageError.renderingFailed
        }
        return UIImage(cgImage: rendered)
    }

    /// 動画フレームと同じ32BGRA形式のピクセルバッファに変換する
    static func pixelBuffer(from image: UIImage) throws -> CVPixelBuffer {
        guard let cgImage = image.cgImage else { throw TestImageError.renderingFailed }
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        var created: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            cgImage.width,
            cgImage.height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &created
        )
        guard let buffer = created else { throw TestImageError.renderingFailed }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw TestImageError.renderingFailed
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        return buffer
    }
}

/// 白黒の市松模様（エッジが多い）のグレースケール画素列
func checkerboardGray(size: Int, cell: Int) -> [UInt8] {
    (0..<size * size).map { index in
        let x = index % size
        let y = index / size
        return ((x / cell) + (y / cell)).isMultiple(of: 2) ? 255 : 0
    }
}
