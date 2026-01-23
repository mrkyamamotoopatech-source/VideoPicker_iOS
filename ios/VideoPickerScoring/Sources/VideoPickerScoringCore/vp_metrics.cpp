#include "vp_metrics.h"

#include <algorithm>
#include <cmath>
#include <cstdio>

#if __has_include(<opencv2/core.hpp>)
#define VP_HAS_OPENCV 1
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/objdetect.hpp>
#endif

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

static float compute_sharpness_in_rect(const GrayFrame& frame, int x, int y, int width, int height) {
  int x0 = std::max(1, x);
  int y0 = std::max(1, y);
  int x1 = std::min(frame.width - 2, x + width - 1);
  int y1 = std::min(frame.height - 2, y + height - 1);

  if (x1 <= x0 || y1 <= y0) {
    return 0.0f;
  }

  double sum = 0.0;
  double sum_sq = 0.0;
  int count = 0;

  for (int yy = y0; yy <= y1; ++yy) {
    const uint8_t* row = frame.data + yy * frame.stride;
    const uint8_t* row_prev = frame.data + (yy - 1) * frame.stride;
    const uint8_t* row_next = frame.data + (yy + 1) * frame.stride;
    for (int xx = x0; xx <= x1; ++xx) {
      int center = row[xx];
      int lap = -4 * center + row[xx - 1] + row[xx + 1] + row_prev[xx] + row_next[xx];
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
#if defined(VP_HAS_OPENCV)
  std::fprintf(stderr, "vp_scoring person_blur: OpenCV headers detected, using HOG detector path\n");
  if (frame.width <= 0 || frame.height <= 0 || !frame.data) {
    std::fprintf(stderr, "vp_scoring person_blur: invalid frame width=%d height=%d data=%p\n",
                 frame.width, frame.height, static_cast<const void*>(frame.data));
    return 0.0f;
  }

  const int max_dim = std::max(frame.width, frame.height);
  const int target_max_dim = 480;
  float scale = 1.0f;
  if (max_dim > target_max_dim) {
    scale = static_cast<float>(target_max_dim) / static_cast<float>(max_dim);
  }
  std::fprintf(stderr, "vp_scoring person_blur: frame=%dx%d stride=%d max_dim=%d scale=%.4f\n",
               frame.width, frame.height, frame.stride, max_dim, scale);

  cv::Mat gray(frame.height, frame.width, CV_8UC1, const_cast<uint8_t*>(frame.data),
               static_cast<size_t>(frame.stride));
  cv::Mat resized;
  if (scale < 1.0f) {
    cv::resize(gray, resized, cv::Size(), scale, scale, cv::INTER_AREA);
  } else {
    resized = gray;
  }

  static thread_local cv::HOGDescriptor hog;
  static thread_local bool hog_ready = false;
  if (!hog_ready) {
    hog.setSVMDetector(cv::HOGDescriptor::getDefaultPeopleDetector());
    hog_ready = true;
  }

  std::vector<cv::Rect> detections;
  hog.detectMultiScale(resized, detections, 0.0, cv::Size(8, 8), cv::Size(16, 16), 1.05, 2.0, false);
  std::fprintf(stderr, "vp_scoring person_blur: detectMultiScale resized=%dx%d detections=%zu\n",
               resized.cols, resized.rows, detections.size());

  if (detections.empty()) {
    std::fprintf(stderr, "vp_scoring person_blur: OpenCV enabled, no person detected (fallback)\n");
    return compute_sharpness(frame);
  }

  double weighted_sum = 0.0;
  double area_sum = 0.0;
  float inv_scale = 1.0f / scale;

  for (const auto& rect : detections) {
    int x = static_cast<int>(rect.x * inv_scale);
    int y = static_cast<int>(rect.y * inv_scale);
    int width = static_cast<int>(rect.width * inv_scale);
    int height = static_cast<int>(rect.height * inv_scale);

    int clamped_width = std::min(width, frame.width - x);
    int clamped_height = std::min(height, frame.height - y);
    if (clamped_width <= 0 || clamped_height <= 0) {
      std::fprintf(stderr,
                   "vp_scoring person_blur: skip detection x=%d y=%d w=%d h=%d clamped_w=%d clamped_h=%d\n",
                   x, y, width, height, clamped_width, clamped_height);
      continue;
    }

    float sharpness = compute_sharpness_in_rect(frame, x, y, clamped_width, clamped_height);
    double area = static_cast<double>(clamped_width) * static_cast<double>(clamped_height);
    weighted_sum += static_cast<double>(sharpness) * area;
    area_sum += area;
    std::fprintf(stderr,
                 "vp_scoring person_blur: detection x=%d y=%d w=%d h=%d sharpness=%.4f area=%.0f\n",
                 x, y, clamped_width, clamped_height, sharpness, area);
  }

  if (area_sum <= 0.0) {
    std::fprintf(stderr, "vp_scoring person_blur: area_sum=0, falling back to full-frame sharpness\n");
    return compute_sharpness(frame);
  }

  float score = static_cast<float>(weighted_sum / area_sum);
  std::fprintf(stderr, "vp_scoring person_blur: weighted_sum=%.4f area_sum=%.4f score=%.4f\n",
               weighted_sum, area_sum, score);
  return score;
#else
  std::fprintf(stderr, "vp_scoring person_blur: OpenCV headers not available, using sharpness fallback\n");
  return compute_sharpness(frame);
#endif
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
