#include <android/imagedecoder.h>
#include <android/bitmap.h> // For ANDROID_BITMAP_FORMAT_RGBA_8888 enum
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <cerrno>
#include <string>
#include <vector>
#include <android/log.h> // 引入 Android Log
#include <stdlib.h> // for malloc, free
#include <math.h> // for roundf
#include <string.h> // for memcpy

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp> // 用于 cv::cvtColor, cv::resize, cv::copyMakeBorder
#include <opencv2/core/types.hpp> // For cv::Size, cv::Scalar

// 定义 Log Tag 和 Log 宏
#define LOG_TAG "ImageProcessorNative"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__) // 可以添加 Debug 级别
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)

/**
 * @brief 使用 Android AImageDecoder 加载图像并返回 OpenCV Mat 对象。
 *
 * @param imagePath 图像文件的路径。
 * @param targetWidth 目标宽度。如果 <= 0，则使用原始宽度。
 * @param targetHeight 目标高度。如果 <= 0，则使用原始高度。
 * @return cv::Mat 包含 BGR 格式图像数据的 OpenCV Mat 对象。如果失败则返回空的 Mat。
 */
cv::Mat loadImageWithAndroidDecoder(const std::string& imagePath, int targetWidth = -1, int targetHeight = -1) {
    // 1. 打开文件
    int fd = open(imagePath.c_str(), O_RDONLY);
    if (fd < 0) {
        LOGE("Error opening file: %s - %s", imagePath.c_str(), strerror(errno));
        return cv::Mat(); // 返回空 Mat 表示错误
    }

    // 2. 创建 AImageDecoder
    AImageDecoder* decoder = nullptr;
    int result = AImageDecoder_createFromFd(fd, &decoder);
    // 立即关闭文件描述符，无论 AImageDecoder_createFromFd 是否成功
    close(fd);

    if (result != ANDROID_IMAGE_DECODER_SUCCESS) {
        LOGE("Error creating AImageDecoder: %d", result);
        return cv::Mat();
    }

    // 3. (可选) 设置目标尺寸
    bool useTargetSize = (targetWidth > 0 && targetHeight > 0);
    if (useTargetSize) {
        result = AImageDecoder_setTargetSize(decoder, targetWidth, targetHeight);
        if (result != ANDROID_IMAGE_DECODER_SUCCESS) {
            LOGE("Error setting target size (%dx%d): %d", targetWidth, targetHeight, result);
            AImageDecoder_delete(decoder);
            return cv::Mat();
        }
        LOGD("Target size set to %dx%d", targetWidth, targetHeight); // 添加调试日志
    }

    // 4. 获取图像头信息以确定最终解码尺寸
    const AImageDecoderHeaderInfo* headerInfo = AImageDecoder_getHeaderInfo(decoder);
     if (!headerInfo) {
         LOGE("Error getting image header info.");
         AImageDecoder_delete(decoder);
         return cv::Mat();
    }

    // 确定解码器将输出的实际宽度和高度
    int decodeWidth = AImageDecoderHeaderInfo_getWidth(headerInfo);
    int decodeHeight = AImageDecoderHeaderInfo_getHeight(headerInfo);
     LOGD("Original image size: %dx%d", decodeWidth, decodeHeight);

    // 如果设置了目标尺寸，AImageDecoder 会解码并缩放到该尺寸
    // AImageDecoder 会内部处理缩放，我们只需要根据是否设置 target size 确定最终 Mat 尺寸
    int finalWidth = useTargetSize ? targetWidth : decodeWidth;
    int finalHeight = useTargetSize ? targetHeight : decodeHeight;
     LOGD("Decoding to size: %dx%d", finalWidth, finalHeight);

    // AImageDecoder 通常解码为 RGBA_8888 格式
    AndroidBitmapFormat expectedFormat = ANDROID_BITMAP_FORMAT_RGBA_8888;
    // 注意：目前没有标准 API 来查询解码器 *将要* 输出的格式，但默认且推荐的是 RGBA_8888

    // 5. 准备用于存储解码像素的 OpenCV Mat
    // 创建一个 RGBA 格式的 Mat 来接收解码数据
    cv::Mat decodedMat(finalHeight, finalWidth, CV_8UC4); // 使用 final 尺寸

    // 6. 解码图像到 Mat 的数据缓冲区
    size_t stride = decodedMat.step; // 使用 cv::Mat 的步长
    size_t bufferSize = decodedMat.total() * decodedMat.elemSize(); // Mat 的总字节数

    result = AImageDecoder_decodeImage(decoder, decodedMat.data, stride, bufferSize);

    // 7. 清理 AImageDecoder 资源
    AImageDecoder_delete(decoder);

    if (result != ANDROID_IMAGE_DECODER_SUCCESS) {
        LOGE("Error decoding image: %d", result);
        return cv::Mat(); // 解码失败，返回空 Mat
    }

    // 8. 将颜色空间从 RGBA 转换为 BGR (OpenCV 常用的格式)
    cv::Mat bgrMat;
    cv::cvtColor(decodedMat, bgrMat, cv::COLOR_RGBA2BGR);

    LOGI("Successfully loaded image: %s (%dx%d)", imagePath.c_str(), bgrMat.cols, bgrMat.rows);

    return bgrMat; // 返回 BGR 格式的 Mat
}

