// ignore_for_file: avoid_print

import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class ImageTag {
  final String imagePath;
  final int tagId;
  final String tagName;
  final double probability;
  final DateTime taggedAt;

  ImageTag({
    required this.imagePath,
    required this.tagId,
    required this.tagName,
    required this.probability,
    required this.taggedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'image_path': imagePath,
      'tag_id': tagId,
      'tag_name': tagName,
      'probability': probability,
      'tagged_at': taggedAt.toIso8601String(),
    };
  }

  factory ImageTag.fromMap(Map<String, dynamic> map) {
    return ImageTag(
      imagePath: map['image_path'],
      tagId: map['tag_id'],
      tagName: map['tag_name'],
      probability: map['probability'],
      taggedAt: DateTime.parse(map['tagged_at']),
    );
  }

  @override
  String toString() {
    return 'ImageTag{imagePath: $imagePath, tagId: $tagId, tagName: $tagName, probability: $probability, taggedAt: $taggedAt}';
  }
}

class ImageTagDatabase {
  static final ImageTagDatabase instance = ImageTagDatabase._init();
  static Database? _database;

  ImageTagDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('image_tag.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE image_tags(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        image_path TEXT NOT NULL,
        tag_id INTEGER NOT NULL,
        tag_name TEXT NOT NULL,
        probability REAL NOT NULL,
        tagged_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE processed_images(
        image_path TEXT PRIMARY KEY,
        processed_at TEXT NOT NULL
      )
    ''');

    // 创建索引以加快查询
    await db.execute('CREATE INDEX idx_image_path ON image_tags(image_path)');
    await db.execute('CREATE INDEX idx_tag_id ON image_tags(tag_id)');
    await db.execute('CREATE INDEX idx_tag_name ON image_tags(tag_name)');
  }

  // 插入单个标签
  Future<int> insertTag(ImageTag tag) async {
    final db = await instance.database;
    return await db.insert('image_tags', tag.toMap());
  }

  // 批量插入标签
  Future<void> insertTags(List<ImageTag> tags) async {
    final db = await instance.database;
    final batch = db.batch();

    for (var tag in tags) {
      batch.insert('image_tags', tag.toMap());
    }

    await batch.commit(noResult: true);
  }

  // 标记图像为已处理
  Future<void> markImageAsProcessed(String imagePath) async {
    final db = await instance.database;
    await db.insert('processed_images', {
      'image_path': imagePath,
      'processed_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // 检查图像是否已处理
  Future<bool> isImageProcessed(String imagePath) async {
    final db = await instance.database;
    final result = await db.query(
      'processed_images',
      where: 'image_path = ?',
      whereArgs: [imagePath],
    );
    return result.isNotEmpty;
  }

  // 按标签ID搜索图像
  Future<List<ImageTag>> searchByTagId(int tagId) async {
    final db = await instance.database;
    final maps = await db.query(
      'image_tags',
      where: 'tag_id = ?',
      whereArgs: [tagId],
    );
    return List.generate(maps.length, (i) => ImageTag.fromMap(maps[i]));
  }

  // 按标签名称搜索图像（模糊搜索）
  Future<List<ImageTag>> searchByTagName(String tagName) async {
    final db = await instance.database;
    final maps = await db.query(
      'image_tags',
      where: 'tag_name LIKE ?',
      whereArgs: ['%$tagName%'],
    );
    return List.generate(maps.length, (i) => ImageTag.fromMap(maps[i]));
  }

  // 获取图像的所有标签
  Future<List<ImageTag>> getTagsForImage(String imagePath) async {
    final db = await instance.database;
    final maps = await db.query(
      'image_tags',
      where: 'image_path = ?',
      whereArgs: [imagePath],
    );
    return List.generate(maps.length, (i) => ImageTag.fromMap(maps[i]));
  }

  // 获取所有标签列表（去重）
  Future<List<Map<String, dynamic>>> getAllDistinctTags() async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT DISTINCT tag_id, tag_name 
      FROM image_tags 
      ORDER BY tag_name
    ''');
  }

  // 获取标签统计信息
  Future<List<Map<String, dynamic>>> getTagStats() async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT tag_id, tag_name, COUNT(DISTINCT image_path) as image_count
      FROM image_tags
      GROUP BY tag_id, tag_name
      ORDER BY image_count DESC
    ''');
  }

  // 清空数据库
  Future<void> clearDatabase() async {
    final db = await instance.database;
    await db.delete('image_tags');
    await db.delete('processed_images');
  }

  // 关闭数据库
  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
