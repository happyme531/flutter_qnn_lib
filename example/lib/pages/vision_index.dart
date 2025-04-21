// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_qnn_lib/qnn.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

import '../model_manager.dart';
import '../widgets/model_manager_widget.dart';
import '../settings_manager.dart';

import '../image_loader.dart';

class VisionIndexPage extends StatefulWidget {
  const VisionIndexPage({super.key});

  @override
  State<VisionIndexPage> createState() => _VisionIndexPageState();
}

class _VisionIndexPageState extends State<VisionIndexPage> {
  File? _image;
  bool _isProcessing = false;
  final ImagePicker _picker = ImagePicker();

  // QNN相关路径
  String _modelPath = '';
  String _customModelName = '';

  // 模型管理
  final ModelManager _modelManager = ModelManager();

  // 设置管理
  final SettingsManager _settingsManager = SettingsManager();

  // QNN实例
  Qnn? _qnnApp;
  bool _isQnnInitialized = false;
  bool _isInitializingQnn = false;

  // 处理结果
  List<double> _features = [];

  // 计时（毫秒）
  int _inputTime = 0;
  int _executeTime = 0;
  int _outputTime = 0;

  // 图像预处理参数
  static const int IMG_SIZE = 256;
  static const List<double> MEAN = [0.5, 0.5, 0.5];
  static const List<double> STD = [0.5, 0.5, 0.5];

  // logit scale and bias
  static const double LOGIT_SCALE = 109.76; // exp(4.69952)
  static const double LOGIT_BIAS = 0;

  @override
  void initState() {
    super.initState();
    _initModelManager();
    // 添加后端切换监听
    _settingsManager.addListener(_onBackendChanged);
  }

  // 初始化模型管理器
  Future<void> _initModelManager() async {
    try {
      await _modelManager.initialize();
      setState(() {});
    } catch (e) {
      print('初始化模型管理器失败: $e');
      _showSnackBar('初始化模型管理器失败: $e');
    }
  }

  // 当选择新模型时的处理
  Future<void> _onModelSelected(String? modelPath) async {
    // 如果传入null，表示需要卸载当前模型
    if (modelPath == null) {
      // 释放现有的QNN资源
      _releaseQnn();

      // 更新状态，清空模型路径
      setState(() {
        _modelPath = '';
        _customModelName = '';
        _isQnnInitialized = false;
      });

      _showSnackBar('模型已卸载');
      return;
    }

    if (_modelPath == modelPath) return;

    // 释放现有的QNN资源
    _releaseQnn();

    setState(() {
      _modelPath = modelPath;
      _customModelName = modelPath.split('/').last;
      _isInitializingQnn = true;
    });

    try {
      // 初始化QNN模型
      final success = await _initializeQnn();
      if (success) {
        _showSnackBar('模型加载成功: $_customModelName');
      } else {
        // 加载失败时清除模型路径
        setState(() {
          _modelPath = '';
          _customModelName = '';
        });
        _showSnackBar('模型加载失败: $_customModelName');
      }
    } catch (e) {
      // 发生错误时清除模型路径
      setState(() {
        _modelPath = '';
        _customModelName = '';
      });
      _showSnackBar('模型加载错误: $e');
    } finally {
      setState(() {
        _isInitializingQnn = false;
      });
    }
  }

