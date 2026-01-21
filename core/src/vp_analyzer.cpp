#include "vp_analyzer.h"

#include <algorithm>
#include <cstdio>
#include <new>
#include <vector>

#include "vp_ffmpeg_decoder.h"
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

class AnalyzerImpl {
 public:
  explicit AnalyzerImpl(const VpConfig& config)
      : config_(config) {
    metrics_.push_back({VP_METRIC_SHARPNESS, config_.sharpness, compute_sharpness_wrapper});
    metrics_.push_back({VP_METRIC_EXPOSURE, config_.exposure, compute_exposure_wrapper});
    metrics_.push_back({VP_METRIC_MOTION_BLUR, config_.motion_blur, compute_motion_blur_wrapper});
    metrics_.push_back({VP_METRIC_NOISE, config_.noise, compute_noise_wrapper});
  }

  int analyze(const char* path, VpAggregateResult* out_result) {
    if (!path || !out_result) {
      return VP_ERR_INVALID_ARGUMENT;
    }

    FfmpegDecoder decoder;
    if (decoder.open(path) != 0) {
      return VP_ERR_FFMPEG;
    }

    std::vector<MetricAggregate> aggregates(metrics_.size());
    DecodedFrame previous_frame;
    bool has_previous = false;
    int processed_frames = 0;

    int decode_result = decoder.decode(config_.fps, config_.max_frames, [&](const DecodedFrame& decoded) {
      GrayFrame frame;
      frame.width = decoded.width;
      frame.height = decoded.height;
      frame.stride = decoded.stride;
      frame.data = decoded.gray.data();

      GrayFrame prev_frame;
      GrayFrame* prev_ptr = nullptr;
      if (has_previous) {
        prev_frame.width = previous_frame.width;
        prev_frame.height = previous_frame.height;
        prev_frame.stride = previous_frame.stride;
        prev_frame.data = previous_frame.gray.data();
        prev_ptr = &prev_frame;
      }

      for (size_t i = 0; i < metrics_.size(); ++i) {
        float raw = metrics_[i].compute(frame, prev_ptr);
        float score = normalize_score(raw, metrics_[i].threshold);
        aggregates[i].update(raw, score);
      }

      previous_frame = decoded;
      has_previous = true;
      ++processed_frames;
    });

    if (decode_result != 0) {
      return VP_ERR_DECODE;
    }

    if (processed_frames == 0) {
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
  config->fps = 5.0f;
  config->max_frames = 300;
  config->sharpness = {800.0f, 50.0f};
  config->exposure = {0.01f, 0.2f};
  config->motion_blur = {0.2f, 1.5f};
  config->noise = {0.02f, 0.15f};
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

int vp_analyze_video_file(VpAnalyzer* analyzer, const char* path, VpAggregateResult* out_result) {
  if (!analyzer || !analyzer->impl) {
    return VP_ERR_INVALID_ARGUMENT;
  }
  return analyzer->impl->analyze(path, out_result);
}

void vp_destroy(VpAnalyzer* analyzer) {
  if (!analyzer) {
    return;
  }
  delete analyzer->impl;
  analyzer->impl = nullptr;
  delete analyzer;
}
