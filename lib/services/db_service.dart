import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task_model.dart';

// DBService Provider（全局单例访问）
final dbServiceProvider = Provider<DBService>((ref) => DBService.instance);

// 数据库服务（单例模式，确保全局唯一实例）
class DBService {
  DBService._();
  static final DBService instance = DBService._();
  Database? _db;
  SharedPreferences? _prefs; // Web平台使用

  // 对外提供数据库实例（非空断言，确保初始化后使用）
  Database get db => _db!;

  // 初始化数据库（应用启动时调用）
  Future<void> init() async {
    try {
      if (kIsWeb) {
        // Web平台使用shared_preferences
        _prefs = await SharedPreferences.getInstance();
      } else {
        // 移动端/桌面端使用path_provider和sqflite
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          sqfliteFfiInit();
          databaseFactory = databaseFactoryFfi;
        }
        final appDocDir = await getApplicationDocumentsDirectory();
        final dbPath = path.join(appDocDir.path, 'pomodoro_tasks.db');

        _db = await openDatabase(
          dbPath,
          version: 1,
          onCreate: _onCreate,
          onOpen: (db) async {
            final tableExists = await db.rawQuery('''
              SELECT name FROM sqlite_master WHERE type='table' AND name='tasks'
            ''');
            if (tableExists.isEmpty) {
              await _onCreate(db, 1);
            }
          },
        );
      }
    } catch (e) {
      throw Exception('数据库初始化失败：$e');
    }
  }

  // 数据库首次创建：创建tasks表
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE tasks (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        start TEXT NOT NULL,
        plannedMinutes INTEGER NOT NULL,
        actualSegments TEXT NOT NULL,
        colorValue INTEGER NOT NULL,
        status INTEGER NOT NULL,
        updatedAt TEXT NOT NULL
      );
    ''');
  }

  // 1. 按日期查询任务（当天00:00 ~ 次日00:00）
  Future<List<TaskModel>> getTasksByDate(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final rows = await db.query(
      'tasks',
      where: 'start >= ? AND start < ?',
      whereArgs: [startOfDay.toIso8601String(), endOfDay.toIso8601String()],
      orderBy: 'start ASC',
    );

    return rows.map((row) => TaskModel.fromMap(row)).toList();
  }

  // 2. 插入新任务
  Future<void> insertTask(TaskModel task) async {
    await db.insert(
      'tasks',
      task.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace, // 存在相同ID时替换
    );
  }

  // 3. 更新现有任务
  Future<void> updateTask(TaskModel task) async {
    await db.update(
      'tasks',
      task.toMap(),
      where: 'id = ?',
      whereArgs: [task.id], // 按任务ID更新
    );
  }

  // 4. 删除任务
  Future<void> deleteTask(String taskId) async {
    await db.delete(
      'tasks',
      where: 'id = ?',
      whereArgs: [taskId],
    );
  }
}