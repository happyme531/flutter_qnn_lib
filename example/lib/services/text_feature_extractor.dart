// for kIsWeb, defaultTargetPlatform

// Correct import paths based on typical project structure
import 'package:flutter_qnn_lib/qnn.dart';
// Assuming tokenizers.dart is in example/lib, adjust if different
import '../tokenizers.dart';

/// Service to handle text encoding using a QNN model and its tokenizer.
class TextFeatureExtractor {
  Qnn? _qnn; // Use the Qnn class from your API
  // Tokenizer is a singleton via Tokenizers.instance, no local instance needed
  bool _initialized = false;
  String? _modelPath;
  String? _tokenizerPath;
  int _inputSequenceLength = 64; // Default, based on Python example

  // Keep track of the backend type used for initialization
  QnnBackendType? _backendType;

  bool get isInitialized => _initialized;
  String? get modelPath => _modelPath;
  String? get tokenizerPath => _tokenizerPath;

  /// Initializes the text model and its corresponding tokenizer (singleton).
  ///
  /// [modelPath]: Path to the ONNX text model file.
  /// [tokenizerPath]: Path to the tokenizer configuration file (e.g., tokenizer.json).
  /// [backendType]: The QNN backend to use for model execution.
  /// [inputSequenceLength]: The expected fixed sequence length for model input (default: 64).
  Future<bool> initializeModel(
    String modelPath,
    String tokenizerPath,
    QnnBackendType backendType, {
    int inputSequenceLength = 64,
    // QNN createAsync doesn't take cache paths directly, caching handled internally?
    // String? cachePath, // Optional: Path for QNN caching
    // String? saveDir, // Optional: Directory to save cache
  }) async {
    if (_initialized) {
      print("TextFeatureExtractor already initialized.");
      // Re-initialize if paths or backend differ
      if (_modelPath != modelPath ||
          _tokenizerPath != tokenizerPath ||
          _backendType != backendType) {
        print("Configuration changed, re-initializing...");
        await dispose();
      } else {
        return true; // Already initialized with the same config
      }
    }

    _modelPath = modelPath;
    _tokenizerPath = tokenizerPath;
    _inputSequenceLength = inputSequenceLength;
    _backendType = backendType; // Store backend type

    try {
      print(
        "Initializing TextFeatureExtractor: Model='$_modelPath', Tokenizer='$_tokenizerPath', Backend='$backendType'",
      );

      // 1. Initialize Tokenizer (Singleton)
      // Ensure previous instance is destroyed if switching tokenizers
      // Note: Destroying singleton affects entire app. Handle with care.
      // Tokenizers.instance.destroy(); // Consider if this is safe in your app context
      bool tokenizerOk = await Tokenizers.instance.createAsync(tokenizerPath);
      if (!tokenizerOk) {
        throw Exception("Failed to load tokenizer from '$tokenizerPath'");
      }
      print("Tokenizer loaded successfully (Singleton).");

      // 2. Initialize QNN Instance
      // Qnn.createAsync handles backend lib path and potential Hexagon init
      _qnn = await Qnn.createAsync(
        backendType,
        modelPath,
        // Specify data types if needed, default is float input/output
        // inputDataType: QnnInputDataType.QNN_INPUT_DATA_TYPE_UINT8, // Example if needed
      );

      if (_qnn == null) {
        throw Exception(
          "Failed to initialize QNN instance. Check logs for details.",
        );
      }

      print("QNN setup steps completed.");

      _initialized = true;
      return true;
    } catch (e) {
      print("Error initializing TextFeatureExtractor: $e");
      await dispose(); // Clean up partial initialization
      return false;
    }
  }