// // --- 示例用法 ---
// // 需要在你的构建系统 (如 CMakeLists.txt) 中链接 ndk 的 jnigraphics 和 android 库，
// // 以及 OpenCV 库 (例如 opencv_core, opencv_imgproc)。
// int main(int argc, char** argv) {
//     if (argc < 2) {
//         std::cerr << "Usage: " << argv[0] << " <image_path> [width] [height]" << std::endl;
//         return 1;
//     }
//     std::string image_path = argv[1];
//     int width = -1;
//     int height = -1;
//     if (argc >= 4) {
//         width = std::stoi(argv[2]);
//         height = std::stoi(argv[3]);
//     }

//     cv::Mat image;
//     if (width > 0 && height > 0) {
//         std::cout << "Loading and scaling image to " << width << "x" << height << "..." << std::endl;
//         image = loadImageWithAndroidDecoder(image_path, width, height);
//     } else {
//         std::cout << "Loading image with original size..." << std::endl;
//         image = loadImageWithAndroidDecoder(image_path);
//     }

//     if (!image.empty()) {
//         std::cout << "Image loaded successfully (" << image.cols << "x" << image.rows << ")." << std::endl;
//         // 在这里可以使用加载的 image (cv::Mat)
//         // 例如，显示图像 (需要 opencv_highgui 模块):
//         // cv::imshow("Loaded Image", image);
//         // cv::waitKey(0);
//     } else {
//         std::cerr << "Failed to load image." << std::endl;
//         return 1;
//     }

//     return 0;
// }

