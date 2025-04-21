/// QNN后端类型定义
enum QnnBackendType {
  /// Snapdragon™ CPU后端
  cpu,

  /// Hexagon™ DSP后端
  dsp,

  /// Adreno™ GPU后端
  gpu,

  /// Hexagon™ HTP后端
  htp,

  /// Snapdragon™ HTA后端
  hta,

  /// Snapdragon™ LPAI后端
  lpai,

  /// Saver后端
  saver,

  /// 未知后端
  unknown,
}

/// QNN后端类型的扩展方法
extension QnnBackendTypeExtension on QnnBackendType {
  /// 获取后端类型的友好名称
  String get displayName {
    switch (this) {
      case QnnBackendType.cpu:
        return 'Snapdragon™ CPU';
      case QnnBackendType.dsp:
        return 'Hexagon™ DSP';
      case QnnBackendType.gpu:
        return 'Adreno™ GPU';
      case QnnBackendType.htp:
        return 'Hexagon™ HTP';
      case QnnBackendType.hta:
        return 'Snapdragon™ HTA';
      case QnnBackendType.lpai:
        return 'Snapdragon™ LPAI';
      case QnnBackendType.saver:
        return 'Saver';
      case QnnBackendType.unknown:
        return 'Unknown';
    }
  }

  String get backendPath {
    switch (this) {
      case QnnBackendType.cpu:
        return 'Cpu';
      case QnnBackendType.dsp:
        return 'Dsp';
      case QnnBackendType.gpu:
        return 'Gpu';
      case QnnBackendType.htp:
        return 'Htp';
      case QnnBackendType.hta:
        return 'Hta';
      case QnnBackendType.lpai:
        return 'Lpai';
      case QnnBackendType.saver:
        return 'Saver';
      case QnnBackendType.unknown:
        return 'Unknown';
    }
  }
}
