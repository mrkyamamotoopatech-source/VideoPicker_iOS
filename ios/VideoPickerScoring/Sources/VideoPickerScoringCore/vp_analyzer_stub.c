#include "vp_analyzer.h"

#include <stdlib.h>

struct VpAnalyzer {
  int placeholder;
};

void vp_default_config(VpConfig* config) {
  if (!config) {
    return;
  }
  config->max_frames = 16;
  config->fps = 1.0f;
  config->normalize = (VpNormalize){360, 0};
  for (int i = 0; i < VP_MAX_ITEMS; ++i) {
    config->thresholds[i] = (VpThreshold){0.0f, 0.0f};
  }
  config->thresholds[VP_METRIC_SHARPNESS] = (VpThreshold){0.8f, 0.2f};
  config->thresholds[VP_METRIC_EXPOSURE] = (VpThreshold){0.8f, 0.2f};
  config->thresholds[VP_METRIC_MOTION_BLUR] = (VpThreshold){0.8f, 0.2f};
  config->thresholds[VP_METRIC_NOISE] = (VpThreshold){0.8f, 0.2f};
  config->thresholds[VP_METRIC_PERSON_BLUR] = (VpThreshold){0.8f, 0.2f};
}

VpAnalyzer* vp_create(const VpConfig* config) {
  (void)config;
  VpAnalyzer* analyzer = (VpAnalyzer*)calloc(1, sizeof(VpAnalyzer));
  return analyzer;
}

int vp_analyze_frames(VpAnalyzer* analyzer, const VpFrame* frames, int frame_count,
                      VpAggregateResult* out_result) {
  (void)analyzer;
  (void)frames;
  (void)frame_count;
  if (out_result) {
    out_result->item_count = 0;
  }
  return VP_ERR_UNSUPPORTED;
}

void vp_destroy(VpAnalyzer* analyzer) {
  free(analyzer);
}
