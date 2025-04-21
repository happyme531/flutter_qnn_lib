import 'dart:io';
import 'package:flutter_qnn_lib/qnn_types.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';

// 导入设置管理器

// 模型信息类
class ModelInfo {
  final String name; // 模型文件名
  final String path; // 模型文件完整路径
  final String taskType; // 任务类型
  final DateTime addedTime; // 添加时间

  ModelInfo({
    required this.name,
    required this.path,
    required this.taskType,
    required this.addedTime,
  });

  // 从JSON创建ModelInfo
  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    return ModelInfo(
      name: json['name'] as String,
      path: json['path'] as String,
      taskType: json['taskType'] as String,
      addedTime: DateTime.parse(json['addedTime'] as String),
    );
  }

  // 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'path': path,
      'taskType': taskType,
      'addedTime': addedTime.toIso8601String(),
    };
  }
}

// 模型加载状态枚举
enum ModelLoadingState { notLoaded, loading, loaded, error }

class ModelManager extends ChangeNotifier {
  // 单例模式
  static final ModelManager _instance = ModelManager._internal();
  factory ModelManager() => _instance;
  ModelManager._internal();

  // 状态变量
  List<ModelInfo> _models = [];
  bool _isLoading = false;
  String? _currentModelPath;
  final String _defaultTaskType = 'wd14_image_tagger';
  ModelLoadingState _loadingState = ModelLoadingState.notLoaded;
  String? _errorMessage;
  static const String _cacheSubDir = 'model_cache'; // Subdirectory for caches

  // Getters
  List<ModelInfo> get models => _models;
  bool get isLoading => _isLoading;
  String? get currentModelPath => _currentModelPath;
  String get defaultTaskType => _defaultTaskType;
  ModelLoadingState get loadingState => _loadingState;
  String? get errorMessage => _errorMessage;