// C 接口函数
extern "C" {

/**
 * @brief (优化版) 加载、预处理图像并返回浮点像素数据。
 *
 * 利用 AImageDecoder 进行缩放，并使用 OpenCV 优化操作。
 * 执行步骤：
 * 1. 使用 AImageDecoder 加载并缩放图像 (保持宽高比，适应目标尺寸)。
 * 2. 将缩放后的图像填充到目标尺寸 (黑色填充)。
 * 3. BGR -> RGB 转换。
 * 4. 转换为 Float 类型。
 * 5. 使用 OpenCV 函数进行向量化归一化。
 * 6. 返回包含 RGB 数据的 float* 缓冲区 (RGBRGBRGB...)。
 *
 * @param imagePath C 字符串形式的图像文件路径。
 * @param targetWidth 预处理后的目标宽度。
 * @param targetHeight 预处理后的目标高度。
 * @param means 包含 3 个元素的数组，表示 RGB 通道的均值 [mean_r, mean_g, mean_b]。
 * @param std_devs 包含 3 个元素的数组，表示 RGB 通道的标准差 [std_r, std_g, std_b]。
 *        注意：标准差不能为零。
 * @return float* 指向预处理后 RGB 数据的缓冲区。
 *         缓冲区大小为 targetWidth * targetHeight * 3 * sizeof(float)。
 *         失败时返回 nullptr。调用者负责使用 free() 释放。
 */
float* preprocessImage(const char* imagePath, int targetWidth, int targetHeight,
                         const float means[3], const float std_devs[3]) {

    if (!imagePath || targetWidth <= 0 || targetHeight <= 0 || !means || !std_devs) {
        LOGE("Invalid arguments provided to preprocessImage.");
        return nullptr;
    }
    if (std_devs[0] == 0.0f || std_devs[1] == 0.0f || std_devs[2] == 0.0f) {
        LOGE("Standard deviations cannot be zero.");
        return nullptr;
    }

    // 修改开始：重新实现保持比例缩放逻辑，不使用原来的 loadImageWithAndroidDecoder 调用
    // 打开文件并创建 AImageDecoder，以获取原始尺寸
    std::string imagePathStr(imagePath);
    int fd = open(imagePathStr.c_str(), O_RDONLY);
    if (fd < 0) {
        LOGE("Error opening file: %s - %s", imagePath, strerror(errno));
        return nullptr;
    }
    AImageDecoder* decoder = nullptr;
    int result = AImageDecoder_createFromFd(fd, &decoder);
    close(fd);
    if (result != ANDROID_IMAGE_DECODER_SUCCESS) {
        LOGE("Error creating AImageDecoder: %d", result);
        return nullptr;
    }
    const AImageDecoderHeaderInfo* headerInfo = AImageDecoder_getHeaderInfo(decoder);
    if (!headerInfo) {
        LOGE("Error getting image header info.");
        AImageDecoder_delete(decoder);
        return nullptr;
    }
    int origWidth = AImageDecoderHeaderInfo_getWidth(headerInfo);
    int origHeight = AImageDecoderHeaderInfo_getHeight(headerInfo);
    LOGD("Original image size: %dx%d", origWidth, origHeight);

    // 计算保持比例缩放的比例因子
    float scaleWidth = (float)targetWidth / origWidth;
    float scaleHeight = (float)targetHeight / origHeight;
    float scale = (scaleWidth < scaleHeight) ? scaleWidth : scaleHeight;
    int decodeWidth = (int)roundf(origWidth * scale);
    int decodeHeight = (int)roundf(origHeight * scale);
    LOGD("Decoding image with scale: %f, resulting in size: %dx%d", scale, decodeWidth, decodeHeight);

    // 设置解码目标尺寸为计算后尺寸
    result = AImageDecoder_setTargetSize(decoder, decodeWidth, decodeHeight);
    if (result != ANDROID_IMAGE_DECODER_SUCCESS) {
        LOGE("Error setting target size (%dx%d): %d", decodeWidth, decodeHeight, result);
        AImageDecoder_delete(decoder);
        return nullptr;
    }

    // 解码图像（默认格式为 RGBA_8888）
    cv::Mat decodedMat(decodeHeight, decodeWidth, CV_8UC4);
    size_t stride = decodedMat.step;
    size_t bufferSize = decodedMat.total() * decodedMat.elemSize();
    result = AImageDecoder_decodeImage(decoder, decodedMat.data, stride, bufferSize);
    AImageDecoder_delete(decoder);
    if (result != ANDROID_IMAGE_DECODER_SUCCESS) {
        LOGE("Error decoding image: %d", result);
        return nullptr;
    }

    // 使用解码后的 RGBA 图像 decodedMat 进行黑边填充，使尺寸达到目标尺寸
    cv::Mat paddedRgbaMat;
    if (decodedMat.cols == targetWidth && decodedMat.rows == targetHeight) {
        paddedRgbaMat = decodedMat; // 无需填充
        LOGD("Image already at target size, no padding needed.");
    } else {
        int padLeft = (targetWidth - decodedMat.cols) / 2;
        int padRight = targetWidth - decodedMat.cols - padLeft;
        int padTop = (targetHeight - decodedMat.rows) / 2;
        int padBottom = targetHeight - decodedMat.rows - padTop;
        // 注意：填充 RGBA 格式时，Scalar 需要 4 个值，这里用 (0, 0, 0, 0) 表示黑色透明
        cv::copyMakeBorder(decodedMat, paddedRgbaMat, padTop, padBottom, padLeft, padRight,
                           cv::BORDER_CONSTANT, cv::Scalar(0, 0, 0, 0));
        LOGD("Padded image to: %dx%d", paddedRgbaMat.cols, paddedRgbaMat.rows);
        if (paddedRgbaMat.cols != targetWidth || paddedRgbaMat.rows != targetHeight) {
            LOGW("Padding size mismatch (%dx%d), resizing to target %dx%d",
                 paddedRgbaMat.cols, paddedRgbaMat.rows, targetWidth, targetHeight);
            cv::resize(paddedRgbaMat, paddedRgbaMat, cv::Size(targetWidth, targetHeight)); // 如果需要调整大小，则仍然调整
        }
    }

    // 将 BGR 转换为 RGB
    cv::Mat rgbMat;
    cv::cvtColor(paddedRgbaMat, rgbMat, cv::COLOR_RGBA2RGB);

    // 4. 转换为 Float
    cv::Mat floatMat;
    rgbMat.convertTo(floatMat, CV_32FC3); // 转换到 0.0-255.0 范围

    // 5. 向量化归一化
    // 注意 mean 和 std_devs 数组是 RGB 顺序
    cv::Scalar meanScalar(means[0], means[1], means[2]);
    cv::Scalar stdDevScalar(std_devs[0], std_devs[1], std_devs[2]);

    cv::subtract(floatMat, meanScalar, floatMat); // floatMat = floatMat - meanScalar
    cv::divide(floatMat, stdDevScalar, floatMat); // floatMat = floatMat / stdDevScalar

    // 6. 分配内存并将数据复制到输出缓冲区
    size_t dataSize = (size_t)targetWidth * targetHeight * 3;
    size_t bufferSizeBytes = dataSize * sizeof(float);
    float* outputData = (float*)malloc(bufferSizeBytes);
    if (!outputData) {
        LOGE("Failed to allocate memory for output data (%zu bytes)", bufferSizeBytes);
        return nullptr;
    }

    // 尝试使用 memcpy (如果内存连续)
    if (floatMat.isContinuous()) {
        memcpy(outputData, floatMat.data, bufferSizeBytes);
        LOGD("Used memcpy for continuous Mat data transfer.");
    } else {
        LOGW("Mat data is not continuous, falling back to row-by-row copy.");
        size_t rowSize = (size_t)targetWidth * 3 * sizeof(float);
        uint8_t* outPtr = reinterpret_cast<uint8_t*>(outputData);
        for (int y = 0; y < targetHeight; ++y) {
            memcpy(outPtr + y * rowSize, floatMat.ptr<uint8_t>(y), rowSize);
        }
        // 或者，更慢的逐元素循环（作为最终备选）
        // float* matPtr = floatMat.ptr<float>(0);
        // size_t outputIndex = 0;
        // for (int y = 0; y < targetHeight; ++y) {
        //     for (int x = 0; x < targetWidth; ++x) {
        //         outputData[outputIndex++] = matPtr[y * floatMat.step1(0) + x * 3 + 0]; // R
        //         outputData[outputIndex++] = matPtr[y * floatMat.step1(0) + x * 3 + 1]; // G
        //         outputData[outputIndex++] = matPtr[y * floatMat.step1(0) + x * 3 + 2]; // B
        //     }
        // }
    }

    LOGI("Successfully preprocessed image %s to %dx%d float buffer (optimized)", imagePath, targetWidth, targetHeight);
    return outputData;
}

} // extern "C"
