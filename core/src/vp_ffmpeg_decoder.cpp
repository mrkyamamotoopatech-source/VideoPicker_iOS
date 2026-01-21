#include "vp_ffmpeg_decoder.h"

#include <algorithm>

namespace vp {

FfmpegDecoder::FfmpegDecoder()
    : format_context_(nullptr),
      codec_context_(nullptr),
      frame_(av_frame_alloc()),
      packet_(av_packet_alloc()),
      sws_context_(nullptr),
      video_stream_index_(-1) {}

FfmpegDecoder::~FfmpegDecoder() {
  if (sws_context_) {
    sws_freeContext(sws_context_);
  }
  if (codec_context_) {
    avcodec_free_context(&codec_context_);
  }
  if (format_context_) {
    avformat_close_input(&format_context_);
  }
  if (frame_) {
    av_frame_free(&frame_);
  }
  if (packet_) {
    av_packet_free(&packet_);
  }
}

int FfmpegDecoder::open(const char* path) {
  if (avformat_open_input(&format_context_, path, nullptr, nullptr) < 0) {
    return -1;
  }
  if (avformat_find_stream_info(format_context_, nullptr) < 0) {
    return -1;
  }

  for (unsigned int i = 0; i < format_context_->nb_streams; ++i) {
    if (format_context_->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
      video_stream_index_ = static_cast<int>(i);
      break;
    }
  }
  if (video_stream_index_ < 0) {
    return -1;
  }

  AVCodecParameters* codec_params = format_context_->streams[video_stream_index_]->codecpar;
  const AVCodec* codec = avcodec_find_decoder(codec_params->codec_id);
  if (!codec) {
    return -1;
  }

  codec_context_ = avcodec_alloc_context3(codec);
  if (!codec_context_) {
    return -1;
  }

  if (avcodec_parameters_to_context(codec_context_, codec_params) < 0) {
    return -1;
  }

  if (avcodec_open2(codec_context_, codec, nullptr) < 0) {
    return -1;
  }

  return 0;
}

int FfmpegDecoder::decode(float fps, int max_frames, const std::function<void(const DecodedFrame&)>& on_frame) {
  if (!format_context_ || !codec_context_) {
    return -1;
  }

  if (fps <= 0.0f) {
    fps = 5.0f;
  }
  double frame_interval = 1.0 / static_cast<double>(fps);
  double next_sample_time = 0.0;
  int sampled_frames = 0;

  AVRational time_base = format_context_->streams[video_stream_index_]->time_base;

  while (av_read_frame(format_context_, packet_) >= 0) {
    if (packet_->stream_index != video_stream_index_) {
      av_packet_unref(packet_);
      continue;
    }

    if (avcodec_send_packet(codec_context_, packet_) < 0) {
      av_packet_unref(packet_);
      return -1;
    }
    av_packet_unref(packet_);

    while (avcodec_receive_frame(codec_context_, frame_) == 0) {
      double pts_seconds = 0.0;
      if (frame_->best_effort_timestamp != AV_NOPTS_VALUE) {
        pts_seconds = frame_->best_effort_timestamp * av_q2d(time_base);
      }

      if (pts_seconds + 1e-6 < next_sample_time) {
        av_frame_unref(frame_);
        continue;
      }

      int width = frame_->width;
      int height = frame_->height;

      if (!sws_context_) {
        sws_context_ = sws_getContext(width, height, static_cast<AVPixelFormat>(frame_->format),
                                      width, height, AV_PIX_FMT_GRAY8, SWS_BILINEAR, nullptr, nullptr, nullptr);
        if (!sws_context_) {
          av_frame_unref(frame_);
          return -1;
        }
      }

      DecodedFrame decoded;
      decoded.width = width;
      decoded.height = height;
      decoded.stride = width;
      decoded.gray.resize(static_cast<size_t>(width * height));

      uint8_t* dest_data[4] = { decoded.gray.data(), nullptr, nullptr, nullptr };
      int dest_linesize[4] = { width, 0, 0, 0 };

      sws_scale(sws_context_, frame_->data, frame_->linesize, 0, height, dest_data, dest_linesize);

      on_frame(decoded);
      ++sampled_frames;
      next_sample_time += frame_interval;

      av_frame_unref(frame_);

      if (sampled_frames >= max_frames) {
        return 0;
      }
    }
  }

  return 0;
}

} // namespace vp