  // 获取应用的模型根目录
  Future<Directory> get _modelRootDir async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory(path.join(appDir.path, 'models'));
  }

  // 获取特定任务类型的模型目录
  Future<Directory> getTaskTypeDir(String taskType) async {
    final rootDir = await _modelRootDir;
    return Directory(path.join(rootDir.path, taskType));
  }

  /// 获取模型缓存的基础目录路径。
  Future<String> getCacheDirectoryPath() async {
    final Directory appCacheDir = await getApplicationCacheDirectory();
    final Directory modelCacheDir = Directory(
      path.join(appCacheDir.path, _cacheSubDir),
    );
    if (!await modelCacheDir.exists()) {
      try {
        await modelCacheDir.create(recursive: true);
        print('Created model cache directory: ${modelCacheDir.path}');
      } catch (e) {
        print('Error creating model cache directory: $e');
        return appCacheDir.path; // Fallback
      }
    }
    return modelCacheDir.path;
  }

  /// 根据模型路径和后端类型构建预期的缓存文件路径。
  Future<String> getModelCachePath(
    String modelPath,
    QnnBackendType backend,
  ) async {
    final cacheDir = await getCacheDirectoryPath();
    final modelName = path.basenameWithoutExtension(modelPath);
    final backendName = backend.name.toLowerCase();
    return path.join(cacheDir, '${modelName}_$backendName.bin');
  }

  /// 检查指定模型和后端的缓存文件是否存在。
  Future<String?> getModelCache(
    String modelPath,
    QnnBackendType backend,
  ) async {
    final expectedPath = await getModelCachePath(modelPath, backend);
    final file = File(expectedPath);
    if (await file.exists()) {
      return expectedPath;
    }
    return null;
  }

  /// 生成用于保存新缓存的文件路径（主要用于 VisionFeatureExtractor）。
  /// 注意：此方法不执行实际保存。
  Future<String?> saveModelCache(
    String modelPath,
    QnnBackendType backend,
  ) async {
    return getModelCachePath(modelPath, backend);
  }

  /// 清除所有模型缓存。
  Future<bool> clearAllModelCache() async {
    try {
      final cacheDir = Directory(await getCacheDirectoryPath());

      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        await cacheDir.create(recursive: true);
        print('Model cache cleared.');
      } else {
        print('Model cache directory does not exist.');
      }
      return true;
    } catch (e) {
      print('清除模型缓存失败: $e');
      return false;
    }
  }

  // 初始化模型管理器
  Future<void> initialize() async {
    try {
      // 创建模型根目录
      final rootDir = await _modelRootDir;
      if (!await rootDir.exists()) {
        await rootDir.create(recursive: true);
      }

      // 创建默认任务类型目录
      final defaultTaskDir = await getTaskTypeDir(_defaultTaskType);
      if (!await defaultTaskDir.exists()) {
        await defaultTaskDir.create(recursive: true);
      }

      // 扫描模型
      await scanModels();
    } catch (e) {
      print('初始化模型管理器失败: $e');
      rethrow;
    }
  }

  // 扫描所有模型
  Future<void> scanModels() async {
    if (_isLoading) return;
    _isLoading = true;

    try {
      final rootDir = await _modelRootDir;
      List<ModelInfo> models = [];

      // 遍历任务类型目录
      await for (var entity in rootDir.list()) {
        if (entity is Directory) {
          String taskType = path.basename(entity.path);

          // 遍历模型文件
          await for (var file in entity.list()) {
            if (file is File && file.path.toLowerCase().endsWith('.so')) {
              models.add(
                ModelInfo(
                  name: path.basename(file.path),
                  path: file.path,
                  taskType: taskType,
                  addedTime: await file.lastModified(),
                ),
              );
            }
          }
        }
      }

      // 按添加时间排序
      models.sort((a, b) => b.addedTime.compareTo(a.addedTime));
      _models = models;
    } catch (e) {
      print('扫描模型失败: $e');
      rethrow;
    } finally {
      _isLoading = false;
    }
  }

  // 导入模型
  Future<void> importModel(String sourcePath, String taskType) async {
    try {
      final file = File(sourcePath);
      if (!await file.exists()) {
        throw '源文件不存在';
      }

      final fileName = path.basename(sourcePath);
      if (!fileName.toLowerCase().endsWith('.so')) {
        throw '只支持.so格式的模型文件';
      }

      // 获取目标目录
      final taskDir = await getTaskTypeDir(taskType);
      if (!await taskDir.exists()) {
        await taskDir.create(recursive: true);
      }

      // 目标文件路径
      final targetPath = path.join(taskDir.path, fileName);
      final targetFile = File(targetPath);

      // 检查是否已存在
      if (await targetFile.exists()) {
        throw '模型文件已存在';
      }

      // 复制文件
      await file.copy(targetPath);

      // 刷新模型列表
      await scanModels();
    } catch (e) {
      print('导入模型失败: $e');
      rethrow;
    }
  }

  // 删除模型
  Future<void> deleteModel(ModelInfo model) async {
    try {
      final file = File(model.path);
      if (await file.exists()) {
        await file.delete();
      }

      // 如果是当前加载的模型,清除状态
      if (model.path == _currentModelPath) {
        _currentModelPath = null;
      }

      // 刷新模型列表
      await scanModels();
    } catch (e) {
      print('删除模型失败: $e');
      rethrow;
    }
  }

  // 设置当前模型
  Future<bool> setCurrentModel(String modelPath) async {
    try {
      _loadingState = ModelLoadingState.loading;
      notifyListeners();

      // 尝试加载模型
      final success = await _loadModel(modelPath);

      if (success) {
        _currentModelPath = modelPath;
        _loadingState = ModelLoadingState.loaded;
        _errorMessage = null;
      } else {
        _loadingState = ModelLoadingState.error;
        _errorMessage = "模型加载失败";
        _currentModelPath = null;
      }

      notifyListeners();
      return success;
    } catch (e) {
      _loadingState = ModelLoadingState.error;
      _errorMessage = e.toString();
      _currentModelPath = null;
      notifyListeners();
      return false;
    }
  }

  // 卸载当前模型
  Future<void> unloadCurrentModel() async {
    if (_currentModelPath != null) {
      try {
        await _unloadModel();
        _currentModelPath = null;
        _loadingState = ModelLoadingState.notLoaded;
        _errorMessage = null;
        notifyListeners();
      } catch (e) {
        _errorMessage = "模型卸载失败: $e";
        notifyListeners();
      }
    }
  }

  // 获取指定任务类型的模型列表
  List<ModelInfo> getModelsByTaskType(String taskType) {
    return _models.where((model) => model.taskType == taskType).toList();
  }

  // 获取所有任务类型
  List<String> getAllTaskTypes() {
    return _models.map((m) => m.taskType).toSet().toList()..sort();
  }

  // 内部方法：加载模型
  Future<bool> _loadModel(String modelPath) async {
    try {
      // TODO: 实现实际的模型加载逻辑
      // 这里需要调用原生方法来加载模型
      return true;
    } catch (e) {
      print('模型加载失败: $e');
      return false;
    }
  }

  // 内部方法：卸载模型
  Future<void> _unloadModel() async {
    try {
      // TODO: 实现实际的模型卸载逻辑
      // 这里需要调用原生方法来卸载模型
    } catch (e) {
      print('模型卸载失败: $e');
      rethrow;
    }
  }
}
