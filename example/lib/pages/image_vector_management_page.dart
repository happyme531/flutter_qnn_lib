import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart'; // For compute and kIsWeb
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For RootIsolateToken
// For QnnBackendType
import 'package:permission_handler/permission_handler.dart';
import 'package:app_settings/app_settings.dart';

import '../model_manager.dart';
import '../settings_manager.dart';
import '../database/image_vector_database.dart';
import '../tasks/image_vector_batch_indexer.dart';
import '../widgets/model_manager_widget.dart';

class ImageVectorManagementPage extends StatefulWidget {
  const ImageVectorManagementPage({super.key});

  @override
  State<ImageVectorManagementPage> createState() =>
      _ImageVectorManagementPageState();
}

class _ImageVectorManagementPageState extends State<ImageVectorManagementPage> {
  final ModelManager _modelManager = ModelManager();
  final SettingsManager _settingsManager = SettingsManager();
  final ImageVectorDatabase _vectorDatabase = ImageVectorDatabase.instance;

  String? _selectedModelPath;
  bool _isProcessing = false;
  BatchIndexProgress? _progress; // Store the latest progress info
  ReceivePort?
  _receivePort; // Port to listen for isolate progress/results AND command port
  StreamSubscription? _progressSubscription;
  SendPort? _isolateCommandPort; // <-- Port to send commands TO the isolate
  bool _isolateRunning = false; // Flag to track if the isolate is active

  @override
  void initState() {
    super.initState();
    _initManagers();
    // Listen for backend changes if needed (e.g., to update UI or re-validate selection)
    // _settingsManager.addListener(_onBackendChanged);
  }

  Future<void> _initManagers() async {
    try {
      await _modelManager.initialize();
      // SettingsManager likely doesn't need async init unless loading from storage
      if (mounted) {
        setState(() {}); // Update UI after manager init
      }
    } catch (e) {
      _showSnackBar('Failed to initialize managers: $e');
    }
  }

  void _onModelSelected(String? modelPath) {
    if (mounted) {
      setState(() {
        _selectedModelPath = modelPath;
        // Reset progress if model changes during processing (or prevent change)
        if (_isProcessing) {
          _cancelBatchIndex(); // Optional: cancel if model changes
        }
        _progress = null; // Clear old progress
      });
    }
  }

  Future<bool> _checkAndRequestPermissions() async {
    var status = await Permission.photos.status;
    if (status.isGranted) {
      return true;
    }

    // If denied permanently, guide user to settings
    if (status.isPermanentlyDenied) {
      _showPermissionDialog('相册权限已被永久拒绝，请前往系统设置开启。', goToSettings: true);
      return false;
    }

    // Request permission
    status = await Permission.photos.request();

    if (status.isGranted) {
      return true;
    } else {
      _showPermissionDialog(
        '需要相册权限才能批量索引图片。请授予权限。',
        goToSettings: status.isPermanentlyDenied,
      );
      return false;
    }
  }

