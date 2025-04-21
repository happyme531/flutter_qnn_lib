#pragma once

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
                         const float means[3], const float std_devs[3]);