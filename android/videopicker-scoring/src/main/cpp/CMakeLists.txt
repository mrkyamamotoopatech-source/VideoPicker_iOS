cmake_minimum_required(VERSION 3.18)
project(vp_scoring_jni LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(vp_scoring_jni SHARED
  vp_jni.cpp
  ../../../../../../core/src/vp_analyzer.cpp
  ../../../../../../core/src/vp_ffmpeg_decoder.cpp
  ../../../../../../core/src/vp_metrics.cpp
)

target_include_directories(vp_scoring_jni PRIVATE
  ../../../../../../core/include
  ../../../../../../core/src
)

target_link_libraries(vp_scoring_jni
  avformat
  avcodec
  swscale
  log
)
