import 'dart:ffi' as ffi;
import 'dart:ffi';
import 'dart:io' show Platform, Directory, File;
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show rootBundle, ByteData;
import 'package:flutter_qnn_lib/qnn_types.dart';
import 'package:flutter_qnn_lib/platform_utils.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'dart:async';

// 注意：这个文件依赖生成的 FFI 绑定文件，请确保 qnn_wrapper_bindings_generated.dart 可用。
import 'qnn_wrapper_bindings_generated.dart';
export 'qnn_types.dart';
export 'qnn_wrapper_bindings_generated.dart'
    show QnnStatus, QnnOutputDataType, QnnInputDataType;

// 存储创建完成后的Completer引用，用于静态回调

// 存储获取浮点输出的Completer引用
// ignore: unused_element
Completer<List<List<double>>>? _floatOutputsCompleter;

// 存储获取后端构建ID的Completer引用
// ignore: unused_element
Completer<String>? _backendBuildIdCompleter;

// 存储销毁实例的Completer引用
Completer<void>? _destroyCompleter;

// 存储最后使用的bindings引用
QnnWrapperBindings? _lastBindings;

// 存储createAsync方法中的completer
Completer<Qnn>? _createAsyncCompleter;

// 创建完成的静态回调函数

// createAsync方法的静态回调函数
@pragma('vm:entry-point') // 确保回调函数不会被优化掉
void _createAsyncCallback(
  ffi.Pointer<QnnSampleApp> app,
  ffi.Pointer<ffi.Void> userData,
) {
  print(
    '_createAsyncCallback被调用! app地址: ${app.address}, userData地址: ${userData.address}',
  );

  // 获取完成器的引用
  final completer = _createAsyncCompleter;
  if (completer != null && !completer.isCompleted) {
    print('completer存在且未完成，即将完成');
    // 因为无法从userData获取bindings，所以我们使用全局变量
    if (_lastBindings != null) {
      print('_lastBindings不为空，创建Qnn实例');
      completer.complete(Qnn._(_lastBindings!, app));
    } else {
      print('警告: _lastBindings为空!');
      completer.completeError('QnnWrapperBindings is null');
    }
  } else {
    print('警告: completer为空或已完成! ${completer?.isCompleted}');
  }
}

// 获取浮点输出的静态回调函数

// 获取后端构建ID的静态回调函数

// 销毁实例的静态回调函数
void _destroyCallback(int status, ffi.Pointer<ffi.Void> userData) {
  final completer = _destroyCompleter;
  if (completer != null && !completer.isCompleted) {
    completer.complete();
  }
}

/// 用于包装 QNN API 的 Dart 接口，内部调用 FFI 生成的绑定函数。
class Qnn {
  final QnnWrapperBindings _bindings;
  final ffi.Pointer<QnnSampleApp> _app;

  Qnn._(this._bindings, this._app);

  /// 加载QNN库
  static ffi.DynamicLibrary? _loadLibrary() {
    if (Platform.isAndroid) {
      try {
        // 尝试加载库文件，根据当前CPU架构加载对应的SO文件
        return ffi.DynamicLibrary.open("libqnn_wrapper.so");
      } catch (e) {
        print("加载SO库失败: $e");
        return null;
      }
    } else {
      print("当前平台不支持: ${Platform.operatingSystem}");
      return null;
    }
  }

