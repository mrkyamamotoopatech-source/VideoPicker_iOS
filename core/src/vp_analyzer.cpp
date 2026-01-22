#include "vp_analyzer.h"

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <new>
#include <vector>

#include "vp_metrics.h"

namespace vp {

struct MetricDefinition {
  VpMetricId id;
  VpThreshold threshold;
  float (*compute)(const GrayFrame& frame, const GrayFrame* prev);
};

struct MetricAggregate {
  float sum_raw = 0.0f;
  float sum_score = 0.0f;
  float min_score = 1.0f;
  float raw_at_min = 0.0f;
  int count = 0;

  void update(float raw, float score) {
    sum_raw += raw;
    sum_score += score;
    if (score < min_score || count == 0) {
      min_score = score;
      raw_at_min = raw;
    }
    ++count;
  }
};

static float compute_sharpness_wrapper(const GrayFrame& frame, const GrayFrame*) {
  return compute_sharpness(frame);
}

static float compute_exposure_wrapper(const GrayFrame& frame, const GrayFrame*) {
  return compute_exposure_clipping(frame);
}

static float compute_motion_blur_wrapper(const GrayFrame& frame, const GrayFrame* prev) {
  return compute_motion_blur(frame, prev);
}

static float compute_noise_wrapper(const GrayFrame& frame, const GrayFrame*) {
  return compute_noise_estimate(frame);
}

static float compute_person_blur_wrapper(const GrayFrame& frame, const GrayFrame*) {
  return compute_sharpness(frame);
}

static VpThreshold threshold_for_metric(const VpConfig& config, VpMetricId id) {
  int index = static_cast<int>(id);
  if (index < 0 || index >= VP_MAX_ITEMS) {
    return VpThreshold{0.0f, 0.0f};
  }
  return config.thresholds[index];
}

static bool prepare_gray_frame(const VpFrame& input, std::vector<uint8_t>& buffer, GrayFrame* out) {
  if (!out || !input.data || input.width <= 0 || input.height <= 0) {
    return false;
  }

  int bytes_per_pixel = 0;
  switch (input.format) {
    case VP_PIXEL_GRAY8:
      bytes_per_pixel = 1;
      break;
    case VP_PIXEL_RGBA8888:
    case VP_PIXEL_BGRA8888:
      bytes_per_pixel = 4;
      break;
    default:
      return false;
  }

  if (input.stride_bytes <= 0 || input.stride_bytes < input.width * bytes_per_pixel) {
    return false;
  }

  buffer.assign(static_cast<size_t>(input.width) * static_cast<size_t>(input.height), 0);

  for (int y = 0; y < input.height; ++y) {
    const uint8_t* row = input.data + static_cast<size_t>(y) * static_cast<size_t>(input.stride_bytes);
    uint8_t* dst = buffer.data() + static_cast<size_t>(y) * static_cast<size_t>(input.width);
    if (input.format == VP_PIXEL_GRAY8) {
      std::copy(row, row + input.width, dst);
    } else {
      for (int x = 0; x < input.width; ++x) {
        int offset = x * 4;
        uint8_t r = 0;
        uint8_t g = 0;
        uint8_t b = 0;
        if (input.format == VP_PIXEL_RGBA8888) {
          r = row[offset];
          g = row[offset + 1];
          b = row[offset + 2];
        } else {
          b = row[offset];
          g = row[offset + 1];
          r = row[offset + 2];
        }
        dst[x] = static_cast<uint8_t>((299 * r + 587 * g + 114 * b) / 1000);
      }
    }
  }

  out->width = input.width;
  out->height = input.height;
  out->stride = input.width;
  out->data = buffer.data();
  return true;
}

class AnalyzerImpl {
 public:
  explicit AnalyzerImpl(const VpConfig& config)
      : config_(config) {
    metrics_.push_back({VP_METRIC_SHARPNESS, threshold_for_metric(config_, VP_METRIC_SHARPNESS),
                        compute_sharpness_wrapper});
    metrics_.push_back({VP_METRIC_EXPOSURE, threshold_for_metric(config_, VP_METRIC_EXPOSURE),
                        compute_exposure_wrapper});
    metrics_.push_back({VP_METRIC_MOTION_BLUR, threshold_for_metric(config_, VP_METRIC_MOTION_BLUR),
                        compute_motion_blur_wrapper});
    metrics_.push_back(
        {VP_METRIC_NOISE, threshold_for_metric(config_, VP_METRIC_NOISE), compute_noise_wrapper});
    metrics_.push_back({VP_METRIC_PERSON_BLUR, threshold_for_metric(config_, VP_METRIC_PERSON_BLUR),
                        compute_person_blur_wrapper});
  }

