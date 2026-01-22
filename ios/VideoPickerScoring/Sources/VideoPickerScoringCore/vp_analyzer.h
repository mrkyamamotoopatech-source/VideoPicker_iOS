#ifndef VP_ANALYZER_H
#define VP_ANALYZER_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

#define VP_MAX_ITEMS 16
#define VP_METRIC_ID_MAX_LEN 32

typedef enum {
  VP_OK = 0,
  VP_ERR_INVALID_ARGUMENT = 1,
  VP_ERR_ALLOC = 2,
  VP_ERR_FFMPEG = 3,
  VP_ERR_DECODE = 4,
  VP_ERR_UNSUPPORTED = 5
} VpErrorCode;

typedef enum {
  VP_METRIC_SHARPNESS = 0,
  VP_METRIC_EXPOSURE = 1,
  VP_METRIC_MOTION_BLUR = 2,
  VP_METRIC_NOISE = 3,
  VP_METRIC_PERSON_BLUR = 4
} VpMetricId;

typedef enum {
  VP_PIXEL_GRAY8 = 0,
  VP_PIXEL_RGBA8888 = 1,
  VP_PIXEL_BGRA8888 = 2
} VpPixelFormat;

typedef struct {
  float good;
  float bad;
} VpThreshold;

typedef struct {
  int32_t target_short_side;
  int32_t target_long_side;
} VpNormalize;

typedef struct {
  int32_t max_frames;
  float fps;
  VpNormalize normalize;
  VpThreshold thresholds[VP_MAX_ITEMS];
} VpConfig;

typedef struct {
  int32_t width;
  int32_t height;
  int32_t stride_bytes;
  VpPixelFormat format;
  const uint8_t* data;
} VpFrame;

typedef struct {
  int32_t id;
  char id_str[VP_METRIC_ID_MAX_LEN];
  float score;
  float raw;
} VpItemResult;

typedef struct {
  int32_t item_count;
  VpItemResult mean[VP_MAX_ITEMS];
  VpItemResult worst[VP_MAX_ITEMS];
} VpAggregateResult;

typedef struct VpAnalyzer VpAnalyzer;

void vp_default_config(VpConfig* config);

VpAnalyzer* vp_create(const VpConfig* config);

int vp_analyze_frames(VpAnalyzer* analyzer, const VpFrame* frames, int frame_count,
                      VpAggregateResult* out_result);

void vp_destroy(VpAnalyzer* analyzer);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // VP_ANALYZER_H
