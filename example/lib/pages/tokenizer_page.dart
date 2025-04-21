import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../tokenizers.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class TokenizerPage extends StatefulWidget {
  const TokenizerPage({Key? key}) : super(key: key);

  @override
  State<TokenizerPage> createState() => _TokenizerPageState();
}

class _TokenizerPageState extends State<TokenizerPage> {
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _outputController = TextEditingController();
  bool _isTokenizerLoaded = false;
  String _modelPath = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _inputController.text = "你好，这是一个测试文本。Hello World!";
    // 初始化时自动加载内置分词器
    _loadBuiltInTokenizer();
  }

  @override
  void dispose() {
    Tokenizers.instance.destroy();
    _inputController.dispose();
    _outputController.dispose();
    super.dispose();
  }

  // 加载内置分词器模型
  Future<void> _loadBuiltInTokenizer() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 内置分词器路径
      const String assetPath = 'assets/siglip2/tokenizer.json';

      // 加载资源文件
      final ByteData data = await rootBundle.load(assetPath);
      final List<int> bytes = data.buffer.asUint8List();

      // 创建临时文件来保存分词器数据
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/temp_tokenizer.json');
      await tempFile.writeAsBytes(bytes);

      _modelPath = tempFile.path;
      final fileName = _modelPath.split('/').last;

      // 加载模型
      final success = await Tokenizers.instance.createAsync(_modelPath);

      if (mounted) {
        setState(() {
          _isTokenizerLoaded = success;
          _isLoading = false;
        });

        // 显示结果提示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '内置分词器加载成功!' : '内置分词器加载失败!'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      print('加载内置分词器失败: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载内置分词器失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loadTokenizerModel() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles();

      if (result != null) {
        _modelPath = result.files.single.path!;
        final fileName = _modelPath.split('/').last;

        // 显示加载提示
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('正在加载分词器模型: $fileName')));

        // 加载模型
        final success = await Tokenizers.instance.create(_modelPath);

        setState(() {
          _isTokenizerLoaded = success;
        });

        // 显示结果提示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '分词器模型加载成功!' : '分词器模型加载失败!'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      print('加载分词器模型失败: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载分词器模型失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _processText() {
    if (!_isTokenizerLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先加载分词器模型'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final String text = _inputController.text;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入要处理的文本'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // 对文本进行分词
    final List<int>? tokens = Tokenizers.instance.encode(text);

    if (tokens == null) {
      _outputController.text = "分词失败";
      return;
    }

    // 构建输出信息
    final StringBuffer output = StringBuffer();
    output.writeln("分词结果 (${tokens.length} 个token):");
    output.writeln("Token IDs: $tokens");
    output.writeln("\n单个Token详情:");

    for (int i = 0; i < tokens.length; i++) {
      final int tokenId = tokens[i];
      final String? tokenText = Tokenizers.instance.idToToken(tokenId);
      output.writeln("[$i] ID: $tokenId, 内容: \"$tokenText\"");
    }

    // 解码测试
    final String? decoded = Tokenizers.instance.decode(tokens);
    output.writeln("\n解码结果:");
    output.writeln(decoded ?? "解码失败");

    _outputController.text = output.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 模型状态与选择按钮 Card
            Card(
              elevation: 1,
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                // 使用 Row 布局状态和按钮
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start, // 顶部对齐
                  children: [
                    // 左侧：状态和模型路径 (用 Expanded 占据左侧空间)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min, // 让 Column 高度自适应
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min, // 防止 Row 过宽
                            children: [
                              Text(
                                '分词器: ${_isTokenizerLoaded ? "已加载" : "未加载"}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color:
                                      _isTokenizerLoaded
                                          ? Colors.green
                                          : Colors.red,
                                ),
                              ),
                              if (_isLoading)
                                const Padding(
                                  padding: EdgeInsets.only(left: 8.0),
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (_isTokenizerLoaded && _modelPath.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                '模型: ${_modelPath.split('/').last}',
                                style: TextStyle(color: Colors.grey[600]),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // 在状态和按钮之间添加间距
                    const SizedBox(width: 12),
                    // 右侧：按钮
                    Row(
                      mainAxisSize: MainAxisSize.min, // 让 Column 高度自适应
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ), // 调整按钮内边距
                            textStyle: TextStyle(fontSize: 13), // 可以稍微减小字体适应空间
                          ),
                          onPressed: _loadBuiltInTokenizer,
                          icon: const Icon(Icons.download, size: 16), // 调整图标大小
                          label: const Text('加载内置'),
                        ),
                        const SizedBox(height: 4), // 按钮之间的垂直间距
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ), // 调整按钮内边距
                            textStyle: TextStyle(fontSize: 13), // 可以稍微减小字体适应空间
                          ),
                          onPressed: _loadTokenizerModel,
                          icon: const Icon(Icons.file_open, size: 16), // 调整图标大小
                          label: const Text('选择文件'),
                        ),
                      ],
                    ),
                    // 移除之前的 SizedBox 和 Wrap
                    // const SizedBox(height: 10),
                    // Wrap(...)
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // 输入区 Card (保持紧凑样式，但恢复字体大小)
            Card(
              elevation: 1,
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      // 恢复默认字体大小
                      '输入文本:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        // fontSize: 14, // 移除
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _inputController,
                      maxLines: 3,
                      // style: TextStyle(fontSize: 14), // 移除
                      decoration: const InputDecoration(
                        hintText: '输入要分词的文本...',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: _processText,
                      icon: const Icon(Icons.text_format, size: 20),
                      label: const Text('开始分词'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // 输出区 Card - 使用 Expanded 包裹使其填充剩余空间
            Expanded(
              child: Card(
                elevation: 1,
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias, // 防止内容溢出 Card 圆角
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            // 恢复默认字体大小
                            '分词结果:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              // fontSize: 14, // 移除
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 20),
                            tooltip: '复制结果',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: BoxConstraints(),
                            onPressed: () {
                              if (_outputController.text.isNotEmpty) {
                                Clipboard.setData(
                                  ClipboardData(text: _outputController.text),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已复制到剪贴板')),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // 输出 TextField - 使用 Expanded 包裹填充 Card 内部剩余空间
                      Expanded(
                        child: TextField(
                          controller: _outputController,
                          maxLines: null, // 允许无限行以利用 Expanded 空间
                          readOnly: true,
                          style: TextStyle(
                            // 恢复默认大小，但保留 monospace
                            // fontSize: 13, // 移除
                            fontFamily: 'monospace',
                          ),
                          decoration: const InputDecoration(
                            hintText: '分词结果将显示在这里...',
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Color(0xFFF5F5F5),
                            contentPadding: EdgeInsets.all(10),
                          ),
                          expands: true, // 让 TextField 填充父 Expanded 空间
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
