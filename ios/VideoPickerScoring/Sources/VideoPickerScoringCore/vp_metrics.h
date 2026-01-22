#ifndef VP_METRICS_H
#define VP_METRICS_H

#include <stdint.h>

#include "vp_analyzer.h"

namespace vp {

struct GrayFrame {
  int width;
  int height;
  int stride;
  const uint8_t* data;
};

struct MetricResult {
  float raw;
  float score;
};

float normalize_score(float raw, const VpThreshold& threshold);

float compute_sharpness(const GrayFrame& frame);
float compute_exposure_clipping(const GrayFrame& frame);
float compute_noise_estimate(const GrayFrame& frame);
float compute_motion_blur(const GrayFrame& frame, const GrayFrame* prev_frame);

const char* metric_id_to_string(VpMetricId id);

} // namespace vp

#endif // VP_METRICS_H
