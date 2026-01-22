#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <vector>

#include "vp_analyzer.h"

int main(int argc, char** argv) {
  if (argc < 4) {
    std::fprintf(stderr, "Usage: %s <width> <height> <gray8_file>\n", argv[0]);
    return 1;
  }

  int width = std::atoi(argv[1]);
  int height = std::atoi(argv[2]);
  if (width <= 0 || height <= 0) {
    std::fprintf(stderr, "Invalid dimensions\n");
    return 1;
  }

  std::ifstream input(argv[3], std::ios::binary);
  if (!input) {
    std::fprintf(stderr, "Failed to open file: %s\n", argv[3]);
    return 1;
  }

  size_t size = static_cast<size_t>(width) * static_cast<size_t>(height);
  std::vector<uint8_t> buffer(size);
  input.read(reinterpret_cast<char*>(buffer.data()), static_cast<std::streamsize>(size));
  if (input.gcount() != static_cast<std::streamsize>(size)) {
    std::fprintf(stderr, "Expected %zu bytes, got %lld bytes\n", size,
                 static_cast<long long>(input.gcount()));
    return 1;
  }

  VpConfig config;
  vp_default_config(&config);

  VpAnalyzer* analyzer = vp_create(&config);
  if (!analyzer) {
    std::fprintf(stderr, "Failed to create analyzer\n");
    return 1;
  }

  VpFrame frame{};
  frame.width = width;
  frame.height = height;
  frame.stride_bytes = width;
  frame.format = VP_PIXEL_GRAY8;
  frame.data = buffer.data();

  VpAggregateResult result{};
  int rc = vp_analyze_frames(analyzer, &frame, 1, &result);
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
