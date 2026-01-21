#ifndef VP_FFMPEG_DECODER_H
#define VP_FFMPEG_DECODER_H

#include <functional>
#include <vector>

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
}

namespace vp {

struct DecodedFrame {
  int width;
  int height;
  int stride;
  std::vector<uint8_t> gray;
};

class FfmpegDecoder {
 public:
  FfmpegDecoder();
  ~FfmpegDecoder();

  int open(const char* path);
  int decode(float fps, int max_frames, float start_time_sec, const std::function<void(const DecodedFrame&)>& on_frame);

 private:
  AVFormatContext* format_context_;
  AVCodecContext* codec_context_;
  AVFrame* frame_;
  AVPacket* packet_;
  SwsContext* sws_context_;
  int video_stream_index_;
};

} // namespace vp

#endif // VP_FFMPEG_DECODER_H
