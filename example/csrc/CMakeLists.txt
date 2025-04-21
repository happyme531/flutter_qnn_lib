cmake_minimum_required(VERSION 3.19)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_subdirectory(tokenizers-cpp)

# C API库
add_library(tokenizers_c_api
    SHARED
    tokenizers_c.cc
)

target_include_directories(tokenizers_c_api
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}
    PRIVATE
        ${TOKENIZERS_CPP_INCLUDE}
)

target_link_libraries(tokenizers_c_api
    PRIVATE
        tokenizers_cpp
        log
)

# OpenCV
set(OpenCV_DIR /home/zt/下载/OpenCV-android-sdk/sdk/native/jni/)
find_package(OpenCV REQUIRED)

add_library(image_loader
    SHARED
    image_loader.cpp
)

target_include_directories(image_loader
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}
    PRIVATE
        ${OpenCV_INCLUDE_DIRS}
)

target_link_libraries(image_loader
    PRIVATE
        ${OpenCV_LIBS}
        log
        jnigraphics
)

if (ANDROID)
  # Set minimum Android API level to 30
  set(CMAKE_SYSTEM_VERSION 30)

  # Support Android 15 16k page size
  target_link_options(tokenizers_c_api PRIVATE "-Wl,-z,max-page-size=16384")
  target_link_options(image_loader PRIVATE "-Wl,-z,max-page-size=16384")
endif()

add_custom_command(
    TARGET tokenizers_c_api POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy
            ${CMAKE_BINARY_DIR}/compile_commands.json
            ${CMAKE_SOURCE_DIR}/../compile_commands.json
    COMMENT "复制compile_commands.json到源代码目录"
)