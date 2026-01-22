cmake_minimum_required(VERSION 3.18)
project(vp_scoring_jni LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(vp_scoring_jni SHARED
  vp_jni.cpp
  ../../../../../../core/src/vp_analyzer.cpp
  ../../../../../../core/src/vp_metrics.cpp
)

find_package(OpenCV QUIET COMPONENTS core imgproc objdetect)
message(STATUS "OpenCV_FOUND=${OpenCV_FOUND}")

target_include_directories(vp_scoring_jni PRIVATE
  ../../../../../../core/include
  ../../../../../../core/src
)

if(OpenCV_FOUND)
  target_include_directories(vp_scoring_jni PRIVATE ${OpenCV_INCLUDE_DIRS})
  set(EXTRA_OPENCV_LIBS ${OpenCV_LIBS})
endif()

target_link_libraries(vp_scoring_jni
  log
  ${EXTRA_OPENCV_LIBS}
)
