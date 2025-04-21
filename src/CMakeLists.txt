cmake_minimum_required(VERSION 3.22)
project(flutter_qnn_wrapper)

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fno-omit-frame-pointer")

#导出compile_commands.json
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# 定义共享库的源文件
set(COMMON_LIB_SOURCES "Log/Logger.cpp"
                       "Log/LogUtils.cpp"
                       "PAL/src/linux/Directory.cpp"
                       "PAL/src/linux/DynamicLoading.cpp"
                       "PAL/src/linux/FileOp.cpp"
                       "PAL/src/linux/Path.cpp"
                       "PAL/src/common/GetOpt.cpp"
                       "PAL/src/common/StringOp.cpp"
                       "Utils/DataUtil.cpp"
                       "Utils/DynamicLoadUtil.cpp"
                       "Utils/IOTensor.cpp"
                       "Utils/QnnSampleAppUtils.cpp"
                       "QnnSampleApp.cpp"
                       "WrapperUtils/QnnWrapperUtils.cpp")

# 创建动态库
add_library(qnn_common SHARED ${COMMON_LIB_SOURCES})

# 添加qnn_wrapper库
add_library(qnn_wrapper SHARED "qnn_wrapper.cpp")

# Android NDK 编译设置
set(CMAKE_SYSTEM_NAME Android)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_ANDROID_ARCH_ABI arm64-v8a)

# 设置C++标准
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 设置编译选项
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fPIC -Wall -Wextra -Wno-unused-parameter")
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -g -O0")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3")

# 从环境变量获取QNN SDK路径
set(QNN_SDK_ROOT $ENV{QNN_SDK_ROOT})

include(TestConfig.cmake OPTIONAL)

target_include_directories(qnn_common PUBLIC CachingUtil
                                      Log
                                      PAL/include
                                      Utils
                                      WrapperUtils
                                      ${CMAKE_BINARY_DIR}
                                      ${QNN_SDK_ROOT}/include/QNN
                                      ${QNN_SDK_ROOT}/include
                                      ./)

# 为qnn_wrapper设置包含目录
target_include_directories(qnn_wrapper PUBLIC CachingUtil
                                      Log
                                      PAL/include
                                      Utils
                                      WrapperUtils
                                      ${CMAKE_BINARY_DIR}
                                      ${QNN_SDK_ROOT}/include/QNN
                                      ${QNN_SDK_ROOT}/include
                                      ./)

target_link_libraries(qnn_common PRIVATE log)

# 链接qnn_common库到qnn_wrapper
target_link_libraries(qnn_wrapper PRIVATE qnn_common log)

# 可选：设置输出名称和属性
set_target_properties(qnn_common PROPERTIES 
                      OUTPUT_NAME "qnn_common"
                      VERSION 1.0.0
                      SOVERSION 1)

set_target_properties(qnn_wrapper PROPERTIES 
                      OUTPUT_NAME "qnn_wrapper"
                      VERSION 1.0.0
                      SOVERSION 1)

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(qnn_wrapper PRIVATE "-Wl,-z,max-page-size=16384")
endif()

add_custom_command(
    TARGET qnn_wrapper POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy
            ${CMAKE_BINARY_DIR}/compile_commands.json
            ${CMAKE_SOURCE_DIR}/../compile_commands.json
    COMMENT "复制compile_commands.json到源代码目录"
)