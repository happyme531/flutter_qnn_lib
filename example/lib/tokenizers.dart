import 'dart:ffi' as ffi;
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'dart:async';

import 'tokenizers_bindings_generated.dart';

/// Tokenizers类，封装tokenizers_c API
class Tokenizers {
  /// 静态单例实例
  static Tokenizers? _instance;

  /// 绑定的C API
  late TokenizersBindings _bindings;

  /// 共享库
  late ffi.DynamicLibrary _dylib;

  /// 私有构造函数
  Tokenizers._() {
    _dylib = _loadLibrary();
    _bindings = TokenizersBindings(_dylib);
  }

  /// 获取Tokenizers单例
  static Tokenizers get instance {
    _instance ??= Tokenizers._();
    return _instance!;
  }

  /// 加载动态库
  ffi.DynamicLibrary _loadLibrary() {
    if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libtokenizers_c_api.so');
    }
    throw UnsupportedError('当前平台不支持');
  }

  /// Tokenizer句柄
  ffi.Pointer<ffi.Void>? _handle;

  /// 从文件创建tokenizer
  Future<bool> create(String modelPath) async {
    // 确保先销毁之前的实例（如果有）
    if (_handle != null) {
      destroy();
    }

    final modelPathPointer = modelPath.toNativeUtf8();
    final handlePointer = calloc<Pointer<TokenizerHandle>>();

    try {
      final result = _bindings.TokenizerCreateFromFile(
        modelPathPointer.cast(),
        handlePointer as Pointer<TokenizerHandle>,
      );
      if (result == TokenizersStatus.TOKENIZERS_OK) {
        _handle = handlePointer.value.cast<ffi.Void>();
        return true;
      }

      // 获取错误信息
      final errorMsg =
          _bindings.TokenizerGetLastError().cast<Utf8>().toDartString();
      print('创建Tokenizer失败: $errorMsg');
      return false;
    } finally {
      calloc.free(modelPathPointer);
      calloc.free(handlePointer);
    }
  }

  /// 从内存blob创建tokenizer
  Future<bool> createFromBlob(Uint8List blob, TokenizerType type) async {
    // 确保先销毁之前的实例（如果有）
    if (_handle != null) {
      destroy();
    }

    final blobPointer = calloc<Uint8>(blob.length);
    final blobNative = blobPointer.asTypedList(blob.length);
    blobNative.setAll(0, blob);

    final handlePointer = calloc<Pointer<TokenizerHandle>>();

    try {
      final result = _bindings.TokenizerCreateFromBlob(
        blobPointer.cast(),
        blob.length,
        type,
        handlePointer as Pointer<TokenizerHandle>,
      );
      if (result == TokenizersStatus.TOKENIZERS_OK) {
        _handle = handlePointer.value.cast<ffi.Void>();
        return true;
      }

      // 获取错误信息
      final errorMsg =
          _bindings.TokenizerGetLastError().cast<Utf8>().toDartString();
      print('从blob创建Tokenizer失败: $errorMsg');
      return false;
    } finally {
      calloc.free(blobPointer);
      calloc.free(handlePointer);
    }
  }

  /// 销毁tokenizer
  void destroy() {
    if (_handle != null) {
      _bindings.TokenizerDestroy(_handle!.cast());
      _handle = null;
    }
  }

  /// 编码文本为token
  List<int>? encode(String text, {int maxTokens = 1024}) {
    if (_handle == null) {
      print('Tokenizer未初始化');
      return null;
    }

    final textPointer = text.toNativeUtf8();
    final tokens = calloc<Int32>(maxTokens);
    final numTokens = calloc<Size>();

    try {
      final result = _bindings.TokenizerEncode(
        _handle!.cast(),
        textPointer.cast(),
        tokens,
        numTokens,
        maxTokens,
      );

      if (result == TokenizersStatus.TOKENIZERS_OK) {
        final count = numTokens.value;
        return tokens.asTypedList(count).toList();
      }

      // 获取错误信息
      final errorMsg =
          _bindings.TokenizerGetLastError().cast<Utf8>().toDartString();
      print('编码失败: $errorMsg');
      return null;
    } finally {
      calloc.free(textPointer);
      calloc.free(tokens);
      calloc.free(numTokens);
    }
  }

  /// 解码token为文本
  String? decode(List<int> tokens) {
    if (_handle == null) {
      print('Tokenizer未初始化');
      return null;
    }

    final numTokens = tokens.length;
    final tokensPointer = calloc<Int32>(numTokens);

    // 复制token到本地内存
    for (var i = 0; i < numTokens; i++) {
      tokensPointer[i] = tokens[i];
    }

    // 最大文本长度设置为token数量的4倍（粗略估计）
    final maxTextLen = numTokens * 4;
    final textPointer = calloc<Char>(maxTextLen);
    final textLen = calloc<Size>();
    textLen.value = maxTextLen;

    try {
      final result = _bindings.TokenizerDecode(
        _handle!.cast(),
        tokensPointer,
        numTokens,
        textPointer,
        textLen,
      );

      if (result == TokenizersStatus.TOKENIZERS_OK) {
        return textPointer.cast<Utf8>().toDartString();
      }

      // 获取错误信息
      final errorMsg =
          _bindings.TokenizerGetLastError().cast<Utf8>().toDartString();
      print('解码失败: $errorMsg');
      return null;
    } finally {
      calloc.free(tokensPointer);
      calloc.free(textPointer);
      calloc.free(textLen);
    }
  }

  /// 将token ID转换为token字符串
  String? idToToken(int id) {
    if (_handle == null) {
      print('Tokenizer未初始化');
      return null;
    }

    // 假设token字符串最大长度为100
    final maxTokenLen = 100;
    final tokenPointer = calloc<Char>(maxTokenLen);
    final tokenLen = calloc<Size>();
    tokenLen.value = maxTokenLen;

    try {
      final result = _bindings.TokenizerIdToToken(
        _handle!.cast(),
        id,
        tokenPointer,
        tokenLen,
      );

      if (result == TokenizersStatus.TOKENIZERS_OK) {
        return tokenPointer.cast<Utf8>().toDartString();
      }

      // 获取错误信息
      final errorMsg =
          _bindings.TokenizerGetLastError().cast<Utf8>().toDartString();
      print('ID转Token失败: $errorMsg');
      return null;
    } finally {
      calloc.free(tokenPointer);
      calloc.free(tokenLen);
    }
  }

  /// 将token字符串转换为token ID
  int? tokenToId(String token) {
    if (_handle == null) {
      print('Tokenizer未初始化');
      return null;
    }

    final tokenPointer = token.toNativeUtf8();
    final idPointer = calloc<Int32>();

    try {
      final result = _bindings.TokenizerTokenToId(
        _handle!.cast(),
        tokenPointer.cast(),
        idPointer,
      );

      if (result == TokenizersStatus.TOKENIZERS_OK) {
        return idPointer.value;
      }

      // 获取错误信息
      final errorMsg =
          _bindings.TokenizerGetLastError().cast<Utf8>().toDartString();
      print('Token转ID失败: $errorMsg');
      return null;
    } finally {
      calloc.free(tokenPointer);
      calloc.free(idPointer);
    }
  }

  /// 获取词汇表大小
  int? getVocabSize() {
    if (_handle == null) {
      print('Tokenizer未初始化');
      return null;
    }

    final sizePointer = calloc<Size>();

    try {
      final result = _bindings.TokenizerGetVocabSize(
        _handle!.cast(),
        sizePointer,
      );

      if (result == TokenizersStatus.TOKENIZERS_OK) {
        return sizePointer.value;
      }

      // 获取错误信息
      final errorMsg =
          _bindings.TokenizerGetLastError().cast<Utf8>().toDartString();
      print('获取词汇表大小失败: $errorMsg');
      return null;
    } finally {
      calloc.free(sizePointer);
    }
  }

  /// 从文件异步创建tokenizer
  Future<bool> createAsync(String modelPath) async {
    // 确保先销毁之前的实例（如果有）
    if (_handle != null) {
      destroy();
    }

    final completer = Completer<bool>();
    final modelPathPointer = modelPath.toNativeUtf8();

    // 使用NativeCallable.listener创建跨线程安全的回调
    late final ffi.NativeCallable<
      ffi.Void Function(
        ffi.UnsignedInt status,
        TokenizerHandle handle,
        ffi.Pointer<ffi.Void> userData,
      )
    >
    callback;

    void onTokenizerCreated(
      int status,
      TokenizerHandle handle,
      ffi.Pointer<ffi.Void> userData,
    ) {
      try {
        if (status == TokenizersStatus.TOKENIZERS_OK.value) {
          _handle = handle.cast<ffi.Void>();
          completer.complete(true);
        } else {
          // 获取错误信息
          final errorMsg =
              _bindings.TokenizerGetLastError().cast<Utf8>().toDartString();
          print('异步创建Tokenizer失败: $errorMsg');
          completer.complete(false);
        }
      } finally {
        // 关闭NativeCallable以避免内存泄漏
        callback.close();
        malloc.free(modelPathPointer);
      }
    }

    callback = ffi.NativeCallable.listener(onTokenizerCreated);

    _bindings.TokenizerCreateFromFileAsync(
      modelPathPointer.cast(),
      callback.nativeFunction,
      ffi.nullptr,
    );

    return completer.future;
  }

  /// 从内存blob异步创建tokenizer
  Future<bool> createFromBlobAsync(Uint8List blob, TokenizerType type) async {
    // 确保先销毁之前的实例（如果有）
    if (_handle != null) {
      destroy();
    }

    final completer = Completer<bool>();
    final blobPointer = malloc<ffi.Uint8>(blob.length);
    final blobNative = blobPointer.asTypedList(blob.length);
    blobNative.setAll(0, blob);

    // 使用NativeCallable.listener创建跨线程安全的回调
    late final ffi.NativeCallable<
      ffi.Void Function(
        ffi.UnsignedInt status,
        TokenizerHandle handle,
        ffi.Pointer<ffi.Void> userData,
      )
    >
    callback;

    void onTokenizerCreated(
      int status,
      TokenizerHandle handle,
      ffi.Pointer<ffi.Void> userData,
    ) {
      try {
        if (status == TokenizersStatus.TOKENIZERS_OK.value) {
          _handle = handle.cast<ffi.Void>();
          completer.complete(true);
        } else {
          // 获取错误信息
          final errorMsg =
              _bindings.TokenizerGetLastError().cast<Utf8>().toDartString();
          print('异步从blob创建Tokenizer失败: $errorMsg');
          completer.complete(false);
        }
      } finally {
        // 关闭NativeCallable以避免内存泄漏
        callback.close();
        malloc.free(blobPointer);
      }
    }

    callback = ffi.NativeCallable.listener(onTokenizerCreated);

    _bindings.TokenizerCreateFromBlobAsync(
      blobPointer.cast(),
      blob.length,
      type,
      callback.nativeFunction,
      ffi.nullptr,
    );

    return completer.future;
  }
}
