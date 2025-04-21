// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_qnn_lib/qnn.dart';
import 'package:opencv_core/opencv.dart' as cv;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

import '../model_manager.dart';
import '../widgets/model_manager_widget.dart';
import '../settings_manager.dart';

class Tag {
  final int tagId;
  final String name;

  Tag({required this.tagId, required this.name});

  @override
  String toString() => 'Tag(id: $tagId, name: $name)';
}

class ImageClassificationPage extends StatefulWidget {
  const ImageClassificationPage({super.key});

  @override
  State<ImageClassificationPage> createState() =>
      _ImageClassificationPageState();
}

class _ImageClassificationPageState extends State<ImageClassificationPage> {
  File? _image;
  bool _isProcessing = false;
  final ImagePicker _picker = ImagePicker();

  // QNN相关路径
  String _modelPath = '';
  String _tagsPath = 'selected_tags.csv';
  String _customModelName = ''; // 存储当前加载模型的名称

  // 模型管理
  final ModelManager _modelManager = ModelManager();

  // 设置管理
  final SettingsManager _settingsManager = SettingsManager();

  // QNN实例
  Qnn? _qnnApp;
  bool _isQnnInitialized = false;
  bool _isInitializingQnn = false;

  // 处理结果
  List<Map<String, dynamic>> _results = [];

  // 计时（毫秒）
  int _inputTime = 0;
  int _executeTime = 0;
  int _outputTime = 0;

  // 标签数据
  final List<Tag> _tags = [];

  @override
  void initState() {
    super.initState();
    _loadTags();
    _initModelManager();
    // 添加后端切换监听
    _settingsManager.addListener(_onBackendChanged);
  }

  // 初始化模型管理器
  Future<void> _initModelManager() async {
    try {
      await _modelManager.initialize();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('初始化模型管理器失败: $e');
      if (mounted) {
        _showSnackBar('初始化模型管理器失败: $e');
      }
    }
  }