  int analyze(const VpFrame* frames, int frame_count, VpAggregateResult* out_result) {
    if (!frames || frame_count <= 0 || !out_result) {
      return VP_ERR_INVALID_ARGUMENT;
    }

    int max_frames = config_.max_frames > 0 ? config_.max_frames : frame_count;
    int frames_to_process = std::min(frame_count, max_frames);
    if (frames_to_process <= 0) {
      return VP_ERR_INVALID_ARGUMENT;
    }

    std::vector<MetricAggregate> aggregates(metrics_.size());
    std::vector<uint8_t> current_gray;
    std::vector<uint8_t> previous_gray;
    GrayFrame previous_frame{};
    bool has_previous = false;

    for (int i = 0; i < frames_to_process; ++i) {
      GrayFrame frame{};
      if (!prepare_gray_frame(frames[i], current_gray, &frame)) {
        return VP_ERR_UNSUPPORTED;
      }

      GrayFrame* prev_ptr = has_previous ? &previous_frame : nullptr;
      for (size_t metric_index = 0; metric_index < metrics_.size(); ++metric_index) {
        float raw = metrics_[metric_index].compute(frame, prev_ptr);
        float score = normalize_score(raw, metrics_[metric_index].threshold);
        aggregates[metric_index].update(raw, score);
        if (config_.log_frame_details != 0) {
          std::fprintf(stderr, "vp_scoring frame=%d metric=%s score=%.6f raw=%.6f\n", i,
                       metric_id_to_string(metrics_[metric_index].id), score, raw);
        }
      }

      previous_gray.swap(current_gray);
      previous_frame = frame;
      previous_frame.data = previous_gray.data();
      has_previous = true;
    }

    if (!has_previous) {
      return VP_ERR_DECODE;
    }

    int item_count = static_cast<int>(metrics_.size());
    out_result->item_count = item_count;

    for (int i = 0; i < item_count; ++i) {
      const MetricDefinition& metric = metrics_[i];
      const MetricAggregate& agg = aggregates[i];

      float mean_raw = agg.sum_raw / static_cast<float>(agg.count);
      float mean_score = agg.sum_score / static_cast<float>(agg.count);

      out_result->mean[i].id = static_cast<int32_t>(metric.id);
      std::snprintf(out_result->mean[i].id_str, VP_METRIC_ID_MAX_LEN, "%s", metric_id_to_string(metric.id));
      out_result->mean[i].raw = mean_raw;
      out_result->mean[i].score = mean_score;

      out_result->worst[i].id = static_cast<int32_t>(metric.id);
      std::snprintf(out_result->worst[i].id_str, VP_METRIC_ID_MAX_LEN, "%s", metric_id_to_string(metric.id));
      out_result->worst[i].raw = agg.raw_at_min;
      out_result->worst[i].score = agg.min_score;
    }

    return VP_OK;
  }

 private:
  VpConfig config_;
  std::vector<MetricDefinition> metrics_;
};

} // namespace vp

struct VpAnalyzer {
  vp::AnalyzerImpl* impl;
};

void vp_default_config(VpConfig* config) {
  if (!config) {
    return;
  }
  config->max_frames = 300;
  config->fps = 5.0f;
  config->normalize = {360, 0};
  config->log_frame_details = 0;
  for (int i = 0; i < VP_MAX_ITEMS; ++i) {
    config->thresholds[i] = {0.0f, 0.0f};
  }
  config->thresholds[VP_METRIC_SHARPNESS] = {20.0f, 2.0f};
  config->thresholds[VP_METRIC_EXPOSURE] = {0.002f, 0.02f};
  config->thresholds[VP_METRIC_MOTION_BLUR] = {0.2f, 1.5f};
  config->thresholds[VP_METRIC_NOISE] = {0.001f, 0.01f};
  config->thresholds[VP_METRIC_PERSON_BLUR] = {20.0f, 2.0f};
}

VpAnalyzer* vp_create(const VpConfig* config) {
  if (!config) {
    return nullptr;
  }
  VpAnalyzer* analyzer = new (std::nothrow) VpAnalyzer();
  if (!analyzer) {
    return nullptr;
  }
  analyzer->impl = new (std::nothrow) vp::AnalyzerImpl(*config);
  if (!analyzer->impl) {
    delete analyzer;
    return nullptr;
  }
  return analyzer;
}

int vp_analyze_frames(VpAnalyzer* analyzer, const VpFrame* frames, int frame_count,
                      VpAggregateResult* out_result) {
  if (!analyzer || !analyzer->impl) {
    return VP_ERR_INVALID_ARGUMENT;
  }
  return analyzer->impl->analyze(frames, frame_count, out_result);
}

void vp_destroy(VpAnalyzer* analyzer) {
  if (!analyzer) {
    return;
  }
  delete analyzer->impl;
  analyzer->impl = nullptr;
  delete analyzer;
}