  // 选择图片
  Future<void> _getImage() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
    );

    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _features = [];
      });
    }
  }

  // 加载示例图片
  Future<void> _loadExampleImage() async {
    try {
      setState(() {
        _isProcessing = true;
      });

      // 从assets加载图片
      final ByteData data = await rootBundle.load('assets/example.jpg');
      final List<int> bytes = data.buffer.asUint8List();

      // 创建临时文件
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/example.jpg');
      await tempFile.writeAsBytes(bytes);

      setState(() {
        _image = tempFile;
        _features = [];
        _isProcessing = false;
      });

      _showSnackBar('已加载示例图片');
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      print('加载示例图片失败: $e');
      _showSnackBar('加载示例图片失败: $e');
    }
  }

  // 显示SnackBar的辅助方法
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // 后端切换处理
  void _onBackendChanged() {
    if (_modelPath.isNotEmpty) {
      // 先卸载当前模型
      _releaseQnn();
      // 更新模型状态
      _modelManager.unloadCurrentModel();
      // 重新初始化
      _onModelSelected(_modelPath);
    }
  }

  // 在不需要QNN时释放资源
  void _releaseQnn() {
    if (_qnnApp != null) {
      _qnnApp!.destroy();
      _qnnApp = null;
      _isQnnInitialized = false;
      print('QNN资源已释放');
    }
  }

  @override
  void dispose() {
    _releaseQnn();
    // 移除后端切换监听
    _settingsManager.removeListener(_onBackendChanged);
    super.dispose();
  }

  // 处理图像
  Future<void> _processImage() async {
    if (_image == null) return;

    setState(() {
      _isProcessing = true;
      _features = [];
    });

    try {
      // 确保QNN已初始化
      if (!_isQnnInitialized || _qnnApp == null) {
        final success = await _initializeQnn();
        if (!success) {
          setState(() {
            _isProcessing = false;
          });
          throw '无法初始化QNN模型';
        }
      }

      // // 图像预处理
      // // 使用OpenCV加载图像
      // final bytes = await _image!.readAsBytes();
      // cv.Mat imageMat = cv.imdecode(bytes, cv.IMREAD_COLOR);
      // print(
      //   "图像尺寸: ${imageMat.cols} x ${imageMat.rows}, 通道数: ${imageMat.channels}",
      // );

      // // 图像预处理: 转换为RGB
      // cv.Mat rgbMat;
      // if (imageMat.channels == 4) {
      //   // RGBA图像，转换为RGB
      //   rgbMat = await cv.cvtColorAsync(imageMat, cv.COLOR_BGRA2BGR);
      // } else if (imageMat.channels == 1) {
      //   // 灰度图，转换为RGB
      //   rgbMat = await cv.cvtColorAsync(imageMat, cv.COLOR_GRAY2BGR);
      // } else {
      //   rgbMat = imageMat.clone();
      // }

      // // 图像填充为正方形
      // int width = rgbMat.cols;
      // int height = rgbMat.rows;
      // cv.Mat squareImage;

      // if (height > width) {
      //   // 高大于宽，需要在左右添加填充
      //   int diff = height - width;
      //   int padLeft = diff ~/ 2;
      //   int padRight = diff - padLeft;

      //   // 创建边界填充
      //   squareImage = cv.copyMakeBorder(
      //     rgbMat,
      //     0,
      //     0,
      //     padLeft,
      //     padRight,
      //     cv.BORDER_CONSTANT,
      //     value: cv.Scalar.all(255), // 白色填充
      //   );
      // } else if (width > height) {
      //   // 宽大于高，需要在上下添加填充
      //   int diff = width - height;
      //   int padTop = diff ~/ 2;
      //   int padBottom = diff - padTop;

      //   // 创建边界填充
      //   squareImage = cv.copyMakeBorder(
      //     rgbMat,
      //     padTop,
      //     padBottom,
      //     0,
      //     0,
      //     cv.BORDER_CONSTANT,
      //     value: cv.Scalar.all(255), // 白色填充
      //   );
      // } else {
      //   // 已经是正方形
      //   squareImage = rgbMat.clone();
      // }

      // // 调整尺寸到 448x448 (根据C++代码)
      // cv.Mat resizedImage = cv.resize(squareImage, (IMG_SIZE, IMG_SIZE));

      // cv.Mat floatImage = resizedImage.convertTo(cv.MatType.CV_32FC3);

      // // bgr2rgb
      // cv.Mat rgbImage = cv.cvtColor(floatImage, cv.COLOR_BGR2RGB);

      // // 转换为List<double>并归一化
      // List<double> inputData = [];
      // for (int y = 0; y < IMG_SIZE; y++) {
      //   for (int x = 0; x < IMG_SIZE; x++) {
      //     cv.Vec3f pixel = rgbImage.at(y, x);
      //     // 归一化
      //     inputData.addAll([
      //       (pixel.val1 / 255.0 - MEAN[0]) / STD[0],
      //       (pixel.val2 / 255.0 - MEAN[1]) / STD[1],
      //       (pixel.val3 / 255.0 - MEAN[2]) / STD[2],
      //     ]);
      //   }
      // }

      // // 释放临时Mat对象，避免内存泄漏
      // imageMat.dispose();
      // rgbMat.dispose();
      // squareImage.dispose();
      // resizedImage.dispose();
      // floatImage.dispose();

      var inputData = ImageLoader.preprocessImagePointer(
        _image!.path,
        IMG_SIZE,
        IMG_SIZE,
        MEAN.map((e) => e * 255).toList(),
        STD.map((e) => e * 255).toList(),
      );

      // 创建上下文
      QnnStatus status = _qnnApp!.createContext();
      if (status != QnnStatus.QNN_STATUS_SUCCESS) {
        throw '创建QNN上下文失败: $status';
      }

      // 准备输入数据并执行推理
      final inputStartTime = DateTime.now();
      status = await _qnnApp!.loadFloatInputsFromPointersAsync(
        [inputData],
        [IMG_SIZE * IMG_SIZE * 3],
        0,
      );
      final inputEndTime = DateTime.now();
      _inputTime = inputEndTime.difference(inputStartTime).inMilliseconds;

      if (status != QnnStatus.QNN_STATUS_SUCCESS) {
        throw '加载输入数据失败: $status';
      }

      // 执行推理
      final executeStartTime = DateTime.now();
      status = await _qnnApp!.executeGraphsAsync();
      final executeEndTime = DateTime.now();
      _executeTime = executeEndTime.difference(executeStartTime).inMilliseconds;

      if (status != QnnStatus.QNN_STATUS_SUCCESS) {
        throw '执行推理失败: $status';
      }

      // 获取输出
      final outputStartTime = DateTime.now();
      List<List<double>> outputData = _qnnApp!.getFloatOutputs(0);
      final outputEndTime = DateTime.now();
      _outputTime = outputEndTime.difference(outputStartTime).inMilliseconds;

      if (outputData.isEmpty || outputData[1].isEmpty) {
        throw '获取输出失败';
      }

      // 应用LOGIT_SCALE和LOGIT_BIAS（如需要）
      _features = outputData[1];
      print('输出特征向量大小: ${_features.length}');

      // 释放QNN资源
      _qnnApp!.freeContext();

      // 释放输入数据
      ImageLoader.free(inputData);

      setState(() {
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      print('图像处理错误: $e');

      // 显示错误对话框
      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('处理失败'),
              content: Text('$e'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('确定'),
                ),
              ],
            ),
      );
    }
  }

  // 初始化QNN模型
  Future<bool> _initializeQnn() async {
    // 已初始化，直接返回成功
    if (_isQnnInitialized && _qnnApp != null) {
      return true;
    }

    try {
      // 检查模型和后端文件是否存在
      if (_modelPath.isEmpty || !File(_modelPath).existsSync()) {
        print('模型文件不存在: $_modelPath，请先选择有效的模型文件');
        _showSnackBar('模型文件不存在，请选择有效的模型文件');
        return false;
      }
      print('尝试初始化QNN...');

      // 添加延迟让弹窗有时间显示
      await Future.delayed(const Duration(milliseconds: 100));

      try {
        // 检查是否有缓存文件
        String? cachePath = await _modelManager.getModelCache(
          _modelPath,
          _settingsManager.backendType,
        );

        if (cachePath != null) {
          print('找到模型缓存文件: $cachePath');
          _showSnackBar('使用缓存加载模型，速度将更快');

          // 使用缓存文件创建QNN实例
          _qnnApp = await Qnn.createAsync(
            _settingsManager.backendType,
            cachePath,
          );
        } else {
          print('未找到缓存文件，使用原始模型');

          // 使用原始模型文件创建QNN实例
          _qnnApp = await Qnn.createAsync(
            _settingsManager.backendType,
            _modelPath,
          );

          if (_qnnApp != null) {
            // 生成缓存文件路径
            String? outputCachePath = await _modelManager.saveModelCache(
              _modelPath,
              _settingsManager.backendType,
            );

            if (outputCachePath != null) {
              print('正在保存模型缓存...');
              // 生成缓存文件名（不带后缀）
              final cacheFileName = path
                  .basename(outputCachePath)
                  .replaceAll('.bin', '');
              // 获取缓存目录
              final cacheDir = path.dirname(outputCachePath);

              // 保存二进制缓存
              final result = _qnnApp!.saveBinary(cacheDir, cacheFileName);
              if (result == QnnStatus.QNN_STATUS_SUCCESS) {
                print('模型缓存保存成功: $outputCachePath');
                _showSnackBar('模型缓存已保存，下次加载将更快');
              } else {
                print('模型缓存保存失败，状态码: $result');
              }
            }
          }
        }

        if (_qnnApp == null) {
          throw '创建QNN应用失败';
        }

        // 验证模型是否真正可用
        QnnStatus status = _qnnApp!.createContext();
        if (status != QnnStatus.QNN_STATUS_SUCCESS) {
          throw '创建QNN上下文失败: $status';
        }
        _qnnApp!.freeContext();

        print('QNN初始化成功');
        _isQnnInitialized = true;
        return true;
      } catch (e) {
        print('QNN初始化失败: $e');
        _showSnackBar('QNN初始化失败: $e');
        _releaseQnn();
        return false;
      }
    } catch (e) {
      print('初始化错误: $e');
      _showSnackBar('QNN初始化错误: $e');
      _releaseQnn();
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(title: const Text('视觉特征提取'), centerTitle: true),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '基于QNN的视觉特征提取示例',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                // 使用模型管理器组件
                ModelManagerWidget(
                  onModelSelected: _onModelSelected,
                  currentModelPath: _modelPath,
                  taskType: 'vision_encoder',
                ),

                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: _isInitializingQnn ? null : _getImage,
                      child: const Text('选择图片'),
                    ),
                    ElevatedButton(
                      onPressed: _isInitializingQnn ? null : _loadExampleImage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                      child: const Text('加载示例'),
                    ),
                    ElevatedButton(
                      onPressed:
                          _image == null || _isProcessing || _isInitializingQnn
                              ? null
                              : _processImage,
                      child:
                          _isProcessing
                              ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.0,
                                ),
                              )
                              : const Text('提取特征'),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // 显示选择的图像
                if (_image != null) ...[
                  const Text(
                    '选择的图像:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 250,
                    child: Image.file(_image!, fit: BoxFit.contain),
                  ),
                  const SizedBox(height: 20),
                ],

                // 显示推理结果
                if (_features.isNotEmpty) ...[
                  const Text(
                    '提取的特征向量:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),

                  // 显示计时信息
                  Card(
                    margin: const EdgeInsets.only(bottom: 12.0),
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '计算耗时统计:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('输入数据处理: $_inputTime 毫秒'),
                              Text('${_inputTime.toDouble() / 1000} 秒'),
                            ],
                          ),
                          SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('模型推理执行: $_executeTime 毫秒'),
                              Text('${_executeTime.toDouble() / 1000} 秒'),
                            ],
                          ),
                          SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('输出数据获取: $_outputTime 毫秒'),
                              Text('${_outputTime.toDouble() / 1000} 秒'),
                            ],
                          ),
                          Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '总推理耗时: ${_inputTime + _executeTime + _outputTime} 毫秒',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '${(_inputTime + _executeTime + _outputTime).toDouble() / 1000} 秒',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 显示特征向量信息
                  Card(
                    margin: const EdgeInsets.only(bottom: 12.0),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '特征向量信息:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Divider(),
                          Text('特征向量维度: ${_features.length}'),
                          SizedBox(height: 8),
                          Text('特征向量预览 (前10个值):'),
                          SizedBox(height: 8),
                          Container(
                            height: 100,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: EdgeInsets.all(8),
                            child: SingleChildScrollView(
                              child: Text(
                                _features
                                    .map((e) => e.toStringAsFixed(6))
                                    .join(', '),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // 全屏初始化指示器
        if (_isInitializingQnn)
          Container(
            color: Colors.black.withOpacity(0.4),
            child: Center(
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.0),
                ),
                child: Container(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        '正在初始化模型...',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '模型加载可能需要几秒钟时间，请耐心等待',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
