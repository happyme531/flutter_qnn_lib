import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:math'; // 添加 dart:math 导入
import 'package:flutter/foundation.dart'; // 导入 compute
import 'package:flutter/services.dart'; // <-- 添加 services 包导入

/// 数据模型：存储图像标识符和其特征向量
class ImageVector {
  final int? id; // 数据库自增ID，可以为null
  final String imageIdentifier; // 图像的唯一标识符，例如文件路径
  final Uint8List vectorBlob; // 存储为 BLOB 的特征向量
  final int vectorDim; // 向量维度
  final DateTime addedTimestamp; // 添加时间戳

  ImageVector({
    this.id,
    required this.imageIdentifier,
    required this.vectorBlob,
    required this.vectorDim,
    required this.addedTimestamp,
  });

  /// 将 ImageVector 对象转换为 Map 以便存入数据库
  Map<String, dynamic> toMap() {
    return {
      // 'id' 是自增的，通常不需要在插入时指定
      'image_identifier': imageIdentifier,
      'vector': vectorBlob, // 数据库列名为 'vector'
      'vector_dim': vectorDim,
      'added_timestamp': addedTimestamp.toIso8601String(), // 存储为 ISO8601 字符串
    };
  }

  /// 从数据库 Map 创建 ImageVector 对象
  factory ImageVector.fromMap(Map<String, dynamic> map) {
    return ImageVector(
      id: map['id'],
      imageIdentifier: map['image_identifier'],
      vectorBlob: map['vector'], // 直接读取 BLOB
      vectorDim: map['vector_dim'],
      addedTimestamp: DateTime.parse(map['added_timestamp']), // 解析时间字符串
    );
  }

  @override
  String toString() {
    // 避免打印整个 vectorBlob
    return 'ImageVector{id: $id, imageIdentifier: $imageIdentifier, vectorDim: $vectorDim, addedTimestamp: $addedTimestamp}';
  }
}

/// 顶层函数，用于在 Isolate 中执行向量搜索
/// 参数是一个 Map，包含 'queryVector', 'topK', 'dbPath', 和 'rootIsolateToken'
Future<List<Map<String, dynamic>>> _findSimilarVectorsIsolate(
  Map<String, dynamic> args,
) async {
  final queryVector = args['queryVector'] as List<double>;
  final topK = args['topK'] as int;
  final dbPath = args['dbPath'] as String;
  final rootIsolateToken =
      args['rootIsolateToken'] as RootIsolateToken?; // <-- 获取 Token

  // --- 初始化后台 Isolate 的 Flutter 绑定 --- START
  if (rootIsolateToken == null) {
    print("Isolate Error: RootIsolateToken is missing.");
    // 可以考虑抛出异常或返回特定错误
    return [];
  }
  // 确保 Flutter 绑定已初始化，这对于某些插件（可能包括 sqflite 的某些配置）是必需的
  BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
  print("Isolate: BackgroundIsolateBinaryMessenger initialized.");
  // --- 初始化后台 Isolate 的 Flutter 绑定 --- END

  Database? isolateDb;
  List<Map<String, dynamic>> results = [];
  print("Isolate: Starting background vector search...");

  try {
    // 在 Isolate 中打开独立的数据库连接
    // 注意：如果仍然遇到 databaseFactory 错误，可能需要在此处添加
    // if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.linux || defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.macOS)) {
    //   sqfliteFfiInit(); // 初始化 ffi 工厂
    //   databaseFactory = databaseFactoryFfi; // 设置全局工厂
    // }
    isolateDb = await openDatabase(dbPath);
    print("Isolate: Database opened successfully at path: $dbPath");

    // 从数据库加载所有向量数据
    final maps = await isolateDb.query('image_vectors');
    if (maps.isEmpty) {
      print("Isolate: Database is empty.");
      return [];
    }
    // 使用 ImageVector.fromMap (需要确保 ImageVector 类定义在此文件或已导入)
    final allDbVectors = List.generate(
      maps.length,
      (i) => ImageVector.fromMap(maps[i]),
    );

    if (queryVector.isEmpty) {
      print("Isolate Error: Query vector is empty.");
      return [];
    }

    // 验证维度 (可选，但建议)
    if (allDbVectors.isNotEmpty &&
        queryVector.length != allDbVectors.first.vectorDim) {
      print(
        'Isolate Warning: Query vector dim (${queryVector.length}) != DB vector dim (${allDbVectors.first.vectorDim})',
      );
      // 根据需要决定是否继续
    }

    final queryNorm = ImageVectorDatabase.norm(queryVector); // 使用静态方法
    if (queryNorm == 0) {
      print("Isolate Error: Query vector norm is 0.");
      return [];
    }

    final List<Map<String, dynamic>> similarities = [];

    // 计算相似度
    for (final dbVector in allDbVectors) {
      final dbVectorList = ImageVectorDatabase.blobToVector(
        dbVector.vectorBlob,
      ); // 使用静态方法
      if (dbVectorList.isEmpty) continue;

      final dbNorm = ImageVectorDatabase.norm(dbVectorList); // 使用静态方法
      if (dbNorm == 0) continue;

      final dot = ImageVectorDatabase.dotProduct(
        queryVector,
        dbVectorList,
      ); // 使用静态方法
      if (queryNorm * dbNorm == 0) continue; // 防止除零

      final similarity = dot / (queryNorm * dbNorm);

      similarities.add({
        'identifier': dbVector.imageIdentifier,
        'similarity': similarity,
        'id': dbVector.id,
      });
    }

    // 排序并取 Top K
    similarities.sort(
      (a, b) =>
          (b['similarity'] as double).compareTo(a['similarity'] as double),
    );
    results = similarities.take(topK).toList();
    print("Isolate: Search complete, found ${results.length} results.");
  } catch (e, stackTrace) {
    print("Isolate Error during vector search: $e\n$stackTrace");
    // 返回空列表或根据需要处理错误
    results = [];
  } finally {
    // 确保关闭 Isolate 中的数据库连接
    await isolateDb?.close();
    print("Isolate: Database connection closed.");
  }

  return results;
}

