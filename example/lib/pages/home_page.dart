import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../settings_page.dart';
import 'image_classification_page.dart';
import 'image_classification_search_page.dart';
import 'tokenizer_page.dart';
import 'vision_index.dart';
import 'image_vector_management_page.dart';
import 'image_search_page.dart';

// 定义应用页面枚举
enum AppPage {
  imageClassification,
  imageClassificationSearch,
  tokenizer,
  visionIndex,
  imageVectorManagement,
  imageSearch,
  // 未来可以添加更多功能页面
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // 当前页面
  AppPage _currentPage = AppPage.imageClassification;
  // 页面标题
  final Map<AppPage, String> _pageTitles = {
    AppPage.imageClassification: "图像分类",
    AppPage.imageClassificationSearch: "图像分类与搜索",
    AppPage.tokenizer: "分词器测试",
    AppPage.visionIndex: "视觉特征提取",
    AppPage.imageVectorManagement: "图像向量管理",
    AppPage.imageSearch: "以文搜图",
  };
  // 存储键
  static const String _lastPageKey = 'last_page';

  @override
  void initState() {
    super.initState();
    _loadLastPage();
  }

  // 加载上次使用的页面
  Future<void> _loadLastPage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastPageIndex = prefs.getInt(_lastPageKey);
      if (lastPageIndex != null &&
          lastPageIndex >= 0 &&
          lastPageIndex < AppPage.values.length) {
        if (AppPage.values[lastPageIndex] != null) {
          setState(() {
            _currentPage = AppPage.values[lastPageIndex];
          });
        } else {
          print("Warning: Saved page index $lastPageIndex is out of bounds.");
          setState(() {
            _currentPage = AppPage.values.first;
          });
          await _saveCurrentPage();
        }
      }
    } catch (e) {
      print('加载上次页面失败: $e');
      setState(() {
        _currentPage = AppPage.values.first;
      });
    }
  }

  // 保存当前页面
  Future<void> _saveCurrentPage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastPageKey, _currentPage.index);
    } catch (e) {
      print('保存当前页面失败: $e');
    }
  }

  // 切换页面
  void _navigateToPage(AppPage page) {
    if (_currentPage != page) {
      setState(() {
        _currentPage = page;
      });
      _saveCurrentPage();
    }
    Navigator.of(context).pop(); // 关闭抽屉
  }

  // 打开设置
  void _openSettings([bool fromDrawer = false]) {
    // 如果是从抽屉菜单调用的,则先关闭抽屉
    if (fromDrawer) {
      Navigator.of(context).pop();
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => SettingsPage(
              onBackendChanged: () {
                // 当后端改变时的回调
                setState(() {});
              },
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 获取 ScaffoldMessengerState 以便在需要时显示 SnackBar 等
    // 注意：直接在 build 方法中使用 Scaffold.of(context) 获取 drawer 可能在某些时机过早
    // 但在 FAB 的 onPressed 回调中使用通常是安全的

    return Scaffold(
      // 1. 移除 AppBar
      appBar: null,
      // 保持抽屉定义不变
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Colors.blue),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'QNN应用',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Flutter QNN Demo',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '基于高通神经网络SDK',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            _buildDrawerItem(
              icon: Icons.image,
              title: '图像分类',
              isSelected: _currentPage == AppPage.imageClassification,
              onTap: () => _navigateToPage(AppPage.imageClassification),
            ),
            _buildDrawerItem(
              icon: Icons.search,
              title: '图像分类与搜索',
              isSelected: _currentPage == AppPage.imageClassificationSearch,
              onTap: () => _navigateToPage(AppPage.imageClassificationSearch),
            ),
            _buildDrawerItem(
              icon: Icons.image_search,
              title: '以文搜图',
              isSelected: _currentPage == AppPage.imageSearch,
              onTap: () => _navigateToPage(AppPage.imageSearch),
            ),
            _buildDrawerItem(
              icon: Icons.data_object,
              title: '图像向量管理',
              isSelected: _currentPage == AppPage.imageVectorManagement,
              onTap: () => _navigateToPage(AppPage.imageVectorManagement),
            ),
            _buildDrawerItem(
              icon: Icons.text_fields,
              title: '分词器测试',
              isSelected: _currentPage == AppPage.tokenizer,
              onTap: () => _navigateToPage(AppPage.tokenizer),
            ),
            _buildDrawerItem(
              icon: Icons.remove_red_eye,
              title: '视觉特征提取',
              isSelected: _currentPage == AppPage.visionIndex,
              onTap: () => _navigateToPage(AppPage.visionIndex),
            ),
            const Divider(),
            _buildDrawerItem(
              icon: Icons.settings,
              title: '设置',
              onTap: () => _openSettings(true), // 从抽屉菜单打开
            ),
            _buildDrawerItem(
              icon: Icons.info_outline,
              title: '关于',
              onTap: () => _showAboutDialog(context),
            ),
          ],
        ),
      ),
      // 使用 SafeArea 包裹 body
      body: SafeArea(child: _buildCurrentPage()),
      // 2. 添加 FloatingActionButton, 用 Builder 包裹
      floatingActionButton: Builder(
        builder: (BuildContext fabContext) {
          // 使用 Builder 提供的 context
          return FloatingActionButton(
            mini: false, // 使用小号按钮
            tooltip: '打开菜单',
            child: const Icon(Icons.menu),
            onPressed: () {
              // 4. 使用 fabContext 打开抽屉
              Scaffold.of(fabContext).openDrawer();
            },
          );
        },
      ),
      // 3. 设置按钮位置到左下角
      floatingActionButtonLocation: FloatingActionButtonLocation.miniStartFloat,
    );
  }

  // 构建抽屉项
  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    bool isSelected = false,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: isSelected ? Colors.blue : null),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? Colors.blue : null,
          fontWeight: isSelected ? FontWeight.bold : null,
        ),
      ),
      onTap: onTap,
      selected: isSelected,
    );
  }

  // 构建当前页面
  Widget _buildCurrentPage() {
    switch (_currentPage) {
      case AppPage.imageClassification:
        return const ImageClassificationPage();
      case AppPage.imageClassificationSearch:
        return const ImageClassificationSearchPage();
      case AppPage.tokenizer:
        return const TokenizerPage();
      case AppPage.visionIndex:
        return const VisionIndexPage();
      case AppPage.imageVectorManagement:
        return const ImageVectorManagementPage();
      case AppPage.imageSearch:
        return const ImageSearchPage();
      default:
        return const Center(child: Text('选择一个功能页面'));
    }
  }

  // 显示关于对话框
  void _showAboutDialog(BuildContext context) async {
    Navigator.of(context).pop(); // 关闭抽屉

    // 获取应用信息
    final packageInfo = await PackageInfo.fromPlatform();

    showDialog(
      context: context,
      builder:
          (context) => AboutDialog(
            applicationName: packageInfo.appName,
            applicationVersion: packageInfo.version,
            applicationIcon: const FlutterLogo(size: 50),
            children: [
              const SizedBox(height: 16),
              const Text('基于高通神经网络(QNN)SDK的演示应用'),
              const SizedBox(height: 8),
              const Text('支持各种模型的推理和图像分类功能'),
            ],
          ),
    );
  }
}