  /// 初始化并获取Hexagon库文件路径
  /// 将Hexagon库文件从assets复制到应用数据目录中
  /// 返回Hexagon库文件目录路径
  static Future<String> initializeHexagonLibs(
    String backendPath,
    QnnWrapperBindings bindings,
  ) async {
    try {
      // 获取应用数据目录
      final appDir = await getApplicationDocumentsDirectory();

      // 创建hexagon库目录
      final hexagonDir = Directory('${appDir.path}/hexagon_libs_path');
      if (!await hexagonDir.exists()) {
        await hexagonDir.create(recursive: true);
      }
      final hexagonLibsPath = hexagonDir.path;

      // 创建标记文件路径
      final markerFile = File('${appDir.path}/hexagon_libs_copied');

      // 检查是否已经复制过
      if (await markerFile.exists()) {
        print('Hexagon库文件已经复制过，跳过');
        return hexagonLibsPath;
      }

      // 获取HTP架构版本号
      final archVersion = bindings.qnn_get_htp_arch_version(
        backendPath.toNativeUtf8().cast<ffi.Char>(),
      );
      print('HTP架构版本: $archVersion');
      if (archVersion == -1) {
        print('获取HTP架构版本失败');
        return '';
      }

      // 获取assets包中的所有hexagon库文件
      final targetVersionPath =
          'packages/flutter_qnn_lib/assets/hexagon-libs/hexagon-v$archVersion/unsigned/';
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);

      // 查找所有hexagon库文件
      final hexagonFiles =
          manifestMap.keys
              .where((String key) => key.startsWith(targetVersionPath))
              .toList();

      if (hexagonFiles.isEmpty) {
        print('没有找到Hexagon库文件，检查以下路径: $targetVersionPath');
        print('可用assets: ${manifestMap.keys.join(', ')}');
        return hexagonLibsPath;
      }

      // 复制每个库文件
      for (String assetPath in hexagonFiles) {
        final filename = assetPath.split('/').last;
        final targetFile = File('$hexagonLibsPath/$filename');

        // 加载asset文件
        final ByteData data = await rootBundle.load(assetPath);
        final buffer = data.buffer.asUint8List();

        // 写入到目标文件
        await targetFile.writeAsBytes(buffer);
        print('已复制: $filename 到 ${targetFile.path}');
      }

      // 列出复制后的目录内容
      final hexagonDir2 = Directory(hexagonLibsPath);
      if (await hexagonDir2.exists()) {
        print('Hexagon库目录内容:');
        await for (var entity in hexagonDir2.list()) {
          print('- ${entity.path}');
        }
      }

      // 创建标记文件，表示已完成复制
      await markerFile.writeAsString('done');
      print('所有Hexagon库文件复制完成');

      return hexagonLibsPath;
    } catch (e) {
      print('复制Hexagon库文件失败: $e');
      // 出错时返回空路径
      return '';
    }
  }

  /// 静态方法创建 QnnSampleAppWrapper 对象
  /// [backendPath] 与 [modelPath] 为文件路径，传入 Dart 字符串
  /// [outputDataType] 与 [inputDataType] 为枚举类型
  /// [dataDir] 为应用数据目录路径，用于切换工作目录
  /// [lib] 为已打开的 DynamicLibrary，如果为null则尝试自动加载
  static Future<Qnn?> _create(
    String backendPath,
    String modelPath, {
    QnnOutputDataType outputDataType =
        QnnOutputDataType.QNN_OUTPUT_DATA_TYPE_FLOAT_ONLY,
    QnnInputDataType inputDataType = QnnInputDataType.QNN_INPUT_DATA_TYPE_FLOAT,
    ffi.DynamicLibrary? lib,
  }) async {
    // 如果未提供lib参数，则尝试加载库
    final library = lib ?? _loadLibrary();
    if (library == null) {
      return null;
    }

    final bindings = QnnWrapperBindings(library);
    // 将 Dart 字符串转换为 native 字符串
    final backendPathPtr = backendPath.toNativeUtf8().cast<ffi.Char>();
    final modelPathPtr = modelPath.toNativeUtf8().cast<ffi.Char>();

    // 准备数据目录路径参数
    String? dataDir;
    if (backendPath.toLowerCase().contains("htp")) {
      dataDir = await initializeHexagonLibs(backendPath, bindings);
    } else if (backendPath.toLowerCase().contains("gpu")) {
      dataDir = getApplicationCacheDirectory().toString();
    }

    ffi.Pointer<ffi.Char> dataDirPtr = ffi.nullptr;
    if (dataDir != null && dataDir.isNotEmpty) {
      dataDirPtr = dataDir.toNativeUtf8().cast<ffi.Char>();
    }

    final appPtr = bindings.qnn_sample_app_create(
      backendPathPtr,
      modelPathPtr,
      outputDataType,
      inputDataType,
      dataDirPtr,
    );
    print('appPtr: ${appPtr.address}');
    malloc.free(backendPathPtr);
    malloc.free(modelPathPtr);
    if (dataDirPtr != ffi.nullptr) {
      malloc.free(dataDirPtr);
    }

    if (appPtr.address == 0) {
      return null;
    }
    print('QnnSampleAppWrapper create success');
    return Qnn._(bindings, appPtr);
  }

  /// 静态方法创建 QnnSampleAppWrapper 对象
  /// [backendType] 为后端类型
  /// [modelPath] 为模型文件路径
  /// [outputDataType] 与 [inputDataType] 为枚举类型
  /// [lib] 为已打开的 DynamicLibrary，如果为null则尝试自动加载
  static Future<Qnn?> create(
    QnnBackendType backendType,
    String modelPath, {
    QnnOutputDataType outputDataType =
        QnnOutputDataType.QNN_OUTPUT_DATA_TYPE_FLOAT_ONLY,
    QnnInputDataType inputDataType = QnnInputDataType.QNN_INPUT_DATA_TYPE_FLOAT,
    ffi.DynamicLibrary? lib,
  }) async {
    final nativeLibDir = await PlatformUtils.getNativeLibraryDir();
    if (nativeLibDir == null) {
      print('获取原生库目录失败');
      return null;
    }

    return _create(
      "$nativeLibDir/libQnn${backendType.backendPath}.so",
      modelPath,
      outputDataType: outputDataType,
      inputDataType: inputDataType,
      lib: lib,
    );
  }

  // 创建QNN实例的异步版本
  static Future<Qnn?> createAsync(
    QnnBackendType backendType,
    String modelPath, {
    QnnOutputDataType outputDataType =
        QnnOutputDataType.QNN_OUTPUT_DATA_TYPE_FLOAT_ONLY,
    QnnInputDataType inputDataType = QnnInputDataType.QNN_INPUT_DATA_TYPE_FLOAT,
    ffi.DynamicLibrary? lib,
  }) async {
    print('开始调用createAsync');

    // 清理之前可能存在的全局状态
    _createAsyncCompleter = null;
    _lastBindings = null;

    final completer = Completer<Qnn>();
    _createAsyncCompleter = completer;

    // 如果未提供lib参数，则尝试加载库
    final library = lib ?? _loadLibrary();
    if (library == null) {
      print('加载库失败');
      return null;
    }

    final bindings = QnnWrapperBindings(library);
    print('QnnWrapperBindings创建成功');
    _lastBindings = bindings; // 存储bindings到全局变量
    print('存储bindings到全局变量: $_lastBindings');

    final nativeLibDir = await PlatformUtils.getNativeLibraryDir();
    if (nativeLibDir == null) {
      print('获取原生库目录失败');
      return null;
    }

    final backendPath = "$nativeLibDir/libQnn${backendType.backendPath}.so";
    print('backend路径: $backendPath');

    // 将 Dart 字符串转换为 native 字符串
    final backendPathPtr = backendPath.toNativeUtf8().cast<ffi.Char>();
    final modelPathPtr = modelPath.toNativeUtf8().cast<ffi.Char>();

    // 准备数据目录路径参数 - 与同步版本一致
    String? dataDir;
    if (backendPath.toLowerCase().contains("htp")) {
      dataDir = await initializeHexagonLibs(backendPath, bindings);
      print('初始化Hexagon库: $dataDir');
    } else if (backendPath.toLowerCase().contains("gpu")) {
      dataDir = (await getApplicationCacheDirectory()).path;
    }
    ffi.Pointer<ffi.Char> dataDirPtr = ffi.nullptr;
    if (dataDir != null && dataDir.isNotEmpty) {
      dataDirPtr = dataDir.toNativeUtf8().cast<ffi.Char>();
    }

    // 使用NativeCallable.listener创建跨线程安全的回调
    print('创建NativeCallable.listener');
    late final NativeCallable<
      ffi.Void Function(ffi.Pointer<QnnSampleApp>, ffi.Pointer<ffi.Void>)
    >
    callback;

    void onAppCreated(
      ffi.Pointer<QnnSampleApp> app,
      ffi.Pointer<ffi.Void> userData,
    ) {
      print('跨线程回调被调用! app地址: ${app.address}');
      if (!completer.isCompleted) {
        if (_lastBindings != null) {
          print('创建Qnn实例');
          completer.complete(Qnn._(_lastBindings!, app));
        } else {
          print('警告: _lastBindings为空!');
          completer.completeError('QnnWrapperBindings is null');
        }
      } else {
        print('警告: completer已完成!');
      }
      // 关闭NativeCallable以避免内存泄漏
      callback.close();
    }

    callback = NativeCallable.listener(onAppCreated);

    print('正在调用qnn_sample_app_create_async');
    bindings.qnn_sample_app_create_async(
      backendPathPtr,
      modelPathPtr,
      outputDataType,
      inputDataType,
      dataDirPtr,
      callback.nativeFunction,
      ffi.nullptr,
    );
    print('qnn_sample_app_create_async调用完成，等待回调');

    // 释放内存，与同步版本一致
    malloc.free(backendPathPtr);
    malloc.free(modelPathPtr);
    if (dataDirPtr != ffi.nullptr) {
      malloc.free(dataDirPtr);
    }

    try {
      final result = await completer.future;
      print('收到结果，创建完成');
      return result;
    } catch (e) {
      print('创建QNN实例时发生错误: $e');
      return null;
    } finally {
      // 清理全局状态
      _createAsyncCompleter = null;
    }
  }

  QnnStatus initializeProfiling() =>
      _bindings.qnn_sample_app_initialize_profiling(_app);

  QnnStatus createContext() => _bindings.qnn_sample_app_create_context(_app);

  QnnStatus composeGraphs() => _bindings.qnn_sample_app_compose_graphs(_app);

  QnnStatus finalizeGraphs() => _bindings.qnn_sample_app_finalize_graphs(_app);

  QnnStatus executeGraphs() => _bindings.qnn_sample_app_execute_graphs(_app);

  QnnStatus registerOpPackages() =>
      _bindings.qnn_sample_app_register_op_packages(_app);

  QnnStatus createFromBinary() =>
      _bindings.qnn_sample_app_create_from_binary(_app);

  /// 保存二进制文件，输出路径与二进制名称均为 Dart 字符串
  QnnStatus saveBinary(String outputPath, String binaryName) {
    final outputPathPtr = outputPath.toNativeUtf8().cast<ffi.Char>();
    final binaryNamePtr = binaryName.toNativeUtf8().cast<ffi.Char>();
    final res = _bindings.qnn_sample_app_save_binary(
      _app,
      outputPathPtr,
      binaryNamePtr,
    );
    malloc.free(outputPathPtr);
    malloc.free(binaryNamePtr);
    return res;
  }

  QnnStatus freeContext() => _bindings.qnn_sample_app_free_context(_app);

  QnnStatus terminateBackend() =>
      _bindings.qnn_sample_app_terminate_backend(_app);

  QnnStatus freeGraphs() => _bindings.qnn_sample_app_free_graphs(_app);

  /// 获取后端生成的版本号字符串
  String getBackendBuildId() {
    final idPtr = _bindings.qnn_sample_app_get_backend_build_id(_app);
    // 将 native 字符串转换为 Dart 字符串
    final idStr = idPtr.cast<Utf8>().toDartString();
    // 注意：根据接口说明，返回的字符串需要调用者释放内存，请根据具体情况调用相应的释放函数
    return idStr;
  }

  QnnStatus isDevicePropertySupported() =>
      _bindings.qnn_sample_app_is_device_property_supported(_app);

  QnnStatus createDevice() => _bindings.qnn_sample_app_create_device(_app);

  QnnStatus freeDevice() => _bindings.qnn_sample_app_free_device(_app);

  /// 包装加载浮点数输入张量接口
  /// [inputs] 为二维数组，每个内层 List<double> 表示一个输入张量
  /// [graphIdx] 为图索引
  QnnStatus loadFloatInputs(List<List<double>> inputs, int graphIdx) {
    final numInputs = inputs.length;
    // 分配存放各输入数组指针的内存
    final Pointer<ffi.Pointer<ffi.Float>> inputsPtr = malloc
        .allocate<ffi.Pointer<ffi.Float>>(
          numInputs * ffi.sizeOf<ffi.Pointer<ffi.Float>>(),
        );
    // 分配存放每个输入大小的内存
    final Pointer<ffi.Size> sizesPtr = malloc.allocate<ffi.Size>(
      numInputs * ffi.sizeOf<ffi.Size>(),
    );

    // 存储临时分配的每个输入数组，用于最后释放
    final List<ffi.Pointer<ffi.Float>> allocatedArrays = [];

    for (int i = 0; i < numInputs; i++) {
      final currentList = inputs[i];
      final length = currentList.length;
      // 为当前输入数组分配内存
      final Pointer<ffi.Float> arrPtr = malloc.allocate<ffi.Float>(
        length * ffi.sizeOf<ffi.Float>(),
      );
      for (int j = 0; j < length; j++) {
        arrPtr[j] = currentList[j];
      }
      allocatedArrays.add(arrPtr);
      // 将数组指针写入 inputsPtr
      inputsPtr.elementAt(i).value = arrPtr;
      // 设置当前数组的长度
      sizesPtr.elementAt(i).value = length;
    }

    final status = _bindings.qnn_sample_app_load_float_inputs(
      _app,
      inputsPtr,
      sizesPtr,
      numInputs,
      graphIdx,
    );

    // 释放临时分配的内存
    for (final ptr in allocatedArrays) {
      malloc.free(ptr);
    }
    malloc.free(inputsPtr);
    malloc.free(sizesPtr);
    return status;
  }

  /// 包装加载浮点数输入张量接口，直接使用 Native 指针避免数据拷贝，size 数组由 Dart 提供。
  /// 调用者负责管理 inputsPtrs 列表中的指针以及它们指向的数据的生命周期。
  /// [inputsPtrs] 一个包含输入张量 float 数组指针的列表。
  /// [sizes] Dart List，包含每个 float 数组的大小。
  /// [graphIdx] 为图索引。
  QnnStatus loadFloatInputsFromPointers(
    List<ffi.Pointer<ffi.Float>> inputsPtrs,
    List<int> sizes,
    int graphIdx,
  ) {
    final numInputs = inputsPtrs.length;
    // 检查输入数量是否与 size 列表长度匹配
    if (numInputs != sizes.length) {
      print(
        'Error: inputsPtrs length ($numInputs) does not match sizes list length (${sizes.length})',
      );
      return QnnStatus.QNN_STATUS_FAILURE; // 或者抛出异常
    }

    // 分配内存用于存放 size 数组
    final Pointer<ffi.Size> sizesPtr = malloc.allocate<ffi.Size>(
      numInputs * ffi.sizeOf<ffi.Size>(),
    );
    // 分配内存用于存放输入指针数组
    final Pointer<ffi.Pointer<ffi.Float>> inputsPtrNative = malloc
        .allocate<ffi.Pointer<ffi.Float>>(
          numInputs * ffi.sizeOf<ffi.Pointer<ffi.Float>>(),
        );

    // 将 Dart List<int> 复制到 Native 指针
    // 将 Dart List<Pointer<Float>> 复制到 Native 指针
    for (int i = 0; i < numInputs; i++) {
      sizesPtr[i] = sizes[i];
      inputsPtrNative.elementAt(i).value = inputsPtrs[i];
    }

    final status = _bindings.qnn_sample_app_load_float_inputs(
      _app,
      inputsPtrNative, // 传递 Native 指针数组
      sizesPtr,
      numInputs,
      graphIdx,
    );

    // 释放 size 数组内存和临时的输入指针数组内存
    malloc.free(sizesPtr);
    malloc.free(inputsPtrNative);

    // 注意：此函数不负责释放传入的 inputsPtrs 列表中的指针及其指向的数据内存。
    return status;
  }

  /// 包装获取浮点数输出张量接口
  /// 返回值为二维 List，每个内层 List<double> 表示一个输出张量
  List<List<double>> getFloatOutputs(int graphIdx) {
    // 分配内存用于接收输出数组指针（由底层分配，需要后续释放）
    final Pointer<ffi.Pointer<ffi.Pointer<ffi.Float>>> outputsPtr = malloc
        .allocate<ffi.Pointer<ffi.Pointer<ffi.Float>>>(
          ffi.sizeOf<ffi.Pointer<ffi.Pointer<ffi.Float>>>(),
        );
    // 分配内存用于接收各输出数组大小指针
    final Pointer<ffi.Pointer<ffi.Size>> sizesPtr = malloc
        .allocate<ffi.Pointer<ffi.Size>>(ffi.sizeOf<ffi.Pointer<ffi.Size>>());

    // 分配内存用于接收输出张量数量
    final Pointer<ffi.Size> numOutputsPtr = malloc.allocate<ffi.Size>(
      ffi.sizeOf<ffi.Size>(),
    );

    final status = _bindings.qnn_sample_app_get_float_outputs(
      _app,
      outputsPtr,
      sizesPtr,
      numOutputsPtr,
      graphIdx,
    );
    final numOutputs = numOutputsPtr.value;
    final List<List<double>> results = [];

    if (status != QnnStatus.QNN_STATUS_SUCCESS) {
      // 释放分配的内存
      malloc.free(outputsPtr);
      malloc.free(sizesPtr);
      malloc.free(numOutputsPtr);
      return results;
    }

    // 获取输出数组和大小数组
    final Pointer<ffi.Pointer<ffi.Float>> outputsArray = outputsPtr.value;
    final Pointer<ffi.Size> sizesArray = sizesPtr.value;

    for (int i = 0; i < numOutputs; i++) {
      final arrPtr = outputsArray.elementAt(i).value;
      final length = sizesArray.elementAt(i).value;
      final List<double> outputList = [];
      for (int j = 0; j < length; j++) {
        outputList.add(arrPtr[j]);
      }
      results.add(outputList);
      // 释放底层分配的每个输出数组内存
      malloc.free(arrPtr);
    }

    // 释放输出数组指针和大小数组指针的内存
    malloc.free(outputsArray);
    malloc.free(sizesArray);
    malloc.free(outputsPtr);
    malloc.free(sizesPtr);
    malloc.free(numOutputsPtr);

    return results;
  }

  /// 销毁 QnnSampleApp 对象，释放资源
  void destroy() {
    _bindings.qnn_sample_app_destroy(_app);
  }
}

