cmake_minimum_required(VERSION 3.18)
project(videopicker_scoring LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(vp_scoring STATIC
  src/vp_analyzer.cpp
  src/vp_metrics.cpp
)

find_package(OpenCV QUIET COMPONENTS core imgproc objdetect)
message(STATUS "OpenCV_FOUND=${OpenCV_FOUND}")

target_include_directories(vp_scoring PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_include_directories(vp_scoring PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/src
)

if(OpenCV_FOUND)
  target_include_directories(vp_scoring PRIVATE ${OpenCV_INCLUDE_DIRS})
  target_link_libraries(vp_scoring ${OpenCV_LIBS})
endif()

add_executable(vp_cli
  tools/vp_cli.cpp
)

target_link_libraries(vp_cli vp_scoring)
