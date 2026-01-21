#include <cstdio>

#include "vp_analyzer.h"

int main(int argc, char** argv) {
  if (argc < 2) {
    std::fprintf(stderr, "Usage: %s <video_file>\n", argv[0]);
    return 1;
  }

  VpConfig config;
  vp_default_config(&config);

  VpAnalyzer* analyzer = vp_create(&config);
  if (!analyzer) {
    std::fprintf(stderr, "Failed to create analyzer\n");
    return 1;
  }

  VpAggregateResult result{};
  int rc = vp_analyze_video_file(analyzer, argv[1], &result);
  if (rc != VP_OK) {
    std::fprintf(stderr, "Analyze failed: %d\n", rc);
    vp_destroy(analyzer);
    return 1;
  }

  std::printf("Mean results:\n");
  for (int i = 0; i < result.item_count; ++i) {
    std::printf("  %s score=%.3f raw=%.5f\n", result.mean[i].id_str, result.mean[i].score, result.mean[i].raw);
  }

  std::printf("Worst results:\n");
  for (int i = 0; i < result.item_count; ++i) {
    std::printf("  %s score=%.3f raw=%.5f\n", result.worst[i].id_str, result.worst[i].score, result.worst[i].raw);
  }

  vp_destroy(analyzer);
  return 0;
}
