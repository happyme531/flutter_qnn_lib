import 'dart:ffi';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart'; // for debugPrint
import 'package:flutter_qnn_lib/qnn.dart';
import 'package:opencv_core/opencv.dart' as cv;
import 'package:path/path.dart' as path;

import '../image_loader.dart';
// Removed ModelManager and SettingsManager imports as they are no longer direct dependencies

// --- Add Definition Here ---
class FeatureExtractionResult {
  final List<double>? features;
  final Map<String, int>
  timings; // keys: 'preprocessMs', 'inputMs', 'executeMs'

  FeatureExtractionResult({this.features, required this.timings});
}
// --- End Definition ---

class VisionFeatureExtractor {
  Qnn? _qnnApp;
  bool _isInitialized = false;
  // Removed _modelManager and _settingsManager fields

  String? _currentModelPath;
  QnnBackendType? _currentBackendType;

  // Preprocessing constants remain the same
  static const int IMG_SIZE = 256;
  static const List<double> MEAN = [0.5, 0.5, 0.5];
  static const List<double> STD = [0.5, 0.5, 0.5];

  // Constructor no longer needs ModelManager or SettingsManager
  VisionFeatureExtractor();

  /// Initializes the QNN model for feature extraction.
  /// Accepts optional cache path information.
  /// Returns true if initialization is successful, false otherwise.
  Future<bool> initializeModel(
    String modelPath,
    QnnBackendType backendType, {
    String? expectedCachePath, // Path to check for existing cache
    String? cacheSaveDirectory, // Directory to save new cache
  }) async {
    // If already initialized with the same model and backend, do nothing
    if (_isInitialized &&
        _currentModelPath == modelPath &&
        _currentBackendType == backendType) {
      debugPrint('VisionFeatureExtractor: Model already initialized.');
      return true;
    }

    // Release previous model if exists
    await dispose();

    _currentModelPath = modelPath;
    _currentBackendType = backendType;

    if (_currentModelPath == null || !File(_currentModelPath!).existsSync()) {
      debugPrint(
        'VisionFeatureExtractor Error: Model file not found at $_currentModelPath',
      );
      _isInitialized = false;
      return false;
    }

    debugPrint(
      'VisionFeatureExtractor: Initializing model $_currentModelPath with backend $_currentBackendType...',
    );

    try {
      bool loadedFromCache = false;
      // Check for existing cache using the provided path
      if (expectedCachePath != null && File(expectedCachePath).existsSync()) {
        debugPrint(
          'VisionFeatureExtractor: Attempting to load from provided cache path: $expectedCachePath',
        );
        _qnnApp = await Qnn.createAsync(
          _currentBackendType!,
          expectedCachePath,
        );
        if (_qnnApp != null) {
          loadedFromCache = true;
          debugPrint('VisionFeatureExtractor: Successfully loaded from cache.');
        } else {
          debugPrint(
            'VisionFeatureExtractor: Failed to load from cache path, will load original.',
          );
        }
      }

      // If not loaded from cache, load the original model
      if (!loadedFromCache) {
        debugPrint(
          'VisionFeatureExtractor: Loading original model: $_currentModelPath',
        );
        _qnnApp = await Qnn.createAsync(
          _currentBackendType!,
          _currentModelPath!,
        );

        // Attempt to save cache if model loaded successfully and save directory is provided
        if (_qnnApp != null &&
            cacheSaveDirectory != null &&
            expectedCachePath != null) {
          // We need the expected cache *file name* to save correctly
          final cacheFileName = path
              .basename(expectedCachePath)
              .replaceAll('.bin', '');
          try {
            // Ensure the save directory exists
            final dir = Directory(cacheSaveDirectory);
            if (!await dir.exists()) {
              await dir.create(recursive: true);
              debugPrint(
                'VisionFeatureExtractor: Created cache directory: $cacheSaveDirectory',
              );
            }

            debugPrint(
              'VisionFeatureExtractor: Attempting to save cache to $cacheSaveDirectory/$cacheFileName.bin',
            );
            final result = _qnnApp!.saveBinary(
              cacheSaveDirectory,
              cacheFileName,
            );
            if (result == QnnStatus.QNN_STATUS_SUCCESS) {
              debugPrint(
                'VisionFeatureExtractor: Model cache saved successfully.',
              );
            } else {
              debugPrint(
                'VisionFeatureExtractor: Failed to save model cache, status: $result',
              );
            }
          } catch (e) {
            debugPrint('VisionFeatureExtractor: Error during cache saving: $e');
          }
        } else if (cacheSaveDirectory == null || expectedCachePath == null) {
          debugPrint(
            'VisionFeatureExtractor: Cache saving skipped (directory or expected path not provided).',
          );
        }
      }

      if (_qnnApp == null) {
        throw 'Failed to create QNN instance from cache or original model.';
      }

      _isInitialized = true;
      debugPrint('VisionFeatureExtractor: Model initialized successfully.');
      return true;
    } catch (e, stackTrace) {
      debugPrint(
        'VisionFeatureExtractor Error: Failed to initialize QNN model: $e\n$stackTrace',
      );
      await dispose(); // Ensure cleanup on failure
      return false;
    }
  }

