import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart'; // for debugPrint
import 'package:flutter_qnn_lib/qnn.dart'; // Import the main qnn.dart file
import 'package:photo_manager/photo_manager.dart';
import 'package:sqflite/sqflite.dart'; // For DatabaseException etc.
// For basename
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart'; // <--- 添加这个导入
import 'dart:async'; // <-- 添加 async 导入

import '../services/vision_feature_extractor.dart';
import '../database/image_vector_database.dart';
// Needed by VisionFeatureExtractor
// Needed by VisionFeatureExtractor

// --- Data Classes for Communication ---

/// Arguments passed to the batch indexing isolate.
class BatchIndexArguments {
  final String modelPath;
  final QnnBackendType backendType;
  final String dbPath;
  final SendPort
  mainSendPort; // Port to send progress/results back to main isolate
  final String? expectedCachePath;
  final String? cacheDirectoryPath;
  final RootIsolateToken? rootIsolateToken;

  BatchIndexArguments({
    required this.modelPath,
    required this.backendType,
    required this.dbPath,
    required this.mainSendPort,
    this.expectedCachePath,
    this.cacheDirectoryPath,
    required this.rootIsolateToken,
  });
}

/// Represents the progress/status updates sent from the isolate.
class BatchIndexProgress {
  final int totalImages;
  final int processedImages;
  final String currentImageName;
  final bool isComplete;
  final String? errorMessage; // Optional error message
  // Replace average timings with last image's timings
  final int? lastPreprocessMs;
  final int? lastInputMs;
  final int? lastExecuteMs;

  BatchIndexProgress({
    required this.totalImages,
    required this.processedImages,
    this.currentImageName = '',
    this.isComplete = false,
    this.errorMessage,
    // Update constructor parameters
    this.lastPreprocessMs,
    this.lastInputMs,
    this.lastExecuteMs,
  });

  @override
  String toString() {
    // Update toString for debugging
    return 'Progress(total: $totalImages, processed: $processedImages, current: $currentImageName, complete: $isComplete, error: $errorMessage, lastPre: $lastPreprocessMs, lastIn: $lastInputMs, lastEx: $lastExecuteMs)';
  }
}

// --- Isolate Entry Point ---

