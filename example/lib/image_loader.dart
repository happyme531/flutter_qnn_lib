import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'dart:typed_data';

import 'image_loader_bindings_generated.dart';

// Helper to lookup symbols across platforms.
DynamicLibrary _loadLibrary() {
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libimage_loader.so');
  }
  throw UnsupportedError('Platform not supported');
}

final DynamicLibrary _dylib = _loadLibrary();

/// FFI bindings to `image_loader`.
final ImageLoaderBindings _bindings = ImageLoaderBindings(_dylib);

// Lookup the C 'free' function.
typedef FreeC = Void Function(Pointer<Void>);
typedef FreeDart = void Function(Pointer<Void>);
final FreeDart _free =
    _dylib.lookup<NativeFunction<FreeC>>('free').asFunction<FreeDart>();

/// A Dart wrapper class for the native image preprocessing functions.
class ImageLoader {
  /// Exposes the native `free` function to release memory allocated by native code,
  /// specifically for pointers returned by [preprocessImagePointer].
  ///
  /// Call this method with the pointer obtained from [preprocessImagePointer] when you
  /// are finished using the data to prevent memory leaks.
  ///
  /// Example:
  /// ```dart
  /// Pointer<Float> ptr = ImageLoader.preprocessImagePointer(...);
  /// if (ptr != nullptr) {
  ///   try {
  ///     // Use the pointer data
  ///   } finally {
  ///     ImageLoader.free(ptr);
  ///   }
  /// }
  /// ```
  static void free(Pointer<Float> pointer) {
    _free(pointer.cast<Void>());
  }

  /// Loads and preprocesses an image using the native C++ implementation.
  ///
  /// - Loads the image from [imagePath].
  /// - Resizes it to fit within [targetWidth]x[targetHeight] while preserving aspect ratio.
  /// - Pads the image with black to reach the target dimensions.
  /// - Converts from BGR to RGB.
  /// - Normalizes the pixel values using the provided [means] and [stdDevs].
  ///
  /// Returns a [Float32List] containing the preprocessed image data (RGBRGB...)
  /// or `null` if preprocessing fails.
  ///
  /// Throws [ArgumentError] if means or stdDevs lists do not contain exactly 3 elements
  /// or if any stdDev is zero.
  static Float32List? preprocessImage(
    String imagePath,
    int targetWidth,
    int targetHeight,
    List<double> means,
    List<double> stdDevs,
  ) {
    if (means.length != 3 || stdDevs.length != 3) {
      throw ArgumentError(
        'means and stdDevs lists must contain exactly 3 elements.',
      );
    }
    if (stdDevs.any((std) => std == 0.0)) {
      throw ArgumentError('Standard deviations cannot be zero.');
    }

    // Allocate memory for C strings and float arrays
    final imagePathC = imagePath.toNativeUtf8();
    final meansC = calloc<Float>(3);
    final stdDevsC = calloc<Float>(3);

    // Copy list data to native memory
    for (int i = 0; i < 3; ++i) {
      meansC[i] = means[i];
      stdDevsC[i] = stdDevs[i];
    }

    Pointer<Float> resultPtr = nullptr;
    try {
      // Call the native function
      resultPtr = _bindings.preprocessImage(
        imagePathC.cast<Char>(), // Use cast<Char>() if your C API expects char*
        targetWidth,
        targetHeight,
        meansC,
        stdDevsC,
      );

      if (resultPtr == nullptr) {
        print('Native preprocessImage returned null.');
        return null; // Indicate failure
      }

      // Calculate buffer size
      final int bufferSize = targetWidth * targetHeight * 3;

      // Copy the data from native memory to a Dart Float32List
      // This creates a copy, so we can free the native memory afterwards.
      final Float32List resultData = resultPtr.asTypedList(bufferSize);

      // It's crucial to return a copy or manage the pointer carefully.
      // Returning the asTypedList directly creates a view backed by native memory,
      // which becomes invalid after freeing the pointer.
      return Float32List.fromList(resultData);
    } finally {
      // Free all allocated native memory
      calloc.free(imagePathC);
      calloc.free(meansC);
      calloc.free(stdDevsC);
      if (resultPtr != nullptr) {
        _free(
          resultPtr.cast<Void>(),
        ); // Free the memory allocated by the C++ function
      }
    }
  }

  /// Loads and preprocesses an image, returning a raw pointer to the native float data.
  ///
  /// Performs the same preprocessing steps as [preprocessImage].
  ///
  /// **WARNING:** This method returns a raw `Pointer<Float>` allocated by the native C++
  /// code. The caller is **responsible** for freeing this pointer using `free(pointer.cast<Void>())`
  /// when it's no longer needed to prevent memory leaks. You can get the `free` function
  /// pointer using `DynamicLibrary.lookup<NativeFunction<Void Function(Pointer<Void>)>>('free')`.
  /// The size of the data buffer is `targetWidth * targetHeight * 3` floats.
  ///
  /// Returns `nullptr` if preprocessing fails.
  ///
  /// Throws [ArgumentError] if means or stdDevs lists do not contain exactly 3 elements
  /// or if any stdDev is zero.
  static Pointer<Float> preprocessImagePointer(
    String imagePath,
    int targetWidth,
    int targetHeight,
    List<double> means,
    List<double> stdDevs,
  ) {
    if (means.length != 3 || stdDevs.length != 3) {
      throw ArgumentError(
        'means and stdDevs lists must contain exactly 3 elements.',
      );
    }
    if (stdDevs.any((std) => std == 0.0)) {
      throw ArgumentError('Standard deviations cannot be zero.');
    }

    // Allocate memory for C strings and float arrays
    final imagePathC = imagePath.toNativeUtf8();
    final meansC = calloc<Float>(3);
    final stdDevsC = calloc<Float>(3);

    // Copy list data to native memory
    for (int i = 0; i < 3; ++i) {
      meansC[i] = means[i];
      stdDevsC[i] = stdDevs[i];
    }

    Pointer<Float> resultPtr = nullptr;
    try {
      // Call the native function
      resultPtr = _bindings.preprocessImage(
        imagePathC.cast<Char>(),
        targetWidth,
        targetHeight,
        meansC,
        stdDevsC,
      );
      // DO NOT free resultPtr here. Caller is responsible.
      return resultPtr;
    } finally {
      // Free only the input parameter memory allocated in this function
      calloc.free(imagePathC);
      calloc.free(meansC);
      calloc.free(stdDevsC);
    }
  }
}
