#include "vp_metrics.h"

#include <algorithm>
#include <cmath>

namespace vp {

float normalize_score(float raw, const VpThreshold& threshold) {
  if (threshold.good == threshold.bad) {
    return 0.0f;
  }
  float t = (raw - threshold.bad) / (threshold.good - threshold.bad);
  if (t < 0.0f) {
    t = 0.0f;
  } else if (t > 1.0f) {
    t = 1.0f;
  }
  return t;
}

static inline int clamp_index(int value, int min, int max) {
  return std::max(min, std::min(value, max));
}

float compute_sharpness(const GrayFrame& frame) {
  const int width = frame.width;
  const int height = frame.height;
  const int stride = frame.stride;
  const uint8_t* data = frame.data;

  double sum = 0.0;
  double sum_sq = 0.0;
  int count = 0;

  for (int y = 1; y < height - 1; ++y) {
    const uint8_t* row = data + y * stride;
    const uint8_t* row_prev = data + (y - 1) * stride;
    const uint8_t* row_next = data + (y + 1) * stride;
    for (int x = 1; x < width - 1; ++x) {
      int center = row[x];
      int lap = -4 * center + row[x - 1] + row[x + 1] + row_prev[x] + row_next[x];
      double value = static_cast<double>(lap);
      sum += value;
      sum_sq += value * value;
      ++count;
    }
  }

  if (count == 0) {
    return 0.0f;
  }

  double mean = sum / static_cast<double>(count);
  double variance = (sum_sq / static_cast<double>(count)) - (mean * mean);
  if (variance < 0.0) {
    variance = 0.0;
  }
  return static_cast<float>(variance);
}

float compute_person_blur(const GrayFrame& frame) {
  const int width = frame.width;
  const int height = frame.height;
  if (width <= 2 || height <= 2) {
    return compute_sharpness(frame);
  }

  const float crop_scale = 0.6f;
  int crop_width = std::max(3, static_cast<int>(std::round(width * crop_scale)));
  int crop_height = std::max(3, static_cast<int>(std::round(height * crop_scale)));
  crop_width = std::min(crop_width, width);
  crop_height = std::min(crop_height, height);

  int x0 = (width - crop_width) / 2;
  int y0 = (height - crop_height) / 2;
  const uint8_t* data = frame.data + y0 * frame.stride + x0;

  GrayFrame center_region{
      crop_width,
      crop_height,
      frame.stride,
      data,
  };
  return compute_sharpness(center_region);
}

float compute_exposure_clipping(const GrayFrame& frame) {
  const int width = frame.width;
  const int height = frame.height;
  const int stride = frame.stride;
  const uint8_t* data = frame.data;

  const int low_threshold = 5;
  const int high_threshold = 250;

  int clipped = 0;
  int total = width * height;

  for (int y = 0; y < height; ++y) {
    const uint8_t* row = data + y * stride;
    for (int x = 0; x < width; ++x) {
      int value = row[x];
      if (value <= low_threshold || value >= high_threshold) {
        ++clipped;
      }
    }
  }

  if (total == 0) {
    return 0.0f;
  }
  return static_cast<float>(clipped) / static_cast<float>(total);
}

float compute_noise_estimate(const GrayFrame& frame) {
  const int width = frame.width;
  const int height = frame.height;
  const int stride = frame.stride;
  const uint8_t* data = frame.data;

  double accum = 0.0;
  int count = 0;

  for (int y = 0; y < height; ++y) {
    for (int x = 0; x < width; ++x) {
      int sum = 0;
      int samples = 0;
      for (int dy = -1; dy <= 1; ++dy) {
        int yy = clamp_index(y + dy, 0, height - 1);
        const uint8_t* row = data + yy * stride;
        for (int dx = -1; dx <= 1; ++dx) {
          int xx = clamp_index(x + dx, 0, width - 1);
          sum += row[xx];
          ++samples;
        }
      }
      float mean = static_cast<float>(sum) / static_cast<float>(samples);
      float diff = std::abs(static_cast<float>(data[y * stride + x]) - mean);
      accum += diff;
      ++count;
    }
  }

  if (count == 0) {
    return 0.0f;
  }
  return static_cast<float>(accum / static_cast<double>(count)) / 255.0f;
}

static float compute_edge_strength(const GrayFrame& frame) {
  const int width = frame.width;
  const int height = frame.height;
  const int stride = frame.stride;
  const uint8_t* data = frame.data;

  double accum = 0.0;
  int count = 0;

  for (int y = 1; y < height - 1; ++y) {
    for (int x = 1; x < width - 1; ++x) {
      int gx = -data[(y - 1) * stride + (x - 1)] - 2 * data[y * stride + (x - 1)] - data[(y + 1) * stride + (x - 1)]
             + data[(y - 1) * stride + (x + 1)] + 2 * data[y * stride + (x + 1)] + data[(y + 1) * stride + (x + 1)];
      int gy = -data[(y - 1) * stride + (x - 1)] - 2 * data[(y - 1) * stride + x] - data[(y - 1) * stride + (x + 1)]
             + data[(y + 1) * stride + (x - 1)] + 2 * data[(y + 1) * stride + x] + data[(y + 1) * stride + (x + 1)];
      float mag = std::sqrt(static_cast<float>(gx * gx + gy * gy));
      accum += mag;
      ++count;
    }
  }

  if (count == 0) {
    return 0.0f;
  }
  return static_cast<float>(accum / static_cast<double>(count));
}

float compute_motion_blur(const GrayFrame& frame, const GrayFrame* prev_frame) {
  if (!prev_frame || !prev_frame->data) {
    return 0.0f;
  }

  const int width = frame.width;
  const int height = frame.height;
  const int stride = frame.stride;
  const uint8_t* data = frame.data;
  const uint8_t* prev = prev_frame->data;

  double diff_accum = 0.0;
  int count = width * height;
  for (int y = 0; y < height; ++y) {
    const uint8_t* row = data + y * stride;
    const uint8_t* prow = prev + y * prev_frame->stride;
    for (int x = 0; x < width; ++x) {
      diff_accum += std::abs(static_cast<int>(row[x]) - static_cast<int>(prow[x]));
    }
  }

  float diff_mean = 0.0f;
  if (count > 0) {
    diff_mean = static_cast<float>(diff_accum / static_cast<double>(count)) / 255.0f;
  }

  float edge_strength = compute_edge_strength(frame) / 255.0f;

  return diff_mean / (edge_strength + 1e-5f);
}

const char* metric_id_to_string(VpMetricId id) {
  switch (id) {
    case VP_METRIC_SHARPNESS:
      return "sharpness";
    case VP_METRIC_EXPOSURE:
      return "exposure";
    case VP_METRIC_MOTION_BLUR:
      return "motion_blur";
    case VP_METRIC_NOISE:
      return "noise";
    case VP_METRIC_PERSON_BLUR:
      return "person_blur";
    default:
      return "unknown";
  }
}

} // namespace vp
