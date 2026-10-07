//
//  VPOpenCVLaplacian.h
//  VideoPicker
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// OpenCVのcv::LaplacianをSwiftから呼ぶための薄いラッパー
@interface VPOpenCVLaplacian : NSObject

/// 8bitグレースケール画素列（width × height バイト）の4近傍ラプラシアン分散を返す。
/// 外周1ピクセルは評価に含めない。入力が小さすぎる場合や処理に失敗した場合は0を返す。
+ (float)varianceOfGray:(const uint8_t *)gray width:(NSInteger)width height:(NSInteger)height;

/// 実行時に動いているOpenCVライブラリのバージョン（例: "4.5.3"）。
/// OpenCVの実体はMediaPipeに同梱されたものを使っている
+ (NSString *)openCVVersion;

/// コンパイルに使ったOpenCVヘッダのバージョン。openCVVersionと一致している必要がある
+ (NSString *)headerVersion;

@end

NS_ASSUME_NONNULL_END
