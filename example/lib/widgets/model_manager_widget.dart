import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../model_manager.dart';

class ModelManagerWidget extends StatefulWidget {
  final Function(String? modelPath) onModelSelected;
  final String? currentModelPath;
  final String taskType;

  const ModelManagerWidget({
    Key? key,
    required this.onModelSelected,
    required this.taskType,
    this.currentModelPath,
  }) : super(key: key);

  @override
  State<ModelManagerWidget> createState() => _ModelManagerWidgetState();
}

class _ModelManagerWidgetState extends State<ModelManagerWidget>
    with SingleTickerProviderStateMixin {
  final ModelManager _modelManager = ModelManager();
  bool _isExpanded = false;

  // 添加动画控制器
  late AnimationController _controller;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _initializeModelManager();

    // 初始化动画控制器，使用更短的时间
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic, // 使用非线性曲线，更快的动画效果
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _initializeModelManager() async {
    try {
      await _modelManager.initialize();
      if (mounted) {
        // 添加mounted检查，避免组件已卸载时调用setState
        setState(() {});
      }
    } catch (e) {
      _showError('初始化模型管理器失败: $e');
    }
  }

  // 切换展开状态
  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  void _showError(String message) {
    if (!mounted) return; // 添加mounted检查，如果组件已卸载则不执行
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // 获取当前模型名称
  String _getCurrentModelName() {
    if (widget.currentModelPath == null || widget.currentModelPath!.isEmpty) {
      return '未加载模型';
    }
    return widget.currentModelPath!.split('/').last;
  }

  // 导入模型
  Future<void> _importModel() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final String filePath = result.files.single.path!;

        // 检查文件后缀
        if (!filePath.toLowerCase().endsWith('.so')) {
          _showError('请选择.so后缀的模型文件');
          return;
        }

        // 显示确认对话框
        bool? shouldImport = await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: Text('确认导入'),
                content: Text('是否导入此模型?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text('确认'),
                  ),
                ],
              ),
        );

        if (shouldImport == true) {
          await _modelManager.importModel(filePath, widget.taskType);
          setState(() {});
          _showError('模型导入成功');
        }
      }
    } catch (e) {
      _showError('导入模型失败: $e');
    }
  }

  // 删除模型
  Future<void> _deleteModel(ModelInfo model) async {
    try {
      bool? shouldDelete = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text('删除确认'),
              content: Text('确定要删除模型"${model.name}"吗?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text('删除'),
                ),
              ],
            ),
      );

      if (shouldDelete == true) {
        await _modelManager.deleteModel(model);
        setState(() {});
        _showError('模型已删除');
      }
    } catch (e) {
      _showError('删除模型失败: $e');
    }
  }

  // 加载第一个模型的方法
  Future<void> _loadFirstModel(List<ModelInfo> models) async {
    if (models.isEmpty) return;

    final model = models.first;
    final success = await _modelManager.setCurrentModel(model.path);
    if (success) {
      widget.onModelSelected(model.path);
      _showError('已加载模型: ${model.name}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final models = _modelManager.getModelsByTaskType(widget.taskType);
    final currentModelName = _getCurrentModelName();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题栏 - 整体可点击
          InkWell(
            onTap: _toggleExpanded,
            child: Container(
              height: 64, // 固定高度
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center, // 垂直居中
                children: [
                  // 左侧图标和标题
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center, // 垂直居中
                      children: [
                        Icon(Icons.model_training),
                        SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min, // 最小高度
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center, // 垂直居中
                            children: [
                              Text(
                                '模型管理',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(height: 2), // 固定间距
                              if (widget.currentModelPath != null &&
                                  widget.currentModelPath!.isNotEmpty)
                                Text(
                                  '当前模型: $currentModelName',
                                  style: TextStyle(
                                    color: Colors.blue.shade700,
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                )
                              else
                                Text(
                                  '未加载模型',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 右侧按钮区域 - 使用固定宽度
                  Container(
                    width: 120, // 固定宽度
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end, // 靠右对齐
                      children: [
                        // 检查是否有模型可加载
                        if (!_isExpanded &&
                            models.isNotEmpty &&
                            (widget.currentModelPath == null ||
                                widget.currentModelPath!.isEmpty))
                          ElevatedButton(
                            onPressed:
                                _modelManager.isLoading
                                    ? null
                                    : () => _loadFirstModel(models),
                            child: Text('加载'),
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 0,
                              ),
                            ),
                          ),
                        // 当已加载模型时显示卸载按钮
                        if (!_isExpanded &&
                            widget.currentModelPath != null &&
                            widget.currentModelPath!.isNotEmpty)
                          ElevatedButton(
                            onPressed:
                                _modelManager.isLoading
                                    ? null
                                    : () {
                                      // 直接通知父组件卸载模型
                                      widget.onModelSelected(null);
                                    },
                            child: Text('卸载'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade100,
                              foregroundColor: Colors.red.shade700,
                              padding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 0,
                              ),
                            ),
                          ),
                        SizedBox(width: 8),
                        SizedBox(
                          width: 24, // 固定图标宽度
                          child: AnimatedRotation(
                            turns: _isExpanded ? 0.5 : 0,
                            duration: Duration(milliseconds: 150),
                            child: Icon(Icons.keyboard_arrow_down),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 展开内容，使用动画
          AnimatedCrossFade(
            firstChild: Container(height: 0, width: double.infinity),
            secondChild: _buildExpandedContent(models),
            crossFadeState:
                _isExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
            duration: Duration(milliseconds: 200),
            sizeCurve: Curves.easeOutCubic, // 使用非线性曲线
          ),
        ],
      ),
    );
  }

  // 构建展开内容
  Widget _buildExpandedContent(List<ModelInfo> models) {
    return Padding(
      padding: EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 1),
          SizedBox(height: 16),

          // 标题和导入按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('可用模型列表', style: TextStyle(fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                onPressed: _modelManager.isLoading ? null : _importModel,
                icon: Icon(Icons.add),
                label: Text('导入模型'),
              ),
            ],
          ),

          SizedBox(height: 16),

          // 模型列表
          if (_modelManager.isLoading)
            Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 8),
                  Text('正在扫描模型文件...'),
                ],
              ),
            )
          else if (models.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  '没有可用的模型文件\n请点击"导入模型"按钮添加.so模型文件',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            Container(
              constraints: BoxConstraints(maxHeight: 300, minHeight: 100),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: AlwaysScrollableScrollPhysics(),
                  itemCount: models.length,
                  separatorBuilder: (_, __) => Divider(height: 1),
                  itemBuilder: (context, index) {
                    final model = models[index];
                    final bool isSelected =
                        model.path == widget.currentModelPath;

                    return Material(
                      color: isSelected ? Colors.blue.shade50 : null,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              isSelected ? Colors.blue : Colors.grey.shade200,
                          child: Icon(
                            Icons.model_training,
                            color:
                                isSelected
                                    ? Colors.white
                                    : Colors.grey.shade700,
                          ),
                        ),
                        title: Text(
                          model.name,
                          style: TextStyle(
                            fontWeight:
                                isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          isSelected
                              ? _modelManager.loadingState ==
                                      ModelLoadingState.error
                                  ? '加载失败: ${_modelManager.errorMessage}'
                                  : _modelManager.loadingState ==
                                      ModelLoadingState.loading
                                  ? '正在加载...'
                                  : '当前已加载'
                              : '点击加载此模型',
                          style: TextStyle(
                            color:
                                isSelected
                                    ? _modelManager.loadingState ==
                                            ModelLoadingState.error
                                        ? Colors.red
                                        : _modelManager.loadingState ==
                                            ModelLoadingState.loading
                                        ? Colors.orange
                                        : Colors.blue
                                    : Colors.grey,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isSelected)
                              IconButton(
                                icon: Icon(Icons.delete_outline),
                                onPressed: () => _deleteModel(model),
                                color: Colors.red,
                              ),
                            if (!isSelected)
                              OutlinedButton(
                                onPressed: () async {
                                  final success = await _modelManager
                                      .setCurrentModel(model.path);
                                  if (success) {
                                    widget.onModelSelected(model.path);
                                  }
                                },
                                child: Text('加载'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.blue,
                                ),
                              ),
                            if (isSelected)
                              ElevatedButton(
                                onPressed: () {
                                  // 直接通知父组件卸载模型
                                  widget.onModelSelected(null);
                                },
                                child: Text('卸载'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade100,
                                  foregroundColor: Colors.red.shade700,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