extension QnnAsync on Qnn {
  // 获取浮点输出的异步版本
  Future<List<List<double>>> getFloatOutputsAsync(int graphIdx) {
    final completer = Completer<List<List<double>>>();
    _floatOutputsCompleter = completer;

    // 使用NativeCallable.listener创建跨线程安全的回调
    late final NativeCallable<QnnFloatOutputCallbackFunction> callback;

    void onOutputReady(
      int status,
      ffi.Pointer<ffi.Pointer<ffi.Float>> outputs,
      ffi.Pointer<ffi.Size> sizes,
      int numOutputs,
      ffi.Pointer<ffi.Void> userData,
    ) {
      print('获取输出完成回调被调用，状态: $status, 输出数量: $numOutputs');
      if (status == QnnStatus.QNN_STATUS_SUCCESS.value) {
        final results = <List<double>>[];

        for (var i = 0; i < numOutputs; i++) {
          final arrPtr = outputs.elementAt(i).value;
          final length = sizes.elementAt(i).value;
          final outputList = <double>[];

          // 检查 arrPtr 是否为 nullptr，虽然理论上成功时不应为 nullptr
          if (arrPtr != nullptr) {
            for (var j = 0; j < length; j++) {
              outputList.add(arrPtr[j]);
            }
            // 释放单个输出数组的内存 (float*)
            malloc.free(arrPtr);
          }
          results.add(outputList);
        }

        // 释放 outputs 指针数组 (Pointer<Pointer<Float>>)
        malloc.free(outputs);
        // 释放 sizes 指针数组 (Pointer<Size>)
        malloc.free(sizes);

        completer.complete(results);
      } else {
        completer.complete(<List<double>>[]);
      }
      // 关闭NativeCallable以避免内存泄漏
      callback.close();
    }

    callback = NativeCallable.listener(onOutputReady);

    _bindings.qnn_sample_app_get_float_outputs_async(
      _app,
      graphIdx,
      callback.nativeFunction,
      ffi.nullptr,
    );

    return completer.future;
  }

