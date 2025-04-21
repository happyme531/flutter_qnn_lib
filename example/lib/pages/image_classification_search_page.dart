// ignore_for_file: avoid_print

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_qnn_lib/qnn.dart';
import 'package:opencv_core/opencv.dart' as cv;
import 'package:path/path.dart' as path;
import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:app_settings/app_settings.dart';
import 'package:open_file/open_file.dart';
// 添加 image 库的导入

import '../model_manager.dart';
import '../widgets/model_manager_widget.dart';
import '../settings_manager.dart';
import '../database/image_tag_database.dart';

class ImageClassificationSearchPage extends StatefulWidget {
  const ImageClassificationSearchPage({super.key});

  @override
  State<ImageClassificationSearchPage> createState() =>
      _ImageClassificationSearchPageState();
}

class _ImageClassificationSearchPageState
    extends State<ImageClassificationSearchPage>
    with TickerProviderStateMixin {
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

  // 标签数据
  final List<Tag> _tags = [];

  // 处理状态
  bool _isProcessing = false;
  int _totalImages = 0;
  int _processedImages = 0;
  String _currentProcessingImage = '';
  bool _cancelProcessing = false; // 添加取消处理标志

  // 搜索相关
  String _searchKeyword = '';
  List<ImageTag> _searchResults = [];
  bool _isSearching = false;

  // 新增多标签搜索相关变量
  final List<String> _selectedTags = [];
  List<Map<String, dynamic>> _tagSuggestions = [];
  bool _showSuggestions = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // 添加匹配模式控制变量
  bool _matchAllTags = true; // true: 同时匹配所有标签, false: 匹配任一标签

  // 选项卡控制器
  late TabController _tabController;

  // 数据库实例
  final ImageTagDatabase _database = ImageTagDatabase.instance;

  // 统计信息
  List<Map<String, dynamic>> _tagStats = [];
  bool _isLoadingStats = false;

  // 新增：模型初始化状态消息
  String _initializationStatusMessage = '正在初始化模型...';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadTags();
    _initModelManager();
    // 添加后端切换监听
    _settingsManager.addListener(_onBackendChanged);
    // 加载标签统计信息
    _loadTagStats();

    // 添加搜索框监听
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(() {
      if (!_searchFocusNode.hasFocus) {
        setState(() {
          _showSuggestions = false;
        });
      }
    });
  }

  // 加载标签统计信息
  Future<void> _loadTagStats() async {
    if (mounted) {
      setState(() {
        _isLoadingStats = true;
      });
    }

    try {
      final stats = await _database.getTagStats();
      if (mounted) {
        setState(() {
          _tagStats = stats;
          _isLoadingStats = false;
        });
      }
    } catch (e) {
      print('加载标签统计失败: $e');
      if (mounted) {
        setState(() {
          _isLoadingStats = false;
        });
      }
    }
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

  // 处理单张图片
  Future<List<ImageTag>> _processImage(File imageFile) async {
    List<ImageTag> results = [];

    try {
      // 确保QNN已初始化
      if (!_isQnnInitialized || _qnnApp == null) {
        throw '模型尚未初始化';
      }

      // 1. 使用 image 库加载和解码图像
      final ByteData? decodedImage;
      final ui.Image? image;
      try {
        final bytes = await imageFile.readAsBytes();
        final ui.Codec codec = await ui.instantiateImageCodec(bytes);

        // 2. 获取图片的第一帧信息 (对于静态图片，通常只有一帧) - 这也是异步的
        final ui.FrameInfo frameInfo = await codec.getNextFrame();
        image = frameInfo.image;
        decodedImage = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
      } catch (e) {
        print('图像解码失败: $e');
        return [];
      }

      if (decodedImage == null) {
        print('图像解码失败 (使用 image 库)');
        return [];
      }

      // 2. 将解码后的图像数据转换为 OpenCV Mat 对象 (BGR格式)
      cv.Mat imageMat;

      final expectedLength = image.height * image.width * 4;
      if (decodedImage.lengthInBytes != expectedLength) {
        print('*** ERROR: imageBytes length mismatch! ***');
        print('Image dimensions: ${image.width} x ${image.height}');
        print('imageBytes actual length: ${decodedImage.lengthInBytes}');
        print('Expected length (H * W * 4): $expectedLength');

        // throw Exception(
        //   'Decoded image byte length (${imageBytes.length}) does not match expected length ($expectedLength)',
        // );
        return [];
      }
      imageMat = cv.Mat.fromList(
        image.height,
        image.width,
        cv.MatType.CV_8UC4,
        decodedImage.buffer.asUint8List(),
      );

      if (imageMat.isEmpty) {
        print('从解码数据创建Mat失败');
        return [];
      }
      // Linter 错误行，已删除: cv.Mat.fromList(rows, cols, type, data)

      // 3. 后续处理流程 (基本不变，因为 imageMat 已经是 BGR 格式)
      // 注意：不再需要之前的基于 channels 的 cvtColorAsync 判断

      // 图像填充为正方形
      int width = imageMat.cols;
      int height = imageMat.rows;
      cv.Mat squareImage;

      if (height > width) {
        // 高大于宽，需要在左右添加填充
        int diff = height - width;
        int padLeft = diff ~/ 2;
        int padRight = diff - padLeft;

        // 创建边界填充
        squareImage = await cv.copyMakeBorderAsync(
          imageMat, // 使用 imageMat
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
        squareImage = await cv.copyMakeBorderAsync(
          imageMat, // 使用 imageMat
          padTop,
          padBottom,
          0,
          0,
          cv.BORDER_CONSTANT,
          value: cv.Scalar.all(255), // 白色填充
        );
      } else {
        // 已经是正方形
        squareImage = imageMat.clone(); // 克隆 imageMat
      }
      imageMat.dispose(); // 释放原始 imageMat

      // 调整尺寸到 448x448
      const int DIM = 448;
      cv.Mat resizedImage = await cv.resizeAsync(squareImage, (DIM, DIM));
      squareImage.dispose(); // 释放填充后的图像
      cv.Mat rgbImage = await cv.cvtColorAsync(resizedImage, cv.COLOR_RGBA2RGB);

      // cv.Mat floatImage = await resizedImage.convertToAsync(
      //   cv.MatType.CV_32FC3,
      // );
      resizedImage.dispose(); // 释放调整尺寸后的图像

      // bgr2rgb (仍然需要，因为模型通常需要RGB输入)
      // floatImage.dispose(); // 释放浮点图像

      // 转换为List<double>
      // List<double> inputData = [];
      // for (int y = 0; y < DIM; y++) {
      //   for (int x = 0; x < DIM; x++) {
      //     // 注意：OpenCV Mat 的 at 方法是 (row, col)，对应 (y, x)
      //     cv.Vec3f pixel = rgbImage.at(y, x);
      //     inputData.addAll([pixel.val1, pixel.val2, pixel.val3]);
      //   }
      // }
      List<double> inputData =
          rgbImage
              .toList()
              .expand((row) => row)
              .map((e) => e.toDouble())
              .toList();

      // 释放最后的Mat对象
      // imageMat.dispose(); // 已在前面释放
      // squareImage.dispose(); // 已在前面释放
      // resizedImage.dispose(); // 已在前面释放
      // floatImage.dispose(); // 已在前面释放
      rgbImage.dispose(); // 释放最终的RGB图像

      //最终检查
      if (inputData[0] > 255 || inputData[1] > 255 || inputData[2] > 255) {
        throw '输入数据超出范围';
      }

      // 准备输入数据并执行推理
      QnnStatus status = await _qnnApp!.loadFloatInputsAsync([inputData], 0);
      if (status != QnnStatus.QNN_STATUS_SUCCESS) {
        throw '加载输入数据失败: $status';
      }

      // 执行推理
      status = await _qnnApp!.executeGraphsAsync();
      if (status != QnnStatus.QNN_STATUS_SUCCESS) {
        throw '执行推理失败: $status';
      }

      // 获取输出
      List<List<double>> outputData = await _qnnApp!.getFloatOutputsAsync(0);
      if (outputData.isEmpty || outputData[0].isEmpty) {
        throw '获取输出失败';
      }

      // 处理推理结果
      List<double> probs = outputData[0];
      const double THRESH = 0.4; // 阈值，参考C++代码

      // 构造结果
      final String imagePath = imageFile.path;
      final DateTime now = DateTime.now();

      for (int i = 0; i < probs.length; i++) {
        if (probs[i] > THRESH) {
          String tagName = '';

          // 查找标签名称
          if (i < _tags.length) {
            tagName = _tags[i].name;
          } else {
            tagName = 'tag_$i';
          }

          results.add(
            ImageTag(
              imagePath: imagePath,
              tagId: i,
              tagName: tagName,
              probability: probs[i],
              taggedAt: now,
            ),
          );
        }
      }

      // // 释放QNN资源 (这里不应该释放，应该在dispose或不再需要时释放)
      // _qnnApp!.freeContext();

      return results;
    } catch (e, stacktrace) {
      // 添加 stacktrace 方便调试
      print('处理图像失败: $e');
      print('Stacktrace: $stacktrace'); // 打印堆栈信息
      return [];
    } finally {
      // 确保所有中间创建的 Mat 都被释放是一个好习惯，
      // 但在此函数内局部创建的 Mat 对象（如 imageMat, squareImage 等）
      // 已经在上面的逻辑中通过 dispose() 处理了。
    }
  }

  // 初始化QNN模型
  Future<bool> _initializeQnn() async {
    // 已初始化，直接返回成功
    if (_isQnnInitialized && _qnnApp != null) {
      return true;
    }

    // 确保模型路径有效
    if (_modelPath.isEmpty || !File(_modelPath).existsSync()) {
      print('模型文件不存在: $_modelPath，请先选择有效的模型文件');
      if (mounted) {
        setState(() {
          _initializationStatusMessage = '错误：模型文件不存在';
        });
        _showSnackBar('模型文件不存在，请选择有效的模型文件');
      }
      return false;
    }

    if (mounted) {
      setState(() {
        _isInitializingQnn = true; // 确保在开始时设置为 true
        _initializationStatusMessage = '开始初始化 QNN...';
      });
    }
    print('尝试初始化QNN...');
    final QnnBackendType backendType = _settingsManager.backendType;
    String? loadedFromPath; // 记录实际加载的路径 (模型或缓存)
    bool triedSavingCache = false;

    try {
      if (mounted) {
        setState(() {
          _initializationStatusMessage = '检查模型缓存...';
        });
      }
      // 1. 尝试获取并检查缓存文件
      String? expectedCachePath = await _modelManager.getModelCache(
        _modelPath,
        backendType,
      );

      // 2. 尝试从缓存加载
      if (expectedCachePath != null) {
        // getModelCache 已经检查了文件存在性
        print('找到并尝试从缓存加载: $expectedCachePath');
        if (mounted) {
          setState(() {
            _initializationStatusMessage = '从缓存加载模型...';
          });
        }
        _showSnackBar('使用缓存加载模型...'); // 保留 SnackBar 提示
        try {
          _qnnApp = await Qnn.createAsync(
            backendType,
            expectedCachePath, // 直接使用存在的缓存路径
          );
          if (_qnnApp != null) {
            loadedFromPath = expectedCachePath;
            print('从缓存加载成功');
          } else {
            print('从缓存 $expectedCachePath 加载失败，将尝试从原始模型加载');
            if (mounted) {
              setState(() {
                _initializationStatusMessage = '缓存加载失败，尝试原始模型...';
              });
            }
            // 清理可能存在的无效缓存文件？ (可选)
            try {
              await File(expectedCachePath).delete();
              print('已删除无效的缓存文件: $expectedCachePath');
            } catch (_) {}
          }
        } catch (e) {
          print('从缓存 $expectedCachePath 加载时出错: $e，将尝试从原始模型加载');
          if (mounted) {
            setState(() {
              _initializationStatusMessage = '缓存加载出错，尝试原始模型...';
            });
          }
          // 清理可能存在的无效缓存文件？ (可选)
          try {
            await File(expectedCachePath).delete();
            print('已删除加载出错的缓存文件: $expectedCachePath');
          } catch (_) {}
          _qnnApp = null; // 确保 qnnApp 为 null
        }
      } else {
        print('未找到有效的缓存文件，将从原始模型加载: $_modelPath');
        if (mounted) {
          setState(() {
            _initializationStatusMessage = '未找到缓存，从原始模型加载...';
          });
        }
      }

      // 3. 如果从缓存加载失败或未找到缓存，则从原始模型加载
      if (_qnnApp == null) {
        print('正在从原始模型文件加载: $_modelPath');
        if (mounted) {
          setState(() {
            _initializationStatusMessage = '加载原始模型文件...';
          });
        }
        _showSnackBar('首次加载模型，可能需要一些时间...');
        _qnnApp = await Qnn.createAsync(backendType, _modelPath);
        if (_qnnApp != null) {
          loadedFromPath = _modelPath;
          print('从原始模型加载成功');

          // 4. 尝试保存缓存
          // 获取完整的预期缓存路径
          String targetCachePath = await _modelManager.getModelCachePath(
            _modelPath,
            backendType,
          );
          // 从完整路径推断目录和基本文件名
          String outputCacheDir = path.dirname(targetCachePath);
          String cacheFileNameWithoutExt = path.basenameWithoutExtension(
            targetCachePath,
          );

          if (mounted) {
            setState(() {
              _initializationStatusMessage = '尝试保存模型缓存...';
            });
          }
          print(
            '尝试保存模型缓存到目录: $outputCacheDir 文件名: $cacheFileNameWithoutExt.bin',
          );
          triedSavingCache = true;

          // 确保目录存在
          try {
            final dir = Directory(outputCacheDir);
            if (!await dir.exists()) {
              await dir.create(recursive: true);
            }
          } catch (e) {
            print('创建缓存目录失败: $e');
            // 可以选择不继续保存，或者让 saveBinary 尝试处理
          }

          // 执行保存 (注意：saveBinary 是同步的，但这里放在 async 函数中没问题)
          // 如果需要异步保存，QNN库需要提供异步接口
          final result = _qnnApp!.saveBinary(
            outputCacheDir,
            cacheFileNameWithoutExt,
          );

          if (result == QnnStatus.QNN_STATUS_SUCCESS) {
            print('模型缓存保存成功: $targetCachePath');
            _showSnackBar('模型缓存已保存，下次加载将更快');
          } else {
            print('模型缓存保存失败，状态码: $result');
            _showSnackBar('模型缓存保存失败');
          }
        } else {
          // 这部分代码在之前的逻辑修改后，理论上不太可能执行了
          // 因为如果 createAsync 失败，会在下面的 catch 块中捕获
          print('从原始模型文件加载失败');
          if (mounted) {
            setState(() {
              _initializationStatusMessage = '错误：无法加载原始模型';
            });
          }
          // throw Exception('Failed to load model from $_modelPath'); // 或者直接抛出异常
        }
      }

      // 5. 检查最终结果
      if (_qnnApp == null) {
        // 提供更详细的错误信息
        String triedPaths = expectedCachePath ?? _modelPath;
        if (expectedCachePath != null && triedPaths != _modelPath) {
          triedPaths = '$expectedCachePath (缓存) 和 $_modelPath (原始)';
        }
        throw Exception('创建 QNN 实例失败 (尝试路径: $triedPaths)');
      }

      print('QNN 初始化成功 (从 $loadedFromPath 加载)');
      if (mounted) {
        setState(() {
          _isQnnInitialized = true;
          // 初始化成功后不再显示加载状态
          // _isInitializingQnn = false; // 移动到 finally 块
          // _initializationStatusMessage = '初始化成功'; // 可以选择不设置
        });
      }
      return true;
    } catch (e, stacktrace) {
      final errorMessage = 'QNN 初始化失败: $e';
      print('QNN 初始化过程中发生严重错误: $e');
      print('Stacktrace: $stacktrace');
      if (mounted) {
        setState(() {
          _initializationStatusMessage = errorMessage; // 在加载界面显示错误
        });
      }
      _showSnackBar(errorMessage); // 同时显示 SnackBar
      await _releaseQnn(); // 确保资源被释放
      return false;
    } finally {
      // 无论成功或失败，最后都结束初始化状态
      if (mounted) {
        setState(() {
          _isInitializingQnn = false;
        });
      }
    }
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

  // 显示SnackBar的辅助方法
  void _showSnackBar(String message) {
    if (!mounted) return; // 添加mounted检查，防止组件已卸载后使用context

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // 批量处理设备中的图片
  Future<void> _batchProcessImages() async {
    if (!_isQnnInitialized || _qnnApp == null) {
      _showSnackBar('请先加载模型');
      return;
    }

    // 重置取消状态
    _cancelProcessing = false;

    // 权限检查 - 修改权限请求逻辑
    final storageStatus = await Permission.photos.status;
    if (storageStatus.isDenied || storageStatus.isPermanentlyDenied) {
      // 显示请求权限的对话框
      await showDialog(
        context: context,
        builder:
            (BuildContext context) => AlertDialog(
              title: const Text('需要相册权限'),
              content: const Text('此功能需要访问您的相册才能批量处理图片，请在接下来的系统对话框中授予权限。'),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    if (storageStatus.isPermanentlyDenied) {
                      // 引导用户前往设置页面
                      await AppSettings.openAppSettings();
                    } else {
                      // 请求权限
                      await Permission.photos.request();
                      // 也尝试使用PhotoManager请求权限
                      await PhotoManager.openSetting();
                    }
                  },
                  child: const Text('去授权'),
                ),
              ],
            ),
      );

      // 再次检查权限
      final checkAgain = await Permission.photos.status;
      if (checkAgain.isDenied || checkAgain.isPermanentlyDenied) {
        _showSnackBar('未获得相册权限，无法继续');
        return;
      }
    }

    if (mounted) {
      setState(() {
        _isProcessing = true;
        _processedImages = 0;
        _totalImages = 0;
        _currentProcessingImage = '';
      });
    }

    try {
      // 使用PhotoManager请求权限
      final result = await PhotoManager.requestPermissionExtend();
      if (!result.hasAccess) {
        // 如果PhotoManager权限检查失败，尝试打开设置
        await PhotoManager.openSetting();

        // 再次检查权限
        final recheckResult = await PhotoManager.requestPermissionExtend();
        if (!recheckResult.isAuth) {
          if (mounted) {
            setState(() {
              _isProcessing = false;
            });
            _showSnackBar('无法访问相册，请在系统设置中授予权限');
          }
          return;
        }
      }

      // 获取所有资源
      final albums = await PhotoManager.getAssetPathList(onlyAll: true);
      if (albums.isEmpty) {
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
          _showSnackBar('未找到任何相册');
        }
        return;
      }

      final recents = albums.first;

      // 获取图片
      final assetCount = await recents.assetCountAsync;
      if (assetCount == 0) {
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
          _showSnackBar('相册为空');
        }
        return;
      }

      final recentAssets = await recents.getAssetListRange(
        start: 0,
        end: 9999999999,
      );

      if (mounted) {
        setState(() {
          _totalImages = recentAssets.length;
        });
      }

      // 处理每一张图片
      for (int i = 0; i < recentAssets.length; i++) {
        // 检查是否取消处理
        if (_cancelProcessing) {
          if (mounted) {
            _showSnackBar('已取消处理，共处理了 $_processedImages 张图片');
          }
          break;
        }

        if (!mounted) break;

        final asset = recentAssets[i];

        // 只处理图片
        if (asset.type != AssetType.image) continue;

        // 检查图片是否已处理
        final isProcessed = await _database.isImageProcessed(asset.id);
        if (isProcessed) {
          // 已处理，更新进度并跳过
          if (mounted) {
            setState(() {
              _processedImages++;
            });
          }
          continue;
        }

        try {
          // 获取文件
          File? file = await asset.file;
          if (file == null) continue;

          if (mounted) {
            setState(() {
              _currentProcessingImage = path.basename(file.path);
            });
          }

          // 处理图片
          print('开始处理图片: ${file.path}');
          final results = await _processImage(file);

          // 保存到数据库
          if (results.isNotEmpty) {
            // 更新图片路径为asset ID，便于后续查询
            final imageTags =
                results
                    .map(
                      (tag) => ImageTag(
                        imagePath: asset.id,
                        tagId: tag.tagId,
                        tagName: tag.tagName,
                        probability: tag.probability,
                        taggedAt: tag.taggedAt,
                      ),
                    )
                    .toList();

            await _database.insertTags(imageTags);
            await _database.markImageAsProcessed(asset.id);
          }
        } catch (e) {
          print('处理图片出错: ${asset.id}, 错误: $e');
        }

        // 更新进度
        if (mounted) {
          setState(() {
            _processedImages++;
          });
        }
      }

      // 处理完成后重新加载标签统计
      await _loadTagStats();

      if (mounted && !_cancelProcessing) {
        _showSnackBar('图片处理完成: $_processedImages / $_totalImages');
      }
    } catch (e) {
      print('批量处理错误: $e');
      _showSnackBar('批量处理出错: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _currentProcessingImage = '';
          _cancelProcessing = false; // 重置取消状态
        });
      }
    }
  }

  // 搜索框文本变化监听
  void _onSearchChanged() {
    setState(() {
      _searchKeyword = _searchController.text;
      _showSuggestions = _searchKeyword.isNotEmpty;
    });
    _updateTagSuggestions();
  }

  // 更新标签建议
  Future<void> _updateTagSuggestions() async {
    if (_searchKeyword.isEmpty) {
      setState(() {
        _tagSuggestions = [];
      });
      return;
    }

    try {
      // 从数据库获取匹配的标签
      final suggestions = await _database.getAllDistinctTags();

      // 过滤出匹配的标签，并排除已选择的标签
      final filtered =
          suggestions.where((tag) {
            final tagName = tag['tag_name'] as String;
            return tagName.toLowerCase().contains(
                  _searchKeyword.toLowerCase(),
                ) &&
                !_selectedTags.contains(tagName);
          }).toList();

      // 按相关性排序
      filtered.sort((a, b) {
        final aName = a['tag_name'] as String;
        final bName = b['tag_name'] as String;

        // 如果以关键词开头的排在前面
        if (aName.toLowerCase().startsWith(_searchKeyword.toLowerCase()) &&
            !bName.toLowerCase().startsWith(_searchKeyword.toLowerCase())) {
          return -1;
        }
        if (!aName.toLowerCase().startsWith(_searchKeyword.toLowerCase()) &&
            bName.toLowerCase().startsWith(_searchKeyword.toLowerCase())) {
          return 1;
        }

        // 否则按字母顺序排序
        return aName.compareTo(bName);
      });

      // 限制显示数量
      final limitedSuggestions = filtered.take(8).toList();

      if (mounted) {
        setState(() {
          _tagSuggestions = limitedSuggestions;
        });
      }
    } catch (e) {
      print('获取标签建议出错: $e');
    }
  }

  // 添加标签到选择列表
  void _addTag(String tagName) {
    if (!_selectedTags.contains(tagName)) {
      setState(() {
        _selectedTags.add(tagName);
        _searchController.clear();
        _showSuggestions = false;
        _tagSuggestions = [];
      });
      _searchImages();
    } else {
      setState(() {
        _searchController.clear();
        _showSuggestions = false;
        _tagSuggestions = [];
      });
    }
    _searchFocusNode.unfocus();
  }

  // 从选择列表中移除标签
  void _removeTag(String tagName) {
    setState(() {
      _selectedTags.remove(tagName);
    });
    _searchImages();
  }

  // 清空所有已选择的标签
  void _clearSelectedTags() {
    setState(() {
      _selectedTags.clear();
    });
    _searchImages();
  }

  // 按标签搜索图片
  Future<void> _searchImages() async {
    if (_selectedTags.isEmpty) {
      if (mounted) {
        setState(() {
          _searchResults = [];
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isSearching = true;
        _searchResults = [];
      });
    }

    try {
      List<ImageTag> allResults = [];

      // 对每个选择的标签进行搜索
      for (final tagName in _selectedTags) {
        final results = await _database.searchByTagName(tagName);
        allResults.addAll(results);
      }

      // 根据匹配模式进行筛选
      if (_matchAllTags && _selectedTags.length > 1) {
        // 同时匹配所有标签：对于每个图片路径，统计它匹配的标签数量
        final pathMatchCounts = <String, int>{};
        final pathToTag = <String, ImageTag>{};

        for (var result in allResults) {
          pathMatchCounts[result.imagePath] =
              (pathMatchCounts[result.imagePath] ?? 0) + 1;
          // 保存最新的标签（如果有多个标签匹配同一图片，简单起见取最后一个）
          pathToTag[result.imagePath] = result;
        }

        // 只保留匹配了所有标签的图片
        final filteredResults =
            pathToTag.entries
                .where(
                  (entry) => pathMatchCounts[entry.key] == _selectedTags.length,
                )
                .map((entry) => entry.value)
                .toList();

        if (mounted) {
          setState(() {
            _searchResults = filteredResults;
            _isSearching = false;
          });
        }
      } else {
        // 匹配任一标签：简单去重即可
        final uniqueResults = <String, ImageTag>{};
        for (var result in allResults) {
          uniqueResults[result.imagePath] = result;
        }

        if (mounted) {
          setState(() {
            _searchResults = uniqueResults.values.toList();
            _isSearching = false;
          });
        }
      }
    } catch (e) {
      print('搜索出错: $e');
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
        _showSnackBar('搜索出错: $e');
      }
    }
  }

  // 加载图片缩略图
  Future<Uint8List?> _loadThumbnail(String assetId) async {
    try {
      final asset = await AssetEntity.fromId(assetId);
      if (asset == null) return null;

      final thumb = await asset.thumbnailDataWithSize(
        const ThumbnailSize(200, 200),
        quality: 80,
      );

      return thumb;
    } catch (e) {
      print('加载缩略图失败: $e');
      return null;
    }
  }

  // 使用其他应用打开图片
  Future<void> _openImageWithExternalApp(String assetId) async {
    try {
      // 显示加载指示器
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // 获取资源实体
      final asset = await AssetEntity.fromId(assetId);
      if (asset == null) {
        // 关闭加载指示器
        if (mounted) Navigator.of(context).pop();
        _showSnackBar('无法获取图片信息');
        return;
      }

      // 获取文件路径
      final file = await asset.file;
      if (file == null) {
        // 关闭加载指示器
        if (mounted) Navigator.of(context).pop();
        _showSnackBar('无法获取图片文件');
        return;
      }

      // 关闭加载指示器
      if (mounted) Navigator.of(context).pop();

      // 使用open_file打开图片
      final result = await OpenFile.open(file.path);

      if (result.type != ResultType.done) {
        _showSnackBar('打开图片失败: ${result.message}');
      }
    } catch (e) {
      // 关闭加载指示器
      if (mounted) Navigator.of(context).pop();
      print('打开图片出错: $e');
      _showSnackBar('打开图片失败: $e');
    }
  }

  // 取消批量处理
  void _cancelBatchProcessing() {
    if (_isProcessing) {
      setState(() {
        _cancelProcessing = true;
      });
      _showSnackBar('正在取消处理...');
    }
  }

  @override
  void dispose() {
    _releaseQnn();
    // 移除后端切换监听
    _settingsManager.removeListener(_onBackendChanged);
    _tabController.dispose();
    // 清理搜索相关资源
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            toolbarHeight: 0,
            // 使用 PreferredSize 控制 TabBar 高度
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(40.0), // 设置期望的高度
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.label, // 指示器跟随标签大小
                labelPadding: EdgeInsets.symmetric(
                  horizontal: 16.0,
                ), // 可以调整标签内边距
                tabs: const [
                  Tab(
                    height: 40.0, // 同时设置Tab的高度
                    child: Row(
                      // 使用 Row 排列图标和文本
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.batch_prediction, size: 18), // 缩小图标
                        SizedBox(width: 4), // 图标和文本间距
                        Text('批量处理', style: TextStyle(fontSize: 14)), // 调整字体大小
                      ],
                    ),
                  ),
                  Tab(
                    height: 40.0, // 同时设置Tab的高度
                    child: Row(
                      // 使用 Row 排列图标和文本
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search, size: 18), // 缩小图标
                        SizedBox(width: 4), // 图标和文本间距
                        Text('搜索图片', style: TextStyle(fontSize: 14)), // 调整字体大小
                      ],
                    ),
                  ),
                ],
              ),
            ),
            automaticallyImplyLeading: false,
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              // 第一个标签页 - 批量处理
              SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 使用模型管理器组件
                    ModelManagerWidget(
                      onModelSelected: _onModelSelected,
                      currentModelPath: _modelPath,
                      taskType: 'wd14_image_tagger',
                    ),

                    const SizedBox(height: 20),

                    // 批量处理按钮
                    ElevatedButton(
                      onPressed:
                          (_modelPath.isEmpty ||
                                  _isInitializingQnn ||
                                  _isProcessing)
                              ? null
                              : _batchProcessImages,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                      ),
                      child:
                          _isProcessing
                              ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.0,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    _cancelProcessing ? '正在取消...' : '处理中...',
                                  ),
                                ],
                              )
                              : const Text('开始批量处理图片'),
                    ),

                    // 显示处理进度
                    if (_isProcessing) ...[
                      const SizedBox(height: 20),
                      LinearProgressIndicator(
                        value:
                            _totalImages > 0
                                ? _processedImages / _totalImages
                                : 0,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('进度: $_processedImages / $_totalImages'),
                          const SizedBox(width: 16),
                          ElevatedButton.icon(
                            onPressed: _cancelBatchProcessing,
                            icon: const Icon(Icons.cancel, size: 16),
                            label: const Text('取消'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade100,
                              foregroundColor: Colors.red.shade900,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_currentProcessingImage.isNotEmpty)
                        Text(
                          '当前处理: $_currentProcessingImage',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                        ),
                    ],

                    const SizedBox(height: 20),
                    const Divider(),

                    // 标签统计信息
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '标签统计',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),

                        if (_isLoadingStats)
                          const Center(child: CircularProgressIndicator())
                        else if (_tagStats.isEmpty)
                          const Center(child: Text('暂无标签数据'))
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount:
                                _tagStats.length > 20
                                    ? 20
                                    : _tagStats.length, // 限制显示数量
                            itemBuilder: (context, index) {
                              final stat = _tagStats[index];
                              return ListTile(
                                title: Text(stat['tag_name'] ?? '未知标签'),
                                subtitle: Text('标签ID: ${stat['tag_id']}'),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${stat['image_count']} 张图片',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // 第二个标签页 - 搜索图片
              Padding(
                padding: const EdgeInsets.all(8.0), // 减小外层 Padding
                child: Column(
                  children: [
                    // --- 搜索控制区域 ---
                    Card(
                      elevation: 1, // 可以调整阴影
                      margin: const EdgeInsets.only(bottom: 8.0), // 添加底部间距
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0), // Card 内部 Padding
                        child: Column(
                          mainAxisSize: MainAxisSize.min, // 高度自适应内容
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 第一行：搜索框 (移除搜索按钮)
                            Row(
                              children: [
                                // 搜索框 (用 Expanded 包裹以填充空间)
                                Expanded(
                                  child: TextField(
                                    controller: _searchController,
                                    focusNode: _searchFocusNode,
                                    decoration: InputDecoration(
                                      hintText: '输入标签名称',
                                      prefixIcon: const Icon(Icons.search),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                      filled: true,
                                      fillColor: Colors.grey.shade100,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                      suffixIcon:
                                          _searchKeyword.isNotEmpty
                                              ? IconButton(
                                                icon: const Icon(
                                                  Icons.clear,
                                                  size: 20,
                                                ),
                                                onPressed: () {
                                                  _searchController.clear();
                                                },
                                              )
                                              : null,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            // 标签建议列表 (保持不变)
                            if (_showSuggestions && _tagSuggestions.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 8), // 调整间距
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.grey.withOpacity(0.2),
                                      spreadRadius: 1,
                                      blurRadius: 3,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: _tagSuggestions.length,
                                  physics: const NeverScrollableScrollPhysics(),
                                  separatorBuilder:
                                      (context, index) =>
                                          const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final suggestion = _tagSuggestions[index];
                                    return ListTile(
                                      dense: true,
                                      title: Text(suggestion['tag_name']),
                                      subtitle: Text(
                                        '标签ID: ${suggestion['tag_id']}',
                                      ),
                                      onTap: () {
                                        _addTag(suggestion['tag_name']);
                                      },
                                    );
                                  },
                                ),
                              ),

                            // 已选择的标签列表 和 清空/切换按钮 行
                            if (_selectedTags.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start, // 让按钮顶部与第一行标签对齐
                                  children: [
                                    // 已选标签 (用 Expanded 包裹)
                                    Expanded(
                                      child: Wrap(
                                        spacing: 8.0,
                                        runSpacing: 4.0,
                                        children:
                                            _selectedTags.map((tag) {
                                              return Chip(
                                                label: Text(tag),
                                                deleteIcon: const Icon(
                                                  Icons.cancel,
                                                  size: 18,
                                                ),
                                                onDeleted:
                                                    () => _removeTag(tag),
                                                backgroundColor:
                                                    Colors.blue.shade100,
                                                materialTapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                              );
                                            }).toList(),
                                      ),
                                    ),

                                    // 在标签右侧放置按钮 (用 Row 包裹)
                                    const SizedBox(width: 8), // 标签和按钮的间距
                                    Row(
                                      mainAxisSize:
                                          MainAxisSize.min, // 防止按钮占用过多空间
                                      children: [
                                        // 清空按钮
                                        IconButton(
                                          onPressed: _clearSelectedTags,
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                          tooltip: '清空所有标签',
                                          style: IconButton.styleFrom(
                                            backgroundColor: Colors.red.shade50,
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          padding:
                                              EdgeInsets.zero, // 移除默认 padding
                                          constraints:
                                              BoxConstraints(), // 移除默认大小限制
                                        ),

                                        // 匹配模式切换开关 (如果需要显示)
                                        if (_selectedTags.length > 1) ...[
                                          const SizedBox(
                                            width: 4,
                                          ), // 清空和切换按钮的间距
                                          Tooltip(
                                            message:
                                                _matchAllTags
                                                    ? '当前：同时匹配所有标签 (AND)'
                                                    : '当前：匹配任一标签 (OR)',
                                            child: InkWell(
                                              onTap: () {
                                                setState(() {
                                                  _matchAllTags =
                                                      !_matchAllTags;
                                                });
                                                _searchImages();
                                              },
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      _matchAllTags
                                                          ? Colors.green.shade50
                                                          : Colors
                                                              .orange
                                                              .shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                  border: Border.all(
                                                    color:
                                                        _matchAllTags
                                                            ? Colors
                                                                .green
                                                                .shade200
                                                            : Colors
                                                                .orange
                                                                .shade200,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      _matchAllTags
                                                          ? Icons.all_inclusive
                                                          : Icons.filter_alt,
                                                      size: 16,
                                                      color:
                                                          _matchAllTags
                                                              ? Colors
                                                                  .green
                                                                  .shade700
                                                              : Colors
                                                                  .orange
                                                                  .shade700,
                                                    ),
                                                    SizedBox(width: 4),
                                                    Text(
                                                      _matchAllTags
                                                          ? 'AND'
                                                          : 'OR',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color:
                                                            _matchAllTags
                                                                ? Colors
                                                                    .green
                                                                    .shade800
                                                                : Colors
                                                                    .orange
                                                                    .shade800,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // 搜索结果提示 (移到结果区域上方)
                    if (_selectedTags.isNotEmpty &&
                        _searchResults.isEmpty &&
                        !_isSearching)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24.0), // 调整间距
                        child: Text(
                          '点击"搜索"按钮查找匹配的图片',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),

                    // --- 搜索结果区域 ---
                    Expanded(
                      child:
                          _isSearching
                              ? const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 16),
                                    Text('正在搜索匹配的图片...'),
                                  ],
                                ),
                              )
                              : _searchResults.isEmpty &&
                                  _selectedTags.isNotEmpty
                              ? const Center(child: Text('未找到符合条件的图片'))
                              : Column(
                                children: [
                                  // 搜索结果信息 (保持不变)
                                  if (_searchResults.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 8.0,
                                      ),
                                      child: Row(
                                        children: [
                                          Text(
                                            '共找到 ${_searchResults.length} 张图片',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const Spacer(),
                                        ],
                                      ),
                                    ),

                                  // 图片网格 (保持不变)
                                  Expanded(
                                    child: GridView.builder(
                                      gridDelegate:
                                          const SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount:
                                                3, // 可以尝试增加列数以显示更多图片
                                            crossAxisSpacing: 6, // 调整间距
                                            mainAxisSpacing: 6, // 调整间距
                                            childAspectRatio: 0.75, // 可以调整宽高比
                                          ),
                                      itemCount: _searchResults.length,
                                      itemBuilder: (context, index) {
                                        final result = _searchResults[index];
                                        return FutureBuilder<Uint8List?>(
                                          future: _loadThumbnail(
                                            result.imagePath,
                                          ),
                                          builder: (context, snapshot) {
                                            if (snapshot.connectionState ==
                                                ConnectionState.waiting) {
                                              return const Card(
                                                child: Center(
                                                  child:
                                                      CircularProgressIndicator(),
                                                ),
                                              );
                                            }

                                            if (snapshot.data == null) {
                                              return const Card(
                                                child: Center(
                                                  child: Icon(Icons.error),
                                                ),
                                              );
                                            }

                                            return Card(
                                              clipBehavior: Clip.antiAlias,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Column(
                                                children: [
                                                  Expanded(
                                                    child: Stack(
                                                      fit: StackFit.expand,
                                                      children: [
                                                        InkWell(
                                                          onTap: () {
                                                            _openImageWithExternalApp(
                                                              result.imagePath,
                                                            );
                                                          },
                                                          child: Image.memory(
                                                            snapshot.data!,
                                                            fit: BoxFit.cover,
                                                            width:
                                                                double.infinity,
                                                          ),
                                                        ),
                                                        // 添加小图标提示点击可以打开
                                                        Positioned(
                                                          right: 8,
                                                          bottom: 8,
                                                          child: Container(
                                                            padding:
                                                                const EdgeInsets.all(
                                                                  4,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color: Colors
                                                                  .black
                                                                  .withOpacity(
                                                                    0.6,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    12,
                                                                  ),
                                                            ),
                                                            child: const Icon(
                                                              Icons.open_in_new,
                                                              color:
                                                                  Colors.white,
                                                              size: 16,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                          8.0,
                                                        ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          result.tagName,
                                                          style:
                                                              const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                          maxLines: 1,
                                                          overflow:
                                                              TextOverflow
                                                                  .ellipsis,
                                                        ),
                                                        Text(
                                                          '概率: ${(result.probability * 100).toStringAsFixed(1)}%',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color:
                                                                Colors
                                                                    .grey[600],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 全屏初始化指示器
        if (_isInitializingQnn)
          Container(
            color: Colors.black.withOpacity(0.5), // 加深一点背景
            child: Center(
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.0),
                ),
                child: Container(
                  padding: const EdgeInsets.all(24.0),
                  constraints: BoxConstraints(maxWidth: 300), // 限制卡片最大宽度
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 20),
                      Text(
                        _initializationStatusMessage, // 显示动态状态消息
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      // 可以在这里添加一个副标题或提示，如果需要
                      // const SizedBox(height: 8),
                      // Text(
                      //   '请耐心等待...',
                      //   style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      //   textAlign: TextAlign.center,
                      // ),
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

class Tag {
  final int tagId;
  final String name;

  Tag({required this.tagId, required this.name});

  @override
  String toString() => 'Tag(id: $tagId, name: $name)';
}