/// Top-level function to be executed in the background isolate.
Future<void> runBatchIndexIsolate(BatchIndexArguments args) async {
  // 将 cancelRequested 声明移到前面
  bool cancelRequested = false;

  // --- 初始化后台 Isolate 的 Flutter 绑定 --- START
  // 确保我们有 RootIsolateToken
  if (args.rootIsolateToken == null) {
    print("Isolate Error: RootIsolateToken is missing.");
    // 可以尝试发送错误回主 Isolate，或者直接抛出异常
    args.mainSendPort.send(
      BatchIndexProgress(
        totalImages: 0,
        processedImages: 0,
        isComplete: true,
        errorMessage: '后台初始化失败：缺少 RootIsolateToken',
      ),
    );
    return; // 无法继续
  }
  BackgroundIsolateBinaryMessenger.ensureInitialized(
    args.rootIsolateToken!, // <-- 使用传递过来的 Token
  );
  // --- 初始化后台 Isolate 的 Flutter 绑定 --- END

  // --- 设置命令接收端口 --- START
  final ReceivePort isolateCommandReceivePort = ReceivePort();
  // 将此 Isolate 的命令接收端口发送回主 Isolate
  args.mainSendPort.send({'commandPort': isolateCommandReceivePort.sendPort});

  StreamSubscription? commandSubscription;

  commandSubscription = isolateCommandReceivePort.listen((message) {
    if (message == 'CANCEL') {
      debugPrint('Isolate: Received CANCEL command.');
      cancelRequested = true;
      commandSubscription?.cancel(); // 收到取消后停止监听命令
      isolateCommandReceivePort.close(); // 关闭自己的端口
    }
  });
  // --- 设置命令接收端口 --- END

  VisionFeatureExtractor? featureExtractor;
  Database? isolateDb;

  // --- Helper Function to Send Progress ---
  void sendProgress(BatchIndexProgress progress) {
    try {
      args.mainSendPort.send(progress);
    } catch (e) {
      // If sending fails, the main isolate might have stopped listening (e.g., disposed)
      debugPrint(
        'Isolate: Failed to send progress, assuming cancellation. Error: $e',
      );
      cancelRequested = true; // Assume cancelled if send fails
    }
  }

  int totalAssets = 0;
  int processedCount = 0;

  // --- Variables to store the last successful timings ---
  int? lastPreprocessMs;
  int? lastInputMs;
  int? lastExecuteMs;

  try {
    debugPrint('Isolate: Starting batch index task...');
    sendProgress(
      BatchIndexProgress(
        totalImages: 0,
        processedImages: 0,
        currentImageName: 'Initializing...',
      ),
    );

    // --- Initialization ---
    // Initialize Feature Extractor using cache paths from args
    featureExtractor =
        VisionFeatureExtractor(); // Create instance (no managers needed)

    // Pass backend type and cache info to initializeModel
    final bool modelInitSuccess = await featureExtractor.initializeModel(
      args.modelPath,
      args.backendType, // Pass backend type from args
      expectedCachePath: args.expectedCachePath, // Pass expected cache path
      cacheSaveDirectory: args.cacheDirectoryPath, // Pass save directory
    );

    if (!modelInitSuccess) {
      throw Exception('Failed to initialize the vision model in isolate.');
    }

    // Initialize Database Connection
    isolateDb = await openDatabase(
      args.dbPath,
      readOnly: false,
    ); // Need write access
    // Create an instance of ImageVectorDatabase logic tied to this isolate's connection
    // We can't use the Singleton instance directly. We'll call static methods or replicate logic.
    final ImageVectorDatabase isolateDbHandler =
        ImageVectorDatabase
            .instance; // This still uses the singleton, tricky...
    // Better: Pass dbPath and perform operations directly or create a non-singleton DB helper.
    // Let's stick to direct DB operations for now.

    debugPrint('Isolate: Initialization complete. Fetching images...');
    sendProgress(
      BatchIndexProgress(
        totalImages: 0, // Still 0 initially
        processedImages: 0,
        currentImageName: 'Fetching image list...', // Update status message
      ),
    );

    // --- Fetch Image Assets ---
    final albums = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: RequestType.image,
    );
    if (albums.isEmpty) {
      debugPrint('Isolate: No image albums found.');
      sendProgress(
        BatchIndexProgress(
          totalImages: 0,
          processedImages: 0,
          isComplete: true,
        ),
      );
      return;
    }
    final mainAlbum = albums.first;
    // final initialTotalAssets = await mainAlbum.assetCountAsync; // Get initial count for info

    // Fetch the entire list of assets at the beginning
    // Note: If the number of assets is extremely large, this might consume significant memory.
    // Consider using getAssetListPaged if memory becomes an issue, but process the full list.
    final List<AssetEntity> allAssets = await mainAlbum.getAssetListRange(
      start: 0,
      end: await mainAlbum.assetCountAsync,
    ); // Fetch all assets based on current count

    totalAssets = allAssets.length; // Use the count from the fetched list

    if (totalAssets == 0) {
      debugPrint('Isolate: Album is empty.');
      sendProgress(
        BatchIndexProgress(
          totalImages: 0,
          processedImages: 0,
          isComplete: true,
        ),
      );
      return;
    }

    // --- Start Processing the Fixed List ---
    int databaseErrors = 0;
    int featureErrors = 0;

    debugPrint(
      'Isolate: Total images to process: $totalAssets. Starting processing...',
    );

    // Send initial progress (no timings yet)
    sendProgress(
      BatchIndexProgress(
        totalImages: totalAssets,
        processedImages: 0,
        currentImageName: 'Starting...',
      ),
    );

    // Iterate directly over the fetched list
    for (final asset in allAssets) {
      if (cancelRequested) break;

      final String currentImageId = asset.id;
      final String currentImageName = await asset.titleAsync ?? asset.id;

      // Send progress *before* processing this asset, include the *previous* image's timings
      sendProgress(
        BatchIndexProgress(
          totalImages: totalAssets,
          processedImages: processedCount,
          currentImageName: currentImageName,
          // Pass the timings recorded from the *last* successful extraction
          lastPreprocessMs: lastPreprocessMs,
          lastInputMs: lastInputMs,
          lastExecuteMs: lastExecuteMs,
        ),
      );

      // Reset last timings for the current iteration, will be updated on success
      // lastPreprocessMs = null;
      // lastInputMs = null;
      // lastExecuteMs = null;
      // ^-- Actually, let's keep the last successful one until a new one succeeds.

      try {
        // --- Check if Indexed ---
        final List<Map<String, dynamic>> existing = await isolateDb.query(
          'image_vectors',
          columns: ['id'],
          where: 'image_identifier = ?',
          whereArgs: [currentImageId],
          limit: 1,
        );

        if (existing.isNotEmpty) {
          debugPrint(
            'Isolate: Skipping already indexed image: $currentImageName ($currentImageId)',
          );
          continue;
        }

        // --- Get File ---
        if (cancelRequested) break;
        // Getting the file can be time-consuming, do it after the index check
        final File? imageFile =
            await asset.originFile ?? await asset.file; // Prefer original file
        if (imageFile == null) {
          debugPrint(
            'Isolate: Failed to get file for asset: $currentImageName ($currentImageId)',
          );
          featureErrors++;
          continue;
        }

        // --- Extract Features (includes timing) ---
        if (cancelRequested) break;
        final FeatureExtractionResult? result = await featureExtractor
            .extractFeature(imageFile);

        if (result != null && result.features != null) {
          // --- Extraction Successful ---
          // Update last timings with the current successful result
          lastPreprocessMs = result.timings['preprocessMs'];
          lastInputMs = result.timings['inputMs'];
          lastExecuteMs = result.timings['executeMs'];

          final features = result.features!;

          // --- Add to Database ---
          final vectorBlob = ImageVectorDatabase.vectorToBlob(
            features,
          ); // Use static helper
          final vectorDim = features.length;
          final timestamp = DateTime.now();
          final imageVectorMap = {
            'image_identifier': currentImageId,
            'vector': vectorBlob,
            'vector_dim': vectorDim,
            'added_timestamp': timestamp.toIso8601String(),
          };

          final int insertedId = await isolateDb.insert(
            'image_vectors',
            imageVectorMap,
            conflictAlgorithm:
                ConflictAlgorithm
                    .replace, // Replace if somehow indexed between check and insert
          );

          if (insertedId > 0) {
            debugPrint(
              'Isolate: Indexed image: $currentImageName ($currentImageId), Dim: $vectorDim',
            );
          } else {
            debugPrint(
              'Isolate: Failed to insert vector for: $currentImageName ($currentImageId)',
            );
            databaseErrors++;
          }
        } else {
          // --- Extraction Failed ---
          debugPrint(
            'Isolate: Failed to extract features for: $currentImageName ($currentImageId)',
          );
          featureErrors++;
          // Do not update last timings on failure
          continue; // Skip DB insertion
        }
      } catch (e, stackTrace) {
        debugPrint(
          'Isolate: Error processing image $currentImageName ($currentImageId): $e\n$stackTrace',
        );
        databaseErrors++;
        // Do not update last timings on error
      } finally {
        processedCount++;
      }
    }

    // --- Completion ---
    debugPrint('Isolate: Batch index task finished.');
    String summaryMessage =
        'Processing complete. $processedCount/$totalAssets processed.';
    if (databaseErrors > 0 || featureErrors > 0) {
      summaryMessage +=
          ' ($featureErrors feature errors, $databaseErrors DB errors)';
    }
    // Send final status including the very last successful timings recorded
    sendProgress(
      BatchIndexProgress(
        totalImages: totalAssets,
        processedImages: processedCount,
        isComplete: true,
        errorMessage:
            cancelRequested
                ? 'Processing cancelled by user.'
                : ((databaseErrors > 0 || featureErrors > 0)
                    ? summaryMessage
                    : null),
        // Pass the timings from the last successful operation
        lastPreprocessMs: lastPreprocessMs,
        lastInputMs: lastInputMs,
        lastExecuteMs: lastExecuteMs,
      ),
    );
  } catch (e, stackTrace) {
    debugPrint('Isolate: Unhandled error in batch index task: $e\n$stackTrace');
    // Send final error message, potentially including last known timings
    sendProgress(
      BatchIndexProgress(
        totalImages: totalAssets,
        processedImages: processedCount,
        isComplete: true,
        errorMessage: 'Critical isolate error: $e',
        lastPreprocessMs:
            lastPreprocessMs, // Send last known timings if available
        lastInputMs: lastInputMs,
        lastExecuteMs: lastExecuteMs,
      ),
    );
  } finally {
    // --- Cleanup --- (确保在 finally 中取消命令监听并关闭端口)
    debugPrint('Isolate: Cleaning up resources...');
    await featureExtractor?.dispose();
    await isolateDb?.close();
    await commandSubscription?.cancel(); // 确保取消监听
    isolateCommandReceivePort.close(); // 确保关闭命令端口
    debugPrint('Isolate: Resources cleaned up. Exiting.');
    // Isolate automatically terminates after this function completes.
  }
}
