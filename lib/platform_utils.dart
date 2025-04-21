import 'package:flutter/services.dart';

/// 平台相关的工具类
class PlatformUtils {
  static const MethodChannel _channel = MethodChannel(
    'flutter_qnn_lib/app_context',
  );

  /// 获取Android原生库目录路径
  static Future<String?> getNativeLibraryDir() async {
    try {
      return await _channel.invokeMethod<String>('getNativeLibraryDir');
    } catch (e) {
      print('获取原生库目录失败: $e');
      return null;
    }
  }
}