  // 获取后端构建ID的异步版本
  Future<String> getBackendBuildIdAsync() {
    final completer = Completer<String>();
    _backendBuildIdCompleter = completer;

    // 使用NativeCallable.listener创建跨线程安全的回调
    late final NativeCallable<QnnStringCallbackFunction> callback;

    void onBuildIdReady(
      int status,
      ffi.Pointer<ffi.Char> result,
      ffi.Pointer<ffi.Void> userData,
    ) {
      print('获取构建ID回调被调用，状态: $status');
      if (status == QnnStatus.QNN_STATUS_SUCCESS.value) {
        final str = result.cast<Utf8>().toDartString();
        malloc.free(result);
        completer.complete(str);
      } else {
        completer.complete('');
      }
      // 关闭NativeCallable以避免内存泄漏
      callback.close();
    }

    callback = NativeCallable.listener(onBuildIdReady);

    _bindings.qnn_sample_app_get_backend_build_id_async(
      _app,
      callback.nativeFunction,
      ffi.nullptr,
    );

    return completer.future;
  }

  // 销毁实例的异步版本
  Future<void> destroyAsync() {
    final completer = Completer<void>();
    _destroyCompleter = completer;

    // 使用NativeCallable.listener创建跨线程安全的回调
    late final NativeCallable<QnnAsyncCallbackFunction> callback;

    void onDestroyed(int status, ffi.Pointer<ffi.Void> userData) {
      print('销毁完成回调被调用，状态: $status');
      completer.complete();
      // 关闭NativeCallable以避免内存泄漏
      callback.close();
    }

    callback = NativeCallable.listener(onDestroyed);

    _bindings.qnn_sample_app_destroy_async(
      _app,
      callback.nativeFunction,
      ffi.nullptr,
    );

    return completer.future;
  }

