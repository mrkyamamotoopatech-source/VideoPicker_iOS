#include "vp_analyzer.h"

#include <stdlib.h>

struct VpAnalyzer {
  int placeholder;
};

void vp_default_config(VpConfig* config) {
  if (!config) {
    return;
  }
  config->fps = 1.0f;
  config->max_frames = 16;
  config->start_time_sec = 0.0f;
  config->sharpness = (VpThreshold){0.8f, 0.2f};
  config->exposure = (VpThreshold){0.8f, 0.2f};
  config->motion_blur = (VpThreshold){0.8f, 0.2f};
  config->noise = (VpThreshold){0.8f, 0.2f};
}

VpAnalyzer* vp_create(const VpConfig* config) {
  (void)config;
  VpAnalyzer* analyzer = (VpAnalyzer*)calloc(1, sizeof(VpAnalyzer));
  return analyzer;
}

int vp_analyze_video_file(VpAnalyzer* analyzer, const char* path, VpAggregateResult* out_result) {
  (void)analyzer;
  (void)path;
  if (out_result) {
    out_result->item_count = 0;
  }
  return VP_ERR_UNSUPPORTED;
}

void vp_destroy(VpAnalyzer* analyzer) {
  free(analyzer);
}
