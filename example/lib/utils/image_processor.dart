// ignore_for_file: avoid_print

import 'dart:io';
import 'package:opencv_core/opencv.dart' as cv;

/// 图像处理工具类，提供图像预处理和其他图像处理功能
class ImageProcessor {
  /// 预处理图像为分类器需要的格式
  /// [imageFile] 输入图像文件
  /// [targetSize] 目标尺寸
  /// 返回处理后的图像数据
  static Future<List<double>> preprocessImageForClassification(
    File imageFile,
    int targetSize,
  ) async {
    // 使用OpenCV加载图像
    final bytes = await imageFile.readAsBytes();
    cv.Mat imageMat = cv.imdecode(bytes, cv.IMREAD_COLOR);
    print(
      "图像尺寸: ${imageMat.cols} x ${imageMat.rows}, 通道数: ${imageMat.channels}",
    );

    // 图像预处理: 转换为RGB
    cv.Mat rgbMat;
    if (imageMat.channels == 4) {
      // RGBA图像，转换为RGB
      rgbMat = await cv.cvtColorAsync(imageMat, cv.COLOR_BGRA2BGR);
    } else if (imageMat.channels == 1) {
      // 灰度图，转换为RGB
      rgbMat = await cv.cvtColorAsync(imageMat, cv.COLOR_GRAY2BGR);
    } else {
      rgbMat = imageMat.clone();
    }

    // 图像填充为正方形
    int width = rgbMat.cols;
    int height = rgbMat.rows;
    cv.Mat squareImage;

    if (height > width) {
      // 高大于宽，需要在左右添加填充
      int diff = height - width;
      int padLeft = diff ~/ 2;
      int padRight = diff - padLeft;

      // 创建边界填充
      squareImage = cv.copyMakeBorder(
        rgbMat,
        0,
        0,
        padLeft,
        padRight,
        cv.BORDER_CONSTANT,
        value: cv.Scalar.all(255), // 白色填充
      );
    } else if (width > height) {
      // 宽大于高，需要在上下添加填充
      int diff = width - height;
      int padTop = diff ~/ 2;
      int padBottom = diff - padTop;

      // 创建边界填充
      squareImage = cv.copyMakeBorder(
        rgbMat,
        padTop,
        padBottom,
        0,
        0,
        cv.BORDER_CONSTANT,
        value: cv.Scalar.all(255), // 白色填充
      );
    } else {
      // 已经是正方形
      squareImage = rgbMat.clone();
    }

    // 调整尺寸到目标尺寸
    cv.Mat resizedImage = cv.resize(squareImage, (targetSize, targetSize));

    cv.Mat floatImage = resizedImage.convertTo(cv.MatType.CV_32FC3);

    // bgr2rgb
    cv.Mat rgbImage = cv.cvtColor(floatImage, cv.COLOR_BGR2RGB);

    // 转换为List<double>
    List<double> inputData = [];
    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {
        cv.Vec3f pixel = rgbImage.at(y, x);
        inputData.addAll([pixel.val1, pixel.val2, pixel.val3]);
      }
    }

    // 释放临时Mat对象，避免内存泄漏
    imageMat.dispose();
    rgbMat.dispose();
    squareImage.dispose();
    resizedImage.dispose();
    floatImage.dispose();
    rgbImage.dispose();

    return inputData;
  }

  /// 预处理图像为提取器需要的格式，包含标准化处理
  /// [imageFile] 输入图像文件
  /// [targetSize] 目标尺寸
  /// [mean] 均值
  /// [std] 标准差
  /// 返回处理后的图像数据
  static Future<List<double>> preprocessImageForExtractor(
    File imageFile,
    int targetSize,
    List<double> mean,
    List<double> std,
  ) async {
    // 使用OpenCV加载图像
    final bytes = await imageFile.readAsBytes();
    cv.Mat imageMat = cv.imdecode(bytes, cv.IMREAD_COLOR);
    print(
      "图像尺寸: ${imageMat.cols} x ${imageMat.rows}, 通道数: ${imageMat.channels}",
    );

    // 图像预处理: 转换为RGB
    cv.Mat rgbMat;
    if (imageMat.channels == 4) {
      // RGBA图像，转换为RGB
      rgbMat = await cv.cvtColorAsync(imageMat, cv.COLOR_BGRA2BGR);
    } else if (imageMat.channels == 1) {
      // 灰度图，转换为RGB
      rgbMat = await cv.cvtColorAsync(imageMat, cv.COLOR_GRAY2BGR);
    } else {
      rgbMat = imageMat.clone();
    }

    // 图像填充为正方形
    int width = rgbMat.cols;
    int height = rgbMat.rows;
    cv.Mat squareImage;

    if (height > width) {
      // 高大于宽，需要在左右添加填充
      int diff = height - width;
      int padLeft = diff ~/ 2;
      int padRight = diff - padLeft;

      // 创建边界填充
      squareImage = cv.copyMakeBorder(
        rgbMat,
        0,
        0,
        padLeft,
        padRight,
        cv.BORDER_CONSTANT,
        value: cv.Scalar.all(255), // 白色填充
      );
    } else if (width > height) {
      // 宽大于高，需要在上下添加填充
      int diff = width - height;
      int padTop = diff ~/ 2;
      int padBottom = diff - padTop;

      // 创建边界填充
      squareImage = cv.copyMakeBorder(
        rgbMat,
        padTop,
        padBottom,
        0,
        0,
        cv.BORDER_CONSTANT,
        value: cv.Scalar.all(255), // 白色填充
      );
    } else {
      // 已经是正方形
      squareImage = rgbMat.clone();
    }

    // 调整尺寸到目标尺寸
    cv.Mat resizedImage = cv.resize(squareImage, (targetSize, targetSize));

    cv.Mat floatImage = resizedImage.convertTo(cv.MatType.CV_32FC3);

    // bgr2rgb
    cv.Mat rgbImage = cv.cvtColor(floatImage, cv.COLOR_BGR2RGB);

    // 转换为List<double>并进行标准化
    List<double> inputData = [];
    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {
        cv.Vec3f pixel = rgbImage.at(y, x);
        // 标准化
        inputData.addAll([
          (pixel.val1 / 255.0 - mean[0]) / std[0],
          (pixel.val2 / 255.0 - mean[1]) / std[1],
          (pixel.val3 / 255.0 - mean[2]) / std[2],
        ]);
      }
    }

    // 释放临时Mat对象，避免内存泄漏
    imageMat.dispose();
    rgbMat.dispose();
    squareImage.dispose();
    resizedImage.dispose();
    floatImage.dispose();
    rgbImage.dispose();

    return inputData;
  }
}
