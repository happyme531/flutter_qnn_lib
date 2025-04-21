import 'dart:io'; // For Platform checks if needed later
import 'dart:typed_data'; // <-- Add for Uint8List
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:path/path.dart' as p; // For path manipulation
import 'package:open_file/open_file.dart'; // <-- Add for opening files
import 'package:path_provider/path_provider.dart'; // <-- Add for temp dir
import 'package:flutter/services.dart'; // <-- Add for rootBundle

// Import necessary services and widgets
import '../model_manager.dart';
import '../settings_manager.dart';
import '../services/text_feature_extractor.dart';
import '../database/image_vector_database.dart';
import '../widgets/model_manager_widget.dart';
// import '../widgets/asset_thumbnail.dart'; // <-- Remove this non-existent import

class ImageSearchPage extends StatefulWidget {
  const ImageSearchPage({super.key});

  @override
  State<ImageSearchPage> createState() => _ImageSearchPageState();
}

class _ImageSearchPageState extends State<ImageSearchPage> {
  final ModelManager _modelManager = ModelManager();
  final SettingsManager _settingsManager = SettingsManager();
  final TextFeatureExtractor _textFeatureExtractor = TextFeatureExtractor();
  final ImageVectorDatabase _vectorDatabase = ImageVectorDatabase.instance;

  final TextEditingController _textController = TextEditingController();

  String? _selectedTextModelPath;
  String? _tempTokenizerPath; // <-- Add path for loaded tokenizer
  bool _isTokenizerLoading = false; // <-- Add tokenizer loading state
  String? _tokenizerLoadError; // <-- Add tokenizer loading error state