  /// Encodes the input text into a feature vector.
  ///
  /// Returns the feature vector as a List<double>, or null if an error occurs.
  Future<List<double>?> encodeText(String text) async {
    if (!_initialized || _qnn == null /* Tokenizer is singleton */ ) {
      print("Error: TextFeatureExtractor not initialized.");
      return null;
    }
    var status = _qnn!.createContext();
    if (status != QnnStatus.QNN_STATUS_SUCCESS) {
      throw Exception("QNN createContext failed: $status");
    }

    try {
      // 1. Tokenize using the singleton instance
      final List<int>? inputIds = Tokenizers.instance.encode(
        text,
        // maxTokens parameter seems available in your Tokenizers.dart
        maxTokens: _inputSequenceLength * 2, // Allow more tokens initially
      );

      if (inputIds == null) {
        print("Error: Tokenization failed.");
        return null;
      }

      // 3. Prepare Input Tensor List (List<List<double>>)
      final List<List<double>> inputs = [
        inputIds.map((e) => e.toDouble()).toList(),
      ];
      const int graphIdx = 0; // Assuming graph index 0

      // 4. Run Inference using async QNN methods
      QnnStatus status = await _qnn!.loadFloatInputsAsync(inputs, graphIdx);
      if (status != QnnStatus.QNN_STATUS_SUCCESS) {
        print("Error: QNN loadFloatInputsAsync failed: $status");
        return null;
      }

      status = await _qnn!.executeGraphsAsync();
      if (status != QnnStatus.QNN_STATUS_SUCCESS) {
        print("Error: QNN executeGraphsAsync failed: $status");
        return null;
      }

      final List<List<double>> outputs = await _qnn!.getFloatOutputsAsync(
        graphIdx,
      );

      if (outputs.isEmpty) {
        print("Error: QNN getFloatOutputsAsync returned empty list or failed.");
        return null;
      }

      // 5. Extract Feature Vector
      // Based on Python `outputs[1][0]`:
      // - Assume the relevant output tensor is the second one (index 1).
      // - Assume it's the only vector in the batch (index 0 within that tensor).
      if (outputs.length < 2) {
        print(
          "Error: Expected at least 2 output tensors, got ${outputs.length}",
        );
        // Fallback: Try the first output tensor
        if (outputs.isNotEmpty && outputs[0].isNotEmpty) {
          print("Warning: Using first output tensor as fallback.");
          return outputs[0];
        } else {
          print("Error: Could not extract valid vector from first output.");
          return null;
        }
      }

      // Assuming the second output tensor contains the feature vector
      final List<double> featureVector = outputs[1];
      if (featureVector.isEmpty) {
        print("Error: Feature vector (output tensor 1) is empty.");
        return null;
      }

      return featureVector;
    } catch (e, stackTrace) {
      print("Error during text encoding: $e\n$stackTrace");
      return null;
    } finally {
      _qnn!.freeContext();
    }
  }

  /// Saves the underlying QNN model's binary cache.
  ///
  /// Returns true if saving was successful, false otherwise.
  /// Requires the QNN instance to be initialized.
  Future<bool> saveModelCache(String cacheDir, String cacheFileName) async {
    if (_qnn == null || !_initialized) {
      print("Error: Cannot save cache, QNN not initialized.");
      return false;
    }
    try {
      print("Attempting to save model cache to $cacheDir/$cacheFileName.bin");
      final status = _qnn!.saveBinary(cacheDir, cacheFileName);
      if (status == QnnStatus.QNN_STATUS_SUCCESS) {
        print("Model cache saved successfully.");
        return true;
      } else {
        print("Failed to save model cache, status: $status");
        return false;
      }
    } catch (e) {
      print("Error saving model cache: $e");
      return false;
    }
  }

  /// Releases the resources used by the QNN instance.
  Future<void> dispose() async {
    print("Disposing TextFeatureExtractor...");
    if (_qnn != null) {
      try {
        await _qnn!.destroyAsync();
        print("QNN instance destroyed.");
      } catch (e) {
        print("Error during QNN resource release: $e");
      }
    }
    _qnn = null;

    // --- Tokenizer Singleton ---
    // Decide if destroying the singleton here is appropriate for your app.
    // If other parts use it, DO NOT destroy it here.
    // Tokenizers.instance.destroy();
    // print("Tokenizer instance (singleton) destroyed.");

    _initialized = false;
    _modelPath = null;
    _tokenizerPath = null;
    _backendType = null;
    print("TextFeatureExtractor disposed.");
  }
}