/// 数据库管理类：用于操作图像向量数据
class ImageVectorDatabase {
  static final ImageVectorDatabase instance = ImageVectorDatabase._init();
  static Database? _database;
  String? _databasePath; // 存储数据库路径

  ImageVectorDatabase._init();

  /// 获取数据库实例，如果未初始化则进行初始化
  Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    // 在初始化时存储路径
    final dbPath = await getDatabasesPath();
    _databasePath = join(dbPath, 'image_vector.db');
    print('数据库路径: $_databasePath');
    _database = await openDatabase(
      _databasePath!,
      version: 1,
      onCreate: _createDB,
    );
    return _database!;
  }

  /// 获取数据库文件的完整路径 (确保先调用 .database 初始化)
  /// 如果数据库未初始化，将触发初始化。
  Future<String?> getDatabasePath() async {
    // 调用 getter database 会确保 _databasePath 被设置 (如果尚未设置)
    await database;
    return _databasePath;
  }

  /// 初始化数据库连接和文件 (此方法现在由 get database 调用)
  // Future<Database> _initDB(String filePath) async { ... } // 可以移除或保留为私有

  /// 创建数据库表结构
  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE image_vectors (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        image_identifier TEXT NOT NULL UNIQUE, -- 图像标识符，必须唯一
        vector BLOB NOT NULL,                  -- 存储向量的 BLOB 数据
        vector_dim INTEGER NOT NULL,           -- 向量维度
        added_timestamp TEXT NOT NULL          -- 添加时间戳 (ISO8601)
      )
    ''');
    // 可以为 image_identifier 创建索引以加快查找（例如删除或检查是否存在时）
    await db.execute(
      'CREATE INDEX idx_vector_image_identifier ON image_vectors(image_identifier)',
    );
    print('image_vectors 表已创建');
  }

  // --- 辅助函数 (改为公有静态) ---

  /// 将 List<double> 向量转换为 Uint8List (BLOB)
  static Uint8List vectorToBlob(List<double> vector) {
    final float32List = Float32List.fromList(vector);
    return float32List.buffer.asUint8List();
  }

  /// 将 Uint8List (BLOB) 转换回 List<double> 向量
  static List<double> blobToVector(Uint8List blob) {
    // 确保读取时也使用 Float32List
    if (blob.lengthInBytes % 4 != 0) {
      print('警告: BLOB 大小 (${blob.lengthInBytes}) 不是4的倍数，可能无法正确转换为 Float32List');
      return []; // 返回空列表表示错误
    }

    try {
      Uint8List alignedBlob = blob; // Start with the original blob

      // Debugging: Print offset and length before conversion
      // print(
      //   'Debug blobToVector: Original blob.offsetInBytes=${blob.offsetInBytes}, blob.lengthInBytes=${blob.lengthInBytes}',
      // );

      // Check if offset is not aligned (multiple of 4)
      if (blob.offsetInBytes % 4 != 0) {
        // print(
        //   '警告: BLOB offsetInBytes (${blob.offsetInBytes}) is not a multiple of 4. Copying data to align.',
        // );
        // Create a copy to ensure alignment (offset will be 0)
        alignedBlob = Uint8List.fromList(blob);
        // Verify the copy (optional debug)
        // print('Debug blobToVector: Copied alignedBlob.offsetInBytes=${alignedBlob.offsetInBytes}, alignedBlob.lengthInBytes=${alignedBlob.lengthInBytes}');
      }

      // Now, perform the conversion using the potentially copied (and thus aligned) blob
      final float32List = alignedBlob.buffer.asFloat32List(
        alignedBlob
            .offsetInBytes, // Should be 0 if copied, or original aligned offset
        alignedBlob.lengthInBytes ~/ 4,
      );
      return float32List.toList();
    } catch (e, stackTrace) {
      // Include stackTrace in catch
      print("错误: blobToVector 转换失败 - $e\n$stackTrace"); // Print stack trace
      return []; // 转换失败也返回空列表
    }
  }

  // --- 核心数据库操作 ---

  /// 添加或更新一个图像向量
  /// 如果 imageIdentifier 已存在，则会替换旧记录
  Future<int> addVector(String imageIdentifier, List<double> vector) async {
    if (vector.isEmpty) {
      print('错误: 尝试添加空向量 (ID: $imageIdentifier)');
      return -1; // 返回 -1 或抛出异常表示失败
    }

    final db = await instance.database;
    final vectorBlob = vectorToBlob(vector);
    final vectorDim = vector.length;
    final timestamp = DateTime.now();

    final imageVector = ImageVector(
      imageIdentifier: imageIdentifier,
      vectorBlob: vectorBlob,
      vectorDim: vectorDim,
      addedTimestamp: timestamp,
    );

    try {
      final id = await db.insert(
        'image_vectors',
        imageVector.toMap(),
        // 如果 image_identifier 冲突，替换旧记录
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print(
        '向量已添加/更新 (ID: $id, Identifier: $imageIdentifier, Dim: $vectorDim)',
      );
      return id;
    } catch (e) {
      print('添加/更新向量时出错 (Identifier: $imageIdentifier): $e');
      return -1; // 返回 -1 表示错误
    }
  }

  /// 获取数据库中所有向量记录 (仅用于后续计算，可能非常耗内存)
  Future<List<ImageVector>> getAllVectors() async {
    final db = await instance.database;
    // 实际应用中可能需要限制或分页
    final maps = await db.query('image_vectors');
    if (maps.isEmpty) {
      return [];
    }
    return List.generate(maps.length, (i) => ImageVector.fromMap(maps[i]));
  }

  /// 检查指定标识符的图像是否已被索引
  Future<bool> isImageIndexed(String imageIdentifier) async {
    final db = await instance.database;
    try {
      final result = await db.query(
        'image_vectors',
        columns: ['id'], // 只需要查询id是否存在即可，更高效
        where: 'image_identifier = ?',
        whereArgs: [imageIdentifier],
        limit: 1, // 找到一个就够了
      );
      return result.isNotEmpty; // 如果查询结果不为空，则表示已索引
    } catch (e) {
      print('检查图像是否索引时出错 (Identifier: $imageIdentifier): $e');
      return false; // 发生错误时，保守地认为未索引
    }
  }

  /// (可选) 保留原始的同步搜索方法，但设为私有或移除
  Future<List<Map<String, dynamic>>> _findSimilarVectorsNaive(
    List<double> queryVector,
    int topK,
  ) async {
    print("开始朴素向量搜索 (将在主线程执行)..."); // 警告

    final allDbVectors = await getAllVectors(); // 仍然需要从主线程获取
    if (allDbVectors.isEmpty) {
      print("数据库为空，无法搜索。");
      return [];
    }

    if (queryVector.isEmpty) {
      print("错误：查询向量为空。");
      return [];
    }

    // 验证查询向量维度是否与数据库中某个向量匹配（假设所有向量维度一致）
    // 在实际应用中，应该更严格地处理维度不一致的情况
    if (allDbVectors.isNotEmpty &&
        queryVector.length != allDbVectors.first.vectorDim) {
      print(
        '警告: 查询向量维度 (${queryVector.length}) 与数据库中向量维度 (${allDbVectors.first.vectorDim}) 不匹配',
      );
      // 可以选择抛出错误或继续，但结果可能无意义
    }

    final queryNorm = ImageVectorDatabase.norm(queryVector); // 调用静态方法
    if (queryNorm == 0) {
      print("错误：查询向量范数为0。");
      return [];
    }

    final List<Map<String, dynamic>> similarities = [];

    // 遍历数据库中的每个向量，计算相似度
    for (final dbVector in allDbVectors) {
      final dbVectorList = blobToVector(dbVector.vectorBlob);
      if (dbVectorList.isEmpty) continue; // 跳过无法转换的向量

      final dbNorm = ImageVectorDatabase.norm(dbVectorList);
      if (dbNorm == 0) continue; // 跳过范数为0的向量

      final dot = ImageVectorDatabase.dotProduct(queryVector, dbVectorList);
      if (queryNorm * dbNorm == 0) continue;
      final similarity = dot / (queryNorm * dbNorm);

      similarities.add({
        'identifier': dbVector.imageIdentifier,
        'similarity': similarity,
        'id': dbVector.id, // 也可返回id
      });
    }

    // 按相似度降序排序
    similarities.sort((a, b) => b['similarity'].compareTo(a['similarity']));

    // 返回 Top K 结果
    final results = similarities.take(topK).toList();
    print("朴素搜索完成，找到 ${results.length} 个相似结果。");
    return results;
  }

  /// 在后台 Isolate 中查找与查询向量最相似的 Top K 个向量
  Future<List<Map<String, dynamic>>> findSimilarVectors(
    List<double> queryVector,
    int topK,
  ) async {
    // 确保数据库已初始化并获取路径
    final db = await database; // 会触发初始化（如果需要）
    if (_databasePath == null) {
      print("错误：无法获取数据库路径以进行后台搜索。");
      return [];
    }
    if (!kIsWeb /* && defaultTargetPlatform != TargetPlatform.windows */ ) {
      // 暂时放开 Windows 限制，看看初始化是否解决问题
      // 检查平台兼容性
      print("启动后台向量搜索...");
      final args = {
        'queryVector': queryVector,
        'topK': topK,
        'dbPath': _databasePath!,
        'rootIsolateToken': RootIsolateToken.instance, // <-- 传递 Token
      };
      // 使用 compute 运行 _findSimilarVectorsIsolate
      try {
        return await compute(_findSimilarVectorsIsolate, args);
      } catch (e) {
        print("在主 Isolate 捕获到 compute 错误: $e");
        // 根据具体错误决定是否回退或抛出
        print("回退到主线程执行向量搜索。");
        return _findSimilarVectorsNaive(queryVector, topK);
      }
    } else {
      // 对于 Web 或 Windows (如果 BackgroundIsolateBinaryMessenger 不足),
      // 可以选择回退到主线程执行（并显示警告）或抛出不支持的错误
      print(
        "警告：当前平台 (${defaultTargetPlatform.name}) 可能不支持在 Isolate 中执行此操作，将在主线程执行向量搜索。",
      );
      return _findSimilarVectorsNaive(queryVector, topK); // 回退到原来的方法
    }
  }

  // --- 其他辅助数据库操作 ---

  /// 获取数据库中的向量总数
  Future<int> getVectorCount() async {
    final db = await instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM image_vectors');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// 根据图像标识符删除向量
  Future<int> deleteVector(String imageIdentifier) async {
    final db = await instance.database;
    final count = await db.delete(
      'image_vectors',
      where: 'image_identifier = ?',
      whereArgs: [imageIdentifier],
    );
    print('已删除 $count 个向量 (Identifier: $imageIdentifier)');
    return count;
  }

  /// 清空 image_vectors 表
  Future<void> clearDatabase() async {
    final db = await instance.database;
    await db.delete('image_vectors');
    print('image_vectors 表已清空');
  }

  /// 关闭数据库连接
  Future<void> close() async {
    final db = await instance.database;
    if (_database != null && _database!.isOpen) {
      await db.close();
      _database = null; // 重置实例以便下次重新打开
      print('数据库已关闭');
    }
  }

  // --- 向量计算辅助函数 (改为公有静态) ---
  /// 计算两个向量的点积
  static double dotProduct(List<double> v1, List<double> v2) {
    if (v1.length != v2.length) {
      print('错误: 向量维度不匹配 (${v1.length} vs ${v2.length})');
      return double.negativeInfinity; // 或者抛出异常
    }
    double sum = 0.0;
    // 使用 double 累加，避免潜在的精度问题
    for (int i = 0; i < v1.length; i++) {
      sum += v1[i] * v2[i];
    }
    return sum;
  }

  /// 计算向量的 L2 范数 (欧几里得长度)
  static double norm(List<double> v) {
    if (v.isEmpty) return 0.0;
    double sumSq = 0.0;
    // 使用 double 累加
    for (final val in v) {
      sumSq += val * val;
    }
    // 使用 dart:math 的 sqrt 函数
    return sqrt(sumSq);
  }
}