  bool _isLoadingModel = false;
  bool _isSearching = false;
  String _statusMessage = ''; // <-- Add state variable for status text
  // Store the raw results from the database search
  List<Map<String, dynamic>> _searchResults = []; // <-- Change type
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _initModelManager();
    _loadBuiltInTokenizer(); // <-- Load tokenizer on init
  }

  Future<void> _initModelManager() async {
    // No need to show loading indicator here usually
    try {
      await _modelManager.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      _showSnackBar('Failed to initialize model manager: $e', isError: true);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    // Dispose the feature extractor when the page is disposed
    _textFeatureExtractor.dispose();
    super.dispose();
  }

  void _onModelSelected(String? modelPath) {
    if (mounted) {
      setState(() {
        _selectedTextModelPath = modelPath;
        _searchResults = []; // Clear results when model changes
        _searchError = null;
      });
    }
  }

  // <-- Add method to load built-in tokenizer -->
  Future<void> _loadBuiltInTokenizer() async {
    if (!mounted) return;
    setState(() {
      _isTokenizerLoading = true;
      _tokenizerLoadError = null;
      _tempTokenizerPath = "";
    });

    try {
      // Path to the built-in tokenizer in assets
      const String assetPath =
          'assets/siglip2/tokenizer.json'; // Adjust if needed

      // Load the asset data
      final ByteData data = await rootBundle.load(assetPath);
      final List<int> bytes = data.buffer.asUint8List();

      // Get temporary directory and create a file
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        p.join(tempDir.path, 'temp_search_tokenizer.json'),
      ); // Unique name
      await tempFile.writeAsBytes(bytes);

      if (mounted) {
        setState(() {
          _tempTokenizerPath = tempFile.path;
          _isTokenizerLoading = false;
          _tokenizerLoadError = null;
          print(
            "Built-in tokenizer loaded to: ${assetPath.replaceFirst('assets/', '')}",
          );
        });
      }
    } catch (e, stackTrace) {
      print('Failed to load built-in tokenizer: $e\n$stackTrace');
      if (mounted) {
        setState(() {
          _tokenizerLoadError = 'Failed to load tokenizer: $e';
          _isTokenizerLoading = false;
        });
        _showSnackBar(_tokenizerLoadError!, isError: true);
      }
    }
  }

  Future<void> _performSearch() async {
    if (_selectedTextModelPath == null) {
      _showSnackBar('请先选择一个文本模型。', isError: true);
      return;
    }
    // <-- Check if tokenizer is loaded -->
    if (_isTokenizerLoading) {
      _showSnackBar('分词器仍在加载中...', isError: true);
      return;
    }
    if (_tempTokenizerPath == null) {
      _showSnackBar('分词器加载失败，无法搜索。', isError: true);
      return;
    }
    if (_textController.text.trim().isEmpty) {
      _showSnackBar('请输入搜索文本。', isError: true);
      return;
    }
    if (_isSearching || _isLoadingModel) return;

    setState(() {
      _isSearching = true;
      _searchResults = [];
      _searchError = null;
      _statusMessage = ''; // Clear previous status
    });

    try {
      // 1. Initialize Text Feature Extractor (if not already or config changed)
      // Check if re-initialization is needed (only model path change matters now)
      if (!_textFeatureExtractor.isInitialized ||
          _textFeatureExtractor.modelPath != _selectedTextModelPath ||
          _textFeatureExtractor.tokenizerPath != _tempTokenizerPath) {
        // <-- Use temp path
        setState(() => _isLoadingModel = true);
        setState(() {
          _statusMessage = '正在初始化文本特征提取器...'; // <-- Update status message
        });

        // <-- Add cache check logic -->
        String? cachePath = await _modelManager.getModelCache(
          _selectedTextModelPath!,
          _settingsManager.backendType,
        );
        String actualModelPath;
        bool useCache = false;
        if (cachePath != null && File(cachePath).existsSync()) {
          print('Using cached model: $cachePath');
          setState(() {
            _statusMessage = '使用缓存加载模型...'; // <-- Update status message
          });
          actualModelPath = cachePath;
          useCache = true;
        } else {
          print(
            'No cache found, using original model: $_selectedTextModelPath',
          );
          actualModelPath = _selectedTextModelPath!;
          useCache = false;
        }

        bool initOk = await _textFeatureExtractor.initializeModel(
          actualModelPath, // <-- Use actual path (original or cache)
          _tempTokenizerPath!,
          _settingsManager.backendType,
        );
        setState(() => _isLoadingModel = false);
        if (!initOk) {
          throw Exception('初始化文本模型或分词器失败。');
        }

        // <-- Add cache saving logic -->
        if (!useCache && initOk) {
          // Get the target path for saving the cache
          String? outputCachePath = await _modelManager.saveModelCache(
            _selectedTextModelPath!,
            _settingsManager.backendType,
          );
          if (outputCachePath != null) {
            // Extract directory and filename (without extension)
            final cacheDir = p.dirname(outputCachePath);
            final cacheFileName = p.basenameWithoutExtension(outputCachePath);
            // Call the save method in TextFeatureExtractor
            bool cacheSaved = await _textFeatureExtractor.saveModelCache(
              cacheDir,
              cacheFileName,
            );
            if (cacheSaved) {
              _showSnackBar('模型缓存已保存，下次加载将更快');
            } else {
              print('模型缓存保存失败');
              // Optional: Show a specific snackbar for cache saving failure
            }
          } else {
            print('无法获取模型缓存保存路径');
          }
        }
        // <-- End cache saving logic -->
      }

      // 2. Encode Text
      setState(() {
        _statusMessage = '正在编码文本查询...'; // <-- Update status message
      });
      final String queryText = _textController.text.trim();
      final List<double>? queryVector = await _textFeatureExtractor.encodeText(
        queryText,
      );

      if (queryVector == null) {
        throw Exception('将文本编码为向量失败。');
      }
      print(
        'Text encoded successfully. Vector dim: ${queryVector.length}. Searching database...',
      );

      // 3. Search Database
      setState(() {
        _statusMessage = '正在搜索图像数据库...'; // <-- Update status message
      });
      // <-- Fix: Use positional arguments for findSimilarVectors
      final List<Map<String, dynamic>> similarVectors = await _vectorDatabase
          .findSimilarVectors(queryVector, 100); // Pass topK as second arg

      if (similarVectors.isEmpty) {
        setState(() {
          _searchError = '未找到相似图像。';
          _isSearching = false;
          _statusMessage = ''; // <-- Clear status message
        });
        return;
      }
      print('Found ${similarVectors.length} potential matches.');

      // 4. Store Results (No need to fetch AssetEntities here)
      // The results already contain identifiers and similarity scores
      setState(() {
        // Sort results by similarity (already done by findSimilarVectors usually, but double-check or sort here if needed)
        similarVectors.sort(
          (a, b) =>
              (b['similarity'] as double).compareTo(a['similarity'] as double),
        );
        _searchResults = similarVectors; // <-- Store the raw results
        _searchError = null;
        _isSearching = false;
        _statusMessage = ''; // <-- Clear status message
      });
      print('Search results top1: ${_searchResults[0]}');
    } catch (e, stackTrace) {
      print('Search failed: $e\n$stackTrace');
      setState(() {
        _searchError = '搜索失败: $e';
        _isSearching = false;
        _isLoadingModel = false;
        _statusMessage = ''; // <-- Clear status message
      });
      _showSnackBar('搜索失败: $e', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : null,
      ),
    );
  }

  // <-- Add helper function: _loadThumbnail -->
  Future<Uint8List?> _loadThumbnail(String assetId) async {
    try {
      final asset = await AssetEntity.fromId(assetId);
      if (asset == null) return null;

      // Request a reasonably sized thumbnail
      final thumb = await asset.thumbnailDataWithSize(
        const ThumbnailSize(256, 256), // Adjust size as needed
        quality: 85, // Adjust quality as needed
      );

      return thumb;
    } catch (e) {
      print('Failed to load thumbnail for $assetId: $e');
      return null;
    }
  }

  // <-- Add helper function: _openImageWithExternalApp -->
  Future<void> _openImageWithExternalApp(String assetId) async {
    try {
      // Show loading indicator while getting the file path
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final asset = await AssetEntity.fromId(assetId);
      if (asset == null) {
        if (mounted) Navigator.of(context).pop(); // Dismiss loading
        _showSnackBar('无法找到图像详情。');
        return;
      }

      final file = await asset.file; // Get the original file
      print('Asset file: $file');
      if (file == null) {
        if (mounted) Navigator.of(context).pop(); // Dismiss loading
        _showSnackBar('无法获取图像文件路径。');
        return;
      }

      if (mounted) Navigator.of(context).pop(); // Dismiss loading

      // Use open_file to open the image
      final result = await OpenFile.open(file.path);

      if (result.type != ResultType.done) {
        _showSnackBar('无法打开图像: ${result.message}');
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop(); // Dismiss loading on error
      print('Error opening image: $e');
      _showSnackBar('打开图像时出错: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculate preferred size for the search bar section in SliverAppBar
    const searchBarHeight = kToolbarHeight + 8.0; // Approx height needed

    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            title: const Text('文本搜图'),
            pinned: true,
            floating: true,
            // Define the total expanded height - now only needs space for the bottom bar
            expandedHeight:
                searchBarHeight + 10, // Keep a little extra space maybe
            // Remove the flexible space content
            flexibleSpace: FlexibleSpaceBar(
              // background can be empty or have some simple decoration if needed
              background: Container(),
            ),
            // Search bar pinned at the bottom
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(searchBarHeight),
              child: Container(
                color:
                    Theme.of(
                      context,
                    ).scaffoldBackgroundColor, // Match background
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 4.0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        decoration: InputDecoration(
                          hintText: '例如：公园里玩耍的狗',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(Icons.clear),
                            tooltip: '清除文本',
                            onPressed: () => _textController.clear(),
                          ),
                          isDense: true, // Make field slightly smaller
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon:
                          (_isSearching || _isLoadingModel)
                              ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color:
                                      Theme.of(context)
                                          .colorScheme
                                          .onPrimary, // Use theme color
                                ),
                              )
                              : Icon(Icons.search),
                      label: Text(
                        _isLoadingModel ? '加载中' : (_isSearching ? '搜索中' : '搜索'),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10.0, // Match TextField padding roughly
                          horizontal: 12.0,
                        ),
                        minimumSize: Size(
                          0,
                          44,
                        ), // Match TextField height roughly
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed:
                          (_isSearching ||
                                  _isLoadingModel ||
                                  _selectedTextModelPath == null)
                              ? null
                              : _performSearch,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Re-add SliverToBoxAdapter for Model Selection and Tokenizer Status
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Add back the model selection widgets
                  ModelManagerWidget(
                    onModelSelected: _onModelSelected,
                    currentModelPath: _selectedTextModelPath,
                    taskType: 'text_encoder',
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: _buildTokenizerStatusWidget(),
                  ),
                  const SizedBox(height: 4),
                  if (_searchError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        _searchError!,
                        style: TextStyle(color: Colors.red.shade700),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Loading/Status Indicator or Empty Placeholder Sliver
          if (_isLoadingModel || _isSearching) // Show loading/status
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 10),
                    if (_statusMessage.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text(
                          _statusMessage,
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      Text(_isLoadingModel ? '加载模型中...' : '搜索中...'),
                  ],
                ),
              ),
            )
          else if (_searchResults.isEmpty) // Show empty placeholder
            SliverFillRemaining(
              child: Center(
                child: Text(
                  _searchError == null ? '输入文本并按搜索查看结果。' : '无结果可显示。',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            // Search Results Grid
            SliverPadding(
              padding: const EdgeInsets.all(4.0),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 4.0,
                  mainAxisSpacing: 4.0,
                  childAspectRatio: 0.75,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final result = _searchResults[index];
                  final assetId = result['identifier'] as String;
                  final similarity = result['similarity'] as double;

                  return FutureBuilder<Uint8List?>(
                    future: _loadThumbnail(assetId),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Card(
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      if (!snapshot.hasData || snapshot.data == null) {
                        return Card(
                          child: Center(
                            child: Icon(
                              Icons.broken_image,
                              color: Colors.grey[400],
                            ),
                          ),
                        );
                      }

                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _openImageWithExternalApp(assetId),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(snapshot.data!, fit: BoxFit.cover),
                              Positioned(
                                bottom: 4,
                                left: 4,
                                right: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.6),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '分数: ${similarity.toStringAsFixed(3)}',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Icon(
                                  Icons.open_in_new,
                                  size: 16,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                }, childCount: _searchResults.length),
              ),
            ),
        ],
      ),
    );
  }

  // <-- Add helper widget for tokenizer status -->
  Widget _buildTokenizerStatusWidget() {
    String statusText;
    Color statusColor;
    Widget? indicator;

    if (_isTokenizerLoading) {
      statusText = '正在加载分词器...';
      statusColor = Colors.orange;
      indicator = const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (_tokenizerLoadError != null) {
      statusText = '分词器错误!';
      statusColor = Colors.red;
    } else if (_tempTokenizerPath != null) {
      statusText = '分词器: ${p.basename(_tempTokenizerPath!)}';
      statusColor = Colors.green;
    } else {
      statusText = '分词器未加载.';
      statusColor = Colors.grey;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (indicator != null) ...[indicator, const SizedBox(width: 6)],
        Text(
          statusText,
          style: TextStyle(color: statusColor, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
