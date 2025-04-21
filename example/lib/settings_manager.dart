import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_qnn_lib/qnn_types.dart';

class SettingsManager extends ChangeNotifier {
  // 单例模式
  static final SettingsManager _instance = SettingsManager._internal();
  factory SettingsManager() => _instance;
  SettingsManager._internal();

  // 设置常量键
  static const String _keyBackendType = 'backend_type';

  // 默认后端类型
  QnnBackendType _backendType = QnnBackendType.htp;

  // Getters
  QnnBackendType get backendType => _backendType;

  // 从持久化存储加载设置
  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final backendIndex = prefs.getInt(_keyBackendType) ?? _backendType.index;
      _backendType = QnnBackendType.values[backendIndex];
      print('设置已加载: 后端类型=${_backendType.toString()}');
    } catch (e) {
      print('加载设置失败: $e');
    }
  }

  // 保存后端类型设置
  Future<bool> saveBackendType(QnnBackendType backendType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyBackendType, backendType.index);
      _backendType = backendType;
      print('后端类型已保存: ${backendType.toString()}');
      notifyListeners();
      return true;
    } catch (e) {
      print('保存后端类型失败: $e');
      return false;
    }
  }

  // 获取后端类型的友好名称
  String getBackendName(QnnBackendType backend) {
    return backend.displayName;
  }

  // 设置后端类型
  Future<void> setBackendType(QnnBackendType type) async {
    if (_backendType != type) {
      _backendType = type;
      await saveBackendType(type);
      notifyListeners();
    }
  }
}