  void _showPermissionDialog(String content, {bool goToSettings = false}) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('需要权限'),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              if (goToSettings)
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    AppSettings.openAppSettings(type: AppSettingsType.settings);
                  },
                  child: const Text('前往设置'),
                )
              else
                TextButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await Permission.photos.request(); // Try requesting again
                  },
                  child: const Text('重试授权'),
                ),
            ],
          ),
    );
  }

  Future<void> _startBatchIndex() async {
    if (_selectedModelPath == null) {
      _showSnackBar('请先选择一个视觉模型');
      return;
    }
    if (_isProcessing || _isolateRunning) {
      _showSnackBar('已经在处理中...');
      return;
    }

    // --- Check Platform Compatibility ---
    if (kIsWeb) {
      _showSnackBar('Web平台不支持后台批量处理。');
      return;
    }
    // Add other platform checks if needed (e.g., sqflite on Windows isolate issues)
    // if (defaultTargetPlatform == TargetPlatform.windows) { ... }

    // --- Check Permissions ---
    final hasPermission = await _checkAndRequestPermissions();
    if (!hasPermission) return;

    // --- Get Necessary Paths ---
    String? dbPath;
    String? cacheDir;
    String? expectedCachePath;
    try {
      // Ensure DB is initialized to get path
      await _vectorDatabase.database;
      dbPath = await _vectorDatabase.getDatabasePath(); // Assumed method

      // Get cache info
      expectedCachePath = await _modelManager.getModelCachePath(
        _selectedModelPath!,
        _settingsManager.backendType,
      ); // Assumed method
      cacheDir = await _modelManager.getCacheDirectoryPath(); // Assumed method

      if (dbPath == null) {
        throw Exception("无法获取数据库路径");
      }
      if (cacheDir == null) {
        throw Exception("无法获取缓存目录路径");
      }
      // expectedCachePath can be null if no cache exists yet
    } catch (e) {
      _showSnackBar('启动失败: 获取路径时出错 - $e');
      return;
    }

    // --- Setup Isolate Communication ---
    _receivePort = ReceivePort();
    // 获取 RootIsolateToken (必须在主 isolate 中获取)
    final rootToken = RootIsolateToken.instance;
    if (rootToken == null) {
      _showSnackBar('错误：无法获取 RootIsolateToken，无法启动后台任务。');
      return;
    }

    final arguments = BatchIndexArguments(
      modelPath: _selectedModelPath!,
      backendType: _settingsManager.backendType,
      dbPath: dbPath,
      mainSendPort: _receivePort!.sendPort,
      expectedCachePath: expectedCachePath,
      cacheDirectoryPath: cacheDir,
      rootIsolateToken: rootToken, // <-- 传递 Token
    );

    // --- Start Isolate ---
    try {
      debugPrint("Starting batch index isolate...");
      // 使用 Isolate.spawn 替代 compute
      final isolate = await Isolate.spawn(
        runBatchIndexIsolate,
        arguments,
        onError: _receivePort!.sendPort, // 将启动错误发送到主端口
        onExit: _receivePort!.sendPort, // 监听退出事件（可选，但有助于调试）
        errorsAreFatal: false, // 通常设为 false，允许我们处理错误
      );
      // 注意：与 Isolate 的交互现在主要通过 _receivePort
      _isolateRunning = true; // Mark isolate as potentially running

      // --- Listen for Progress ---
      _progressSubscription = _receivePort!.listen((message) {
        if (message is BatchIndexProgress) {
          if (mounted) {
            setState(() {
              _progress = message;
              // Update processing state based on completion
              if (message.isComplete) {
                _isProcessing = false;
                _isolateRunning = false; // Isolate finished
                _progressSubscription?.cancel(); // Cancel subscription
                _receivePort?.close(); // Close the port
                _showSnackBar(message.errorMessage ?? '批量处理完成');
              } else {
                _isProcessing =
                    true; // Ensure processing is true while receiving progress
              }
            });
          }
        } else if (message is Map && message.containsKey('commandPort')) {
          // 收到了后台 Isolate 发送回来的命令端口
          _isolateCommandPort = message['commandPort'] as SendPort?;
          debugPrint("Main: Received isolate command port.");
        } else if (message is List && message.length == 2) {
          // 检查是否为 Isolate 的 onError 发送的错误消息 (通常是 [errorString, stackTraceString])
          final error = message[0];
          final stackTrace = message[1];
          debugPrint("Isolate Error (via main port): $error\n$stackTrace");
          _showSnackBar('后台任务出错: $error');
          if (mounted) {
            setState(() {
              _isProcessing = false;
              _isolateRunning = false;
              _progress = BatchIndexProgress(
                totalImages: _progress?.totalImages ?? 0, // 保留之前的进度
                processedImages: _progress?.processedImages ?? 0,
                isComplete: true,
                errorMessage: '后台错误: $error',
              );
            });
          }
          _progressSubscription?.cancel();
          _receivePort?.close();
        } else if (message == null) {
          // Isolate 退出消息 (通常在 onExit 时发送 null)
          debugPrint("Isolate exited.");
          if (_isolateRunning) {
            // 如果 Isolate 意外退出 (而不是正常完成)
            _showSnackBar('后台任务意外终止');
            if (mounted) {
              setState(() {
                _isProcessing = false;
                _isolateRunning = false;
                _progress = BatchIndexProgress(
                  totalImages: _progress?.totalImages ?? 0,
                  processedImages: _progress?.processedImages ?? 0,
                  isComplete: true,
                  errorMessage: '任务意外终止',
                );
              });
            }
            _progressSubscription?.cancel();
            _receivePort?.close();
          }
        }
      });

      // Update UI to show processing started
      if (mounted) {
        setState(() {
          _isProcessing = true;
          _progress = BatchIndexProgress(
            totalImages: 0,
            processedImages: 0,
            currentImageName: '正在启动...',
          );
        });
      }
    } catch (e) {
      // Catch errors during the setup phase before compute starts
      _showSnackBar('启动后台任务时出错: $e');
      _receivePort?.close();
      _progressSubscription?.cancel();
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _isolateRunning = false;
        });
      }
    }
  }

  void _cancelBatchIndex() {
    if (!_isolateRunning && !_isProcessing) {
      debugPrint("Cancel requested but isolate not running.");
      return;
    }
    if (_isolateCommandPort == null) {
      _showSnackBar('无法发送取消命令：未获取到后台命令端口');
      // 仍然尝试关闭进度端口作为后备
      _progressSubscription?.cancel();
      _receivePort?.close();
      _isolateRunning = false;
      if (mounted)
        setState(() {
          _isProcessing = false;
        });
      return;
    }

    debugPrint("Attempting to cancel batch index via command port...");
    try {
      _isolateCommandPort!.send('CANCEL');
      _showSnackBar('已发送取消命令...');
    } catch (e) {
      _showSnackBar('发送取消命令失败: $e');
    }

    // 发送命令后，仍然可以关闭监听和端口
    _progressSubscription?.cancel();
    _receivePort?.close();
    _isolateRunning = false; // Assume cancellation signal sent
    _isolateCommandPort = null; // 清除命令端口

    if (mounted) {
      setState(() {
        _isProcessing = false; // Stop showing active progress UI immediately
        // Keep the last known progress state but mark as maybe cancelled
        _progress = _progress?.copyWith(
          errorMessage: (_progress?.errorMessage ?? '') + ' (正在取消...)',
          // isComplete: true // Or maybe keep isComplete false until confirmed completion?
        );
      });
    }
  }

  @override
  void dispose() {
    // Cancel any active subscription and close the port
    // 发送取消命令（如果仍在运行）- 可选，取决于是否希望在 dispose 时取消
    // if (_isolateRunning && _isolateCommandPort != null) {
    //   try { _isolateCommandPort!.send('CANCEL'); } catch (_) {}
    // }
    _progressSubscription?.cancel();
    _receivePort?.close();
    _isolateCommandPort = null; // 清除引用
    // _settingsManager.removeListener(_onBackendChanged); // If listener was added
    super.dispose();
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // Helper function to format milliseconds to string
    String formatMs(int? ms) {
      if (ms == null || ms <= 0) return 'N/A';
      return '$ms ms';
    }

    // Calculate total time for the last processed image
    int? totalLastMs;
    if (_progress?.lastPreprocessMs != null &&
        _progress?.lastInputMs != null &&
        _progress?.lastExecuteMs != null) {
      totalLastMs =
          _progress!.lastPreprocessMs! +
          _progress!.lastInputMs! +
          _progress!.lastExecuteMs!;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('图像向量批量索引')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '选择视觉模型进行批量特征提取和索引',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // Model Selection
            ModelManagerWidget(
              onModelSelected: _onModelSelected,
              currentModelPath: _selectedModelPath,
              taskType: 'vision_encoder', // Use the correct task type
            ),
            const SizedBox(height: 24),

            // Backend Info (Readonly display from SettingsManager)
            Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '当前计算后端:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _settingsManager.backendType.name.toUpperCase(),
                    ), // Display current backend
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Start/Cancel Button
            ElevatedButton.icon(
              icon: Icon(_isProcessing ? Icons.cancel : Icons.batch_prediction),
              label: Text(_isProcessing ? '取消处理' : '开始批量索引'),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isProcessing ? Colors.red.shade300 : Colors.blue,
                padding: const EdgeInsets.symmetric(vertical: 12.0),
              ),
              // Disable start button if no model selected or already processing
              onPressed:
                  _isProcessing
                      ? _cancelBatchIndex
                      : (_selectedModelPath == null ? null : _startBatchIndex),
            ),
            const SizedBox(height: 20),

            // Progress Indicator Area
            if (_progress != null)
              Column(
                children: [
                  if (_isProcessing &&
                      !_progress!
                          .isComplete) // Show linear progress only when actively processing
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: LinearProgressIndicator(
                        value:
                            (_progress!.totalImages > 0)
                                ? (_progress!.processedImages /
                                    _progress!.totalImages)
                                : null, // Indeterminate if total is 0
                        minHeight: 10,
                      ),
                    ),

                  // Progress Text
                  Text(
                    _progress!.isComplete
                        ? (_progress!.errorMessage ??
                            '处理完成') // Show final status or error
                        : '${_progress!.processedImages} / ${_progress!.totalImages > 0 ? _progress!.totalImages : '...'}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),

                  // --- Performance Timing Display (Last Image) ---
                  // Show if timings for the last image are available
                  if (_progress!.lastPreprocessMs != null)
                    Card(
                      margin: const EdgeInsets.only(top: 16.0),
                      color: Colors.lightBlue.shade50, // Changed color slightly
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              // Updated title
                              '上一张成功处理耗时:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Colors.lightBlue.shade800,
                              ),
                            ),
                            Divider(color: Colors.lightBlue.shade100),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('图像预处理:'),
                                // Use last timings fields
                                Text(formatMs(_progress!.lastPreprocessMs)),
                              ],
                            ),
                            SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('模型输入加载:'),
                                Text(formatMs(_progress!.lastInputMs)),
                              ],
                            ),
                            SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('模型推理执行:'),
                                Text(formatMs(_progress!.lastExecuteMs)),
                              ],
                            ),
                            Divider(color: Colors.lightBlue.shade100),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '总计:',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  // Use calculated total last time
                                  formatMs(totalLastMs),
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                  // --- End Performance Timing Display ---
                  if (!_progress!
                      .isComplete) // Show current image only when processing
                    Text(
                      _progress!.currentImageName.isNotEmpty
                          ? '正在处理: ${_progress!.currentImageName}'
                          : (_isProcessing
                              ? '等待下一张图片...'
                              : ''), // Show waiting text if processing but no name yet
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (_progress!.isComplete && _progress!.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        _progress!.errorMessage!,
                        style: TextStyle(color: Colors.red.shade700),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// Helper extension to add copyWith to BatchIndexProgress for easier state updates
extension BatchIndexProgressCopyWith on BatchIndexProgress {
  BatchIndexProgress copyWith({
    int? totalImages,
    int? processedImages,
    String? currentImageName,
    bool? isComplete,
    String? errorMessage,
    bool clearError = false,
    // Update parameters for copyWith
    int? lastPreprocessMs,
    int? lastInputMs,
    int? lastExecuteMs,
  }) {
    return BatchIndexProgress(
      totalImages: totalImages ?? this.totalImages,
      processedImages: processedImages ?? this.processedImages,
      currentImageName: currentImageName ?? this.currentImageName,
      isComplete: isComplete ?? this.isComplete,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      // Copy last timings
      lastPreprocessMs: lastPreprocessMs ?? this.lastPreprocessMs,
      lastInputMs: lastInputMs ?? this.lastInputMs,
      lastExecuteMs: lastExecuteMs ?? this.lastExecuteMs,
    );
  }
}

// Placeholder methods (Add these to respective classes or implement them)
// Add to ImageVectorDatabase class:
/*
extension ImageVectorDatabasePath on ImageVectorDatabase {
  Future<String?> getDatabasePath() async {
    // Ensure DB is initialized first
    await database;
    return _databasePath; // Return the stored path
  }
}
*/

// Add to ModelManager class:
/*
extension ModelManagerPaths on ModelManager {
   Future<String?> getModelCachePath(String modelPath, QnnBackendType backend) async {
    // Implement logic to determine the expected cache file path based on modelPath and backend
    // This likely involves getting the cache directory and constructing the filename
    final cacheDir = await getCacheDirectoryPath();
    final modelName = path.basenameWithoutExtension(modelPath);
    final backendName = backend.name.toLowerCase();
    return path.join(cacheDir, '${modelName}_$backendName.bin');
  }

   Future<String> getCacheDirectoryPath() async {
      // Implement logic to get the base directory for model caches
      // e.g., using path_provider
      final Directory appCacheDir = await getApplicationCacheDirectory();
      final Directory modelCacheDir = Directory(path.join(appCacheDir.path, 'model_cache'));
      if (!await modelCacheDir.exists()) {
          await modelCacheDir.create(recursive: true);
      }
      return modelCacheDir.path;
   }
}
*/