  // 加载浮点输入的异步版本
  Future<QnnStatus> loadFloatInputsAsync(
    List<List<double>> inputs,
    int graphIdx,
  ) {
    final completer = Completer<QnnStatus>();

    // 使用NativeCallable.listener创建跨线程安全的回调
    late final NativeCallable<QnnAsyncCallbackFunction> callback;

    // 分配存放各输入数组指针的内存
    final numInputs = inputs.length;
    final Pointer<ffi.Pointer<ffi.Float>> inputsPtr = malloc
        .allocate<ffi.Pointer<ffi.Float>>(
          numInputs * ffi.sizeOf<ffi.Pointer<ffi.Float>>(),
        );
    // 分配存放每个输入大小的内存
    final Pointer<ffi.Size> sizesPtr = malloc.allocate<ffi.Size>(
      numInputs * ffi.sizeOf<ffi.Size>(),
    );

    // 存储临时分配的每个输入数组，用于最后释放
    final List<ffi.Pointer<ffi.Float>> allocatedArrays = [];

    for (int i = 0; i < numInputs; i++) {
      final currentList = inputs[i];
      final length = currentList.length;
      // 为当前输入数组分配内存
      final Pointer<ffi.Float> arrPtr = malloc.allocate<ffi.Float>(
        length * ffi.sizeOf<ffi.Float>(),
      );
      for (int j = 0; j < length; j++) {
        arrPtr[j] = currentList[j];
      }
      allocatedArrays.add(arrPtr);
      // 将数组指针写入 inputsPtr
      inputsPtr.elementAt(i).value = arrPtr;
      // 设置当前数组的长度
      sizesPtr.elementAt(i).value = length;
    }

    void onInputsLoaded(int status, ffi.Pointer<ffi.Void> userData) {
      print('加载输入完成回调被调用，状态: $status');
      completer.complete(QnnStatus.fromValue(status));

      // 释放临时分配的内存
      for (final ptr in allocatedArrays) {
        malloc.free(ptr);
      }
      malloc.free(inputsPtr);
      malloc.free(sizesPtr);

      // 关闭NativeCallable以避免内存泄漏
      callback.close();
    }

    callback = NativeCallable.listener(onInputsLoaded);

    _bindings.qnn_sample_app_load_float_inputs_async(
      _app,
      inputsPtr,
      sizesPtr,
      numInputs,
      graphIdx,
      callback.nativeFunction,
      ffi.nullptr,
    );

    return completer.future;
  }