  /// Extracts the feature vector from a given image file.
  /// Returns a FeatureExtractionResult containing the vector and timings, or null if extraction fails.
  Future<FeatureExtractionResult?> extractFeature(File imageFile) async {
    if (!_isInitialized || _qnnApp == null || _currentModelPath == null) {
      debugPrint(
        'VisionFeatureExtractor Error: Model not initialized. Call initializeModel first.',
      );
      return null;
    }
    if (!await imageFile.exists()) {
      debugPrint(
        'VisionFeatureExtractor Error: Input image file does not exist: ${imageFile.path}',
      );
      return null;
    }

    // Initialize timings map
    final Map<String, int> timings = {
      'preprocessMs': 0,
      'inputMs': 0,
      'executeMs': 0,
    };
    final Stopwatch stopwatch = Stopwatch();

    // Initialize contextStatus to a non-success value
    QnnStatus contextStatus = QnnStatus.QNN_STATUS_FAILURE;
    Pointer<Float> inputData = nullptr; // 输入数据
    try {
      // --- Preprocessing Timing ---
      stopwatch.start();
      inputData = ImageLoader.preprocessImagePointer(
        imageFile.path,
        IMG_SIZE,
        IMG_SIZE,
        MEAN.map((e) => e * 255).toList(),
        STD.map((e) => e * 255).toList(),
      );
      if (inputData == nullptr) {
        throw 'Failed to preprocess image: $imageFile';
      }

      // --- QNN Inference ---
      contextStatus = _qnnApp!.createContext(); // Attempt to create context
      if (contextStatus != QnnStatus.QNN_STATUS_SUCCESS) {
        throw 'Failed to create QNN context: $contextStatus';
      }
      stopwatch.stop();
      timings['preprocessMs'] = stopwatch.elapsedMilliseconds;
      stopwatch.reset();
      // --- End Preprocessing Timing ---

      // --- Input Loading Timing ---
      stopwatch.start();
      QnnStatus status = await _qnnApp!.loadFloatInputsFromPointersAsync(
        [inputData],
        [IMG_SIZE * IMG_SIZE * 3],
        0,
      );
      stopwatch.stop();
      timings['inputMs'] = stopwatch.elapsedMilliseconds;
      stopwatch.reset();
      // --- End Input Loading Timing ---

      if (status != QnnStatus.QNN_STATUS_SUCCESS) {
        throw 'Failed to load input data: $status';
      }

      // --- Execution Timing ---
      stopwatch.start();
      status = await _qnnApp!.executeGraphsAsync();
      stopwatch.stop();
      timings['executeMs'] = stopwatch.elapsedMilliseconds;
      stopwatch.reset();
      // --- End Execution Timing ---

      if (status != QnnStatus.QNN_STATUS_SUCCESS) {
        throw 'Failed to execute graph: $status';
      }

      // Get output tensor (Note: getFloatOutputsAsync might also take time, but we focus on core steps)
      List<List<double>> outputData = await _qnnApp!.getFloatOutputsAsync(0);
      if (outputData.isEmpty || outputData[1].isEmpty) {
        throw 'Failed to get valid output data at index 1.';
      }

      // Return result with features and timings
      return FeatureExtractionResult(features: outputData[1], timings: timings);
    } catch (e, stackTrace) {
      debugPrint(
        'VisionFeatureExtractor Error: Failed to process image ${imageFile.path}: $e\n$stackTrace',
      );
      return null;
    } finally {
      // --- Cleanup QNN Context ---
      if (contextStatus == QnnStatus.QNN_STATUS_SUCCESS) {
        _qnnApp!.freeContext();
      }
      // --- Cleanup OpenCV Mats ---
      if (inputData != nullptr) {
        ImageLoader.free(inputData);
      }
    }
  }

  /// Releases the QNN resources.
  Future<void> dispose() async {
    if (_qnnApp != null) {
      // destroy itself is async according to Qnn definition
      await _qnnApp!.destroyAsync();
      _qnnApp = null;
    }
    _isInitialized = false;
    _currentModelPath = null;
    _currentBackendType = null;
    debugPrint('VisionFeatureExtractor: Resources disposed.');
  }
}
