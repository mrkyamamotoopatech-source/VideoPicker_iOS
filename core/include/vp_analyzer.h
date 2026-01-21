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
  VP_METRIC_NOISE = 3
} VpMetricId;

typedef struct {
  float good;
  float bad;
} VpThreshold;

typedef struct {
  float fps;
  int32_t max_frames;
  VpThreshold sharpness;
  VpThreshold exposure;
  VpThreshold motion_blur;
  VpThreshold noise;
} VpConfig;

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

int vp_analyze_video_file(VpAnalyzer* analyzer, const char* path, VpAggregateResult* out_result);

void vp_destroy(VpAnalyzer* analyzer);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // VP_ANALYZER_H