  // 加载浮点输入的异步版本，直接使用 Native 指针，size 数组由 Dart 提供
  Future<QnnStatus> loadFloatInputsFromPointersAsync(
    List<ffi.Pointer<ffi.Float>> inputsPtrs,
    List<int> sizes,
    int graphIdx,
  ) {
    final completer = Completer<QnnStatus>();
    final numInputs = inputsPtrs.length;

    // 检查输入数量是否与 size 列表长度匹配
    if (numInputs != sizes.length) {
      print(
        'Error: inputsPtrs length ($numInputs) does not match sizes list length (${sizes.length})',
      );
      // 异步返回错误
      completer.complete(QnnStatus.QNN_STATUS_FAILURE);
      return completer.future;
    }

    // 分配内存用于存放 size 数组
    final Pointer<ffi.Size> sizesPtr = malloc.allocate<ffi.Size>(
      numInputs * ffi.sizeOf<ffi.Size>(),
    );
    // 分配内存用于存放输入指针数组
    final Pointer<ffi.Pointer<ffi.Float>> inputsPtrNative = malloc
        .allocate<ffi.Pointer<ffi.Float>>(
          numInputs * ffi.sizeOf<ffi.Pointer<ffi.Float>>(),
        );

    // 将 Dart List<int> 复制到 Native 指针
    // 将 Dart List<Pointer<Float>> 复制到 Native 指针
    for (int i = 0; i < numInputs; i++) {
      sizesPtr[i] = sizes[i];
      inputsPtrNative.elementAt(i).value = inputsPtrs[i];
    }

    // 使用NativeCallable.listener创建跨线程安全的回调
    late final NativeCallable<QnnAsyncCallbackFunction> callback;

    void onInputsLoaded(int status, ffi.Pointer<ffi.Void> userData) {
      print('加载输入(指针列表, Dart sizes)完成回调被调用，状态: $status');
      completer.complete(QnnStatus.fromValue(status));

      // 在回调中释放 sizesPtr 内存和临时的输入指针数组内存
      malloc.free(sizesPtr);
      malloc.free(inputsPtrNative);
      // 注意：不在此处释放 inputsPtrs 列表中的指针，它们由调用者管理
      // 关闭NativeCallable以避免内存泄漏
      callback.close();
    }

    callback = NativeCallable.listener(onInputsLoaded);

    _bindings.qnn_sample_app_load_float_inputs_async(
      _app,
      inputsPtrNative, // 传递分配好的 Native 指针数组
      sizesPtr, // 传递分配好的 Native 指针
      numInputs,
      graphIdx,
      callback.nativeFunction,
      ffi.nullptr,
    );

    return completer.future;
  }

  // 执行图的异步版本
  Future<QnnStatus> executeGraphsAsync() {
    final completer = Completer<QnnStatus>();

    // 使用NativeCallable.listener创建跨线程安全的回调
    late final NativeCallable<QnnAsyncCallbackFunction> callback;

    void onGraphsExecuted(int status, ffi.Pointer<ffi.Void> userData) {
      print('执行图完成回调被调用，状态: $status');
      completer.complete(QnnStatus.fromValue(status));
      // 关闭NativeCallable以避免内存泄漏
      callback.close();
    }

    callback = NativeCallable.listener(onGraphsExecuted);

    _bindings.qnn_sample_app_execute_graphs_async(
      _app,
      callback.nativeFunction,
      ffi.nullptr,
    );

    return completer.future;
  }
}
