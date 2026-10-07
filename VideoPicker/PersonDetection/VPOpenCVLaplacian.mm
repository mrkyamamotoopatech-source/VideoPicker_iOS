//
//  VPOpenCVLaplacian.mm
//  VideoPicker
//

// OpenCVの実体はMediaPipe（MediaPipeTasksCommon）に同梱されたものがリンクされる。
// ヘッダは scripts/fetch_opencv_headers.sh で同じバージョンのものを取得している。
// OpenCVのヘッダはAppleのヘッダより先に読み込む（NOなどのマクロ衝突を避けるため）
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

#import "VPOpenCVLaplacian.h"

static const NSInteger kMinimumSide = 3;
// 開口サイズ1は4近傍のラプラシアン核になり、C++コアのcompute_sharpnessと同じ式になる
static const int kLaplacianApertureSize = 1;

@implementation VPOpenCVLaplacian

+ (float)varianceOfGray:(const uint8_t *)gray width:(NSInteger)width height:(NSInteger)height {
    if (gray == NULL || width < kMinimumSide || height < kMinimumSide) {
        return 0;
    }
    try {
        // 入力バッファはコピーせず参照するだけで、書き換えない
        const cv::Mat source((int)height, (int)width, CV_8UC1, const_cast<uint8_t *>(gray));
        cv::Mat laplacian;
        cv::Laplacian(source, laplacian, CV_64F, kLaplacianApertureSize);

        // 外周は境界補間の影響を受けるため、C++コアと同じく内側だけで分散を取る
        const cv::Mat inner = laplacian(cv::Rect(1, 1, (int)width - 2, (int)height - 2));
        cv::Scalar mean;
        cv::Scalar standardDeviation;
        cv::meanStdDev(inner, mean, standardDeviation);
        return (float)(standardDeviation[0] * standardDeviation[0]);
    } catch (const std::exception &exception) {
        // cv::Exceptionに加えてメモリ確保失敗なども捕捉する。C++例外がSwift側へ漏れると異常終了するため
        NSLog(@"[VPOpenCVLaplacian] OpenCVの処理に失敗: %s", exception.what());
        return 0;
    }
}

+ (NSString *)openCVVersion {
    // ヘッダの定数ではなくライブラリ側の関数から取得し、実際にリンクされていることを確認できるようにする
    return [NSString stringWithUTF8String:cv::getVersionString().c_str()];
}

+ (NSString *)headerVersion {
    return @CV_VERSION;
}

@end
