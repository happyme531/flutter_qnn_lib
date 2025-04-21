import 'dart:async'; // 导入 Timer
import 'dart:math'; // 导入 Random
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 导入 HapticFeedback
import 'package:package_info_plus/package_info_plus.dart'; // <-- 添加导入
import 'package:flutter_qnn_lib/qnn_types.dart';
import 'settings_manager.dart';
import 'model_manager.dart';
import 'database/image_tag_database.dart';
import 'easter_egg_animation.dart'; // 导入彩蛋文件

class SettingsPage extends StatefulWidget {
  final Function? onBackendChanged;

  const SettingsPage({Key? key, this.onBackendChanged}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SettingsManager _settingsManager = SettingsManager();
  bool _isLoading = false;
  int _qnnSdkTapCount = 0; // QNN SDK 列表项点击计数器
  DateTime? _lastQnnSdkTapTime; // 上次点击时间
  Color? _tempIconColor; // 用于临时改变图标颜色
  Timer? _iconColorResetTimer; // 用于重置图标颜色的计时器
  final Random _random = Random(); // 用于随机颜色
  final List<Color> _glitchColors = [
    Colors.cyanAccent,
    Colors.purpleAccent,
    Colors.limeAccent,
    Colors.pinkAccent,
    Colors.tealAccent,
  ]; // 奇怪的颜色列表
  String _appVersion = '...'; // <-- 添加状态变量存储版本号

  @override
  void initState() {
    // <-- 添加 initState
    super.initState();
    _loadAppVersion();
  }

  // <-- 添加加载版本号的方法
  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = packageInfo.version;
        });
      }
    } catch (e) {
      print('获取应用版本失败: $e');
      if (mounted) {
        setState(() {
          _appVersion = '未知';
        });
      }
    }
  }

  @override
  void dispose() {
    _iconColorResetTimer?.cancel(); // 在页面销毁时取消计时器
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  // 后端选择设置
                  _buildSection(
                    title: '推理后端设置',
                    icon: Icons.settings_applications,
                    children: [_buildBackendSelector()],
                  ),

                  // 数据管理 (Renamed and added DB deletion)
                  const SizedBox(height: 16),
                  _buildSection(
                    title: '数据管理', // Renamed Section
                    icon: Icons.storage, // Changed Icon
                    children: [
                      ListTile(
                        title: const Text('清除模型缓存'),
                        subtitle: const Text('删除保存的模型二进制缓存文件'),
                        leading: const Icon(
                          Icons.cached, // Changed icon for cache
                          color: Colors.orange,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _clearModelCache,
                      ),
                      const Divider(indent: 16, endIndent: 16), // Divider
                      ListTile(
                        // New ListTile for DB Deletion
                        title: const Text(
                          '清除标签数据库',
                          style: TextStyle(color: Colors.red),
                        ),
                        subtitle: const Text(
                          '删除所有已标记的图片标签和处理记录，此操作不可恢复！',
                          style: TextStyle(fontSize: 12),
                        ),
                        leading: const Icon(
                          Icons.delete_forever,
                          color: Colors.red,
                        ),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: Colors.red,
                        ),
                        onTap: _deleteDatabase, // Call the new method
                      ),
                    ],
                  ),

                  // 版本信息
                  const SizedBox(height: 32),
                  _buildSection(
                    title: '关于',
                    icon: Icons.info_outline,
                    children: [
                      ListTile(
                        title: const Text('版本'),
                        subtitle: Text(_appVersion), // <-- 使用状态变量
                        leading: Icon(
                          Icons.numbers,
                          color: Colors.blue.shade300,
                        ),
                      ),
                      ListTile(
                        title: const Text('基于QNN SDK开发'),
                        subtitle: const Text('Qualcomm AI Engine Direct'),
                        leading: Icon(
                          Icons.developer_board,
                          // 使用临时颜色（如果存在），否则使用默认颜色
                          color: _tempIconColor ?? Colors.blue.shade300,
                        ),
                        onTap: _handleQnnSdkTap, // 添加 onTap 回调
                      ),
                    ],
                  ),
                ],
              ),
    );
  }

  // 构建分区
  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(icon, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // 分割线
          const Divider(height: 1),
          // 子项
          ...children,
        ],
      ),
    );
  }

  // 构建后端选择器
  Widget _buildBackendSelector() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('选择推理后端:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            '不同后端有不同的性能和兼容性特点,根据设备选择合适的后端。一般只有HTP，GPU和CPU可以使用。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),

          // 后端选项
          ...QnnBackendType.values.map(
            (backend) => RadioListTile<QnnBackendType>(
              title: Text(_settingsManager.getBackendName(backend)),
              value: backend,
              groupValue: _settingsManager.backendType,
              onChanged: (newValue) => _changeBackend(newValue!),
            ),
          ),

          const SizedBox(height: 8),
          Text(
            '注意: 更改后端设置后需要重新加载模型。',
            style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
          ),
        ],
      ),
    );
  }

  // 更改后端
  Future<void> _changeBackend(QnnBackendType newBackend) async {
    if (newBackend == _settingsManager.backendType) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // 保存设置
      await _settingsManager.saveBackendType(newBackend);

      // 通知主页面更新后端
      if (widget.onBackendChanged != null) {
        widget.onBackendChanged!();
      }

      // 更新UI
      setState(() {});

      // 显示成功消息
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '已切换到${_settingsManager.getBackendName(newBackend)}后端',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('更改后端失败: $e')));
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 清除模型缓存
  Future<void> _clearModelCache() async {
    // 显示确认对话框
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('确认清除缓存'),
            content: const Text('这将删除所有模型的缓存文件，下次加载模型时将重新生成缓存。\n\n确定要继续吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('确定清除'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
            ],
          ),
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // 清除缓存
      final modelManager = ModelManager();
      final success = await modelManager.clearAllModelCache();

      // 显示结果
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '缓存已清除' : '清除缓存失败'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清除缓存出错: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 清除标签数据库 (New Method)
  Future<void> _deleteDatabase() async {
    // 显示确认对话框
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('确认删除数据库'),
            content: const Text(
              '将永久删除所有已识别的图片标签和处理记录！\n\n此操作无法撤销，确定要继续吗？',
              style: TextStyle(height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('确定删除'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
            ],
          ),
    );

    // 如果用户取消，则不执行任何操作
    if (confirm != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // 调用数据库实例的 clearDatabase 方法
      await ImageTagDatabase.instance.clearDatabase();

      // 显示成功消息
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('图片标签数据库已清除'),
            backgroundColor: Colors.green,
          ),
        );
        // 可选：如果需要，通知其他页面数据已更改
        // 例如，可以调用 widget.onBackendChanged 或添加一个新的回调
      }
    } catch (e) {
      // 显示错误消息
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清除数据库出错: $e'), backgroundColor: Colors.red),
        );
      }
      print('清除数据库出错: $e');
    } finally {
      // 无论成功或失败，都结束加载状态
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 处理 QNN SDK 列表项的点击事件
  void _handleQnnSdkTap() {
    final now = DateTime.now();
    const tapThreshold = Duration(milliseconds: 500);
    const requiredTaps = 7;

    if (_lastQnnSdkTapTime == null ||
        now.difference(_lastQnnSdkTapTime!) > tapThreshold) {
      _qnnSdkTapCount = 1;
    } else {
      _qnnSdkTapCount++;
    }

    _lastQnnSdkTapTime = now;

    // 取消之前的计时器（如果有）
    _iconColorResetTimer?.cancel();

    if (_qnnSdkTapCount >= requiredTaps) {
      print('触发彩蛋！');
      // 重置颜色并取消计时器
      setState(() {
        _tempIconColor = null;
      });
      _iconColorResetTimer?.cancel();

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const QualcommConfusionAnimation(),
        ),
      );
      _qnnSdkTapCount = 0;
      _lastQnnSdkTapTime = null;
    } else {
      // 提供奇怪的反馈 (1-6次点击)
      HapticFeedback.lightImpact(); // 轻微震动

      // 随机选择一个奇怪的颜色
      final randomColor = _glitchColors[_random.nextInt(_glitchColors.length)];

      setState(() {
        _tempIconColor = randomColor; // 设置临时颜色
      });

      // 设置计时器，在短暂延迟后恢复颜色
      _iconColorResetTimer = Timer(const Duration(milliseconds: 150), () {
        // 检查 widget 是否还在树中，防止 setState 错误
        if (mounted) {
          setState(() {
            _tempIconColor = null; // 恢复默认颜色
          });
        }
      });

      print('QNN SDK tap count: $_qnnSdkTapCount - Feedback applied');
    }
  }
}