  // 当选择新模型时的处理
  Future<void> _onModelSelected(String? modelPath) async {
    // 如果传入null，表示需要卸载当前模型
    if (modelPath == null) {
      // 释放现有的QNN资源
      _releaseQnn();

      // 更新状态，清空模型路径
      if (mounted) {
        setState(() {
          _modelPath = '';
          _customModelName = '';
          _isQnnInitialized = false;
        });

        _showSnackBar('模型已卸载');
      }
      return;
    }

    if (_modelPath == modelPath) return;

    // 释放现有的QNN资源
    _releaseQnn();

    if (!mounted) return;

    setState(() {
      _modelPath = modelPath;
      _customModelName = modelPath.split('/').last;
      _isInitializingQnn = true;
    });

    try {
      // 初始化QNN模型
      final success = await _initializeQnn();
      if (!mounted) return;

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
      if (mounted) {
        setState(() {
          _modelPath = '';
          _customModelName = '';
        });
        _showSnackBar('模型加载错误: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isInitializingQnn = false;
        });
      }
    }
  }

  // 加载标签文件
  Future<void> _loadTags() async {
    try {
      // 从assets加载CSV文件
      final String content = await rootBundle.loadString('assets/$_tagsPath');

      // 清空之前的标签
      _tags.clear();

      // 手动解析CSV
      final lines = content.split('\n');

      // 跳过标题行
      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        final values = line.split(',');
        if (values.length >= 2) {
          try {
            final tagId = int.parse(values[0]);
            final name = values[1];
            _tags.add(Tag(tagId: tagId, name: name));
          } catch (e) {
            continue;
          }
        }
      }
      print('标签数量: ${_tags.length}');
    } catch (e) {
      // 加载失败时保持_tags为空
      _tags.clear();
      print('标签加载失败: $e');
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
        _results = [];
      });
    }
  }

  // 加载示例图片
  Future<void> _loadExampleImage() async {
    try {
      if (!mounted) return; // 添加mounted检查

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

      if (!mounted) return; // 添加mounted检查

      setState(() {
        _image = tempFile;
        _results = [];
        _isProcessing = false;
      });

      _showSnackBar('已加载示例图片');
    } catch (e) {
      if (mounted) {
        // 添加mounted检查
        setState(() {
          _isProcessing = false;
        });
        _showSnackBar('加载示例图片失败: $e');
      }
      print('加载示例图片失败: $e');
    }
  }

  // 显示SnackBar的辅助方法
  void _showSnackBar(String message) {
    if (!mounted) return; // 添加mounted检查，防止组件已卸载后使用context

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
  Future<void> _releaseQnn() async {
    if (_qnnApp != null) {
      await _qnnApp!.destroyAsync();
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

    if (!mounted) return; // 添加mounted检查

    setState(() {
      _isProcessing = true;
      _results = [];
    });

    try {
      // 确保QNN已初始化
      if (!_isQnnInitialized || _qnnApp == null) {
        final success = await _initializeQnn();
        if (!mounted) return; // 添加mounted检查

        if (!success) {
          setState(() {
            _isProcessing = false;
          });
          throw '无法初始化QNN模型';
        }
      }

      // 图像预处理
      // 使用OpenCV加载图像
      final bytes = await _image!.readAsBytes();
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

      // 调整尺寸到 448x448 (根据C++代码)
      const int DIM = 448;
      cv.Mat resizedImage = cv.resize(squareImage, (DIM, DIM));

      cv.Mat floatImage = resizedImage.convertTo(cv.MatType.CV_32FC3);

      // bgr2rgb
      cv.Mat rgbImage = cv.cvtColor(floatImage, cv.COLOR_BGR2RGB);

      // 转换为List<double>
      List<double> inputData = [];
      for (int y = 0; y < DIM; y++) {
        for (int x = 0; x < DIM; x++) {
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

      // 创建上下文
      QnnStatus status = _qnnApp!.createContext();
      if (status != QnnStatus.QNN_STATUS_SUCCESS) {
        throw '创建QNN上下文失败: $status';
      }

      // 准备输入数据并执行推理
      final inputStartTime = DateTime.now();
      status = await _qnnApp!.loadFloatInputsAsync([inputData], 0);
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
      List<List<double>> outputData = await _qnnApp!.getFloatOutputsAsync(0);
      final outputEndTime = DateTime.now();
      _outputTime = outputEndTime.difference(outputStartTime).inMilliseconds;

      if (outputData.isEmpty || outputData[0].isEmpty) {
        throw '获取输出失败';
      }

      // 处理推理结果
      List<double> probs = outputData[0];
      const double THRESH = 0.4; // 阈值，参考C++代码

      // 构造结果
      List<Map<String, dynamic>> results = [];
      for (int i = 0; i < probs.length; i++) {
        if (probs[i] > THRESH) {
          final Map<String, dynamic> result = {
            'tagId': i,
            'prob': probs[i],
            'name': '',
          };

          // 查找标签名称
          if (i < _tags.length) {
            result['name'] = _tags[i].name;
          }

          results.add(result);
        }
      }

      // 按概率排序
      results.sort(
        (a, b) => (b['prob'] as double).compareTo(a['prob'] as double),
      );

      // 释放QNN资源
      _qnnApp!.freeContext();

      if (!mounted) return; // 添加mounted检查

      // 更新UI显示结果
      setState(() {
        _results = results;
        _isProcessing = false;
      });
    } catch (e) {
      print('图像处理错误: $e');
      if (mounted) {
        // 添加mounted检查
        setState(() {
          _isProcessing = false;
        });
        _showSnackBar('图像处理失败: $e');
      }
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
        print('QNN初始化成功');
        _isQnnInitialized = true;
        return true;
      } catch (e) {
        print('QNN初始化失败: $e');
        _showSnackBar('QNN初始化失败: $e');
        await _releaseQnn();
        return false;
      }
    } catch (e) {
      print('初始化错误: $e');
      _showSnackBar('QNN初始化错误: $e');
      await _releaseQnn();
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(title: const Text('图像分类'), centerTitle: true),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '基于QNN的图像分类示例',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                // 使用模型管理器组件
                ModelManagerWidget(
                  onModelSelected: _onModelSelected,
                  currentModelPath: _modelPath,
                  taskType: 'wd14_image_tagger',
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
                              : const Text('识别图像'),
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
                if (_results.isNotEmpty) ...[
                  const Text(
                    '推理结果 (概率 > 0.4):',
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

                  ...List.generate(_results.length, (index) {
                    final result = _results[index];
                    final String name = result['name'] as String;
                    final int tagId = result['tagId'] as int;
                    final double prob = result['prob'] as double;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8.0),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                name.isNotEmpty
                                    ? '$tagId - $name'
                                    : '标签ID: $tagId',
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                            Text(
                              '概率: ${(prob * 100).toStringAsFixed(2)}%',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
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
                        '模型加载可能需要几秒钟时间，请耐心等待不要进行任何操作例如别点屏幕不然app可能会闪退',
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
