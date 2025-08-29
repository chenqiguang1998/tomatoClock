import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../models/task_model.dart';
import '../services/db_service.dart';
import 'package:flutter/material.dart';

// 任务视图模型Provider（全局状态管理）
final taskVMProvider = StateNotifierProvider<TaskViewModel, AsyncValue<List<TaskModel>>>(
  (ref) => TaskViewModel(ref), // 传入ref避免数据库初始化竞争
);

class TaskViewModel extends StateNotifier<AsyncValue<List<TaskModel>>> {
  final Ref _ref; // 新增ref依赖，确保数据库就绪
  late final Database _db;
  DateTime _currentDate = DateTime.now(); // 当前选中日期（筛选任务用）

  // 优化：通过ref初始化，避免构造函数直接访问数据库
  TaskViewModel(this._ref) : super(const AsyncLoading()) {
    _initDBAndLoadTasks();
  }

  // 初始化数据库并加载任务（分离初始化逻辑）
  Future<void> _initDBAndLoadTasks() async {
    try {
      _db = _ref.read(dbServiceProvider).db;
      // 确保数据库已初始化
      if (_db == null) {
        await _ref.read(dbServiceProvider).init();
        _db = _ref.read(dbServiceProvider).db;
      }
      await loadForDate(DateTime.now());
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
    }
  }

  // 1. 加载指定日期的任务（当天00:00 ~ 次日00:00）
  Future<void> loadForDate(DateTime date) async {
    _currentDate = DateTime(date.year, date.month, date.day);
    state = const AsyncLoading();

    try {
      final startOfDay = _currentDate;
      final endOfDay = _currentDate.add(const Duration(days: 1));
      // 从数据库查询指定日期的任务
      final rows = await _db.query(
        'tasks',
        where: 'start >= ? AND start < ?',
        whereArgs: [startOfDay.toIso8601String(), endOfDay.toIso8601String()],
        orderBy: 'start ASC',
      );
      // 转换为TaskModel列表并更新状态
      final tasks = rows.map((e) => TaskModel.fromMap(e)).toList();
      state = AsyncData(tasks);
    } catch (e) {
      debugPrint('加载任务失败: \$e');
      state = AsyncError(e, StackTrace.current);
    }
  }

  // 2. 添加任务（检查时间重叠，避免冲突）
  Future<void> addTask(TaskModel task) async {
    if (await _hasTimeOverlap(task)) {
      throw Exception('任务时间与现有任务重叠，请调整开始时间或时长');
    }
    await _ref.read(dbServiceProvider).insertTask(task); // 插入数据库
    await loadForDate(_currentDate); // 重新加载当前日期任务，刷新UI
  }

  // 3. 更新任务（用于拖拽调整时间、修改属性等）
  Future<void> updateTask(TaskModel task) async {
    // 拖拽时检查新时间是否与其他任务重叠（排除自身）
    if (await _hasTimeOverlap(task, excludeSelf: true)) {
      throw Exception('目标时间段已被占用，请选择其他时间');
    }
    await _ref.read(dbServiceProvider).updateTask(task); // 更新数据库
    await loadForDate(_currentDate); // 重新加载任务
  }

  // 4. 拖拽调整任务时间（自动吸附到最近5分钟刻度）
  void adjustTaskTime({required TaskModel task, required DateTime newStart}) {
    final alignedStart = _alignTo5Minutes(newStart); // 时间吸附处理
    state.whenData((tasks) async {
      final index = tasks.indexWhere((t) => t.id == task.id);
      if (index != -1) {
        final updatedTask = tasks[index].copyWith(start: alignedStart);
        final newTasks = List<TaskModel>.from(tasks);
        newTasks[index] = updatedTask;
        
        // 更新数据库
        await _ref.read(dbServiceProvider).updateTask(updatedTask);
        
        // 更新UI状态
        state = AsyncValue.data(newTasks);
      }
    });
  }

  // 5. 检查任务时间是否重叠（excludeSelf：更新时排除自身）
  Future<bool> _hasTimeOverlap(TaskModel newTask, {bool excludeSelf = false}) async {
    final tasks = await _ref.read(dbServiceProvider).getTasksByDate(_currentDate);
    for (final task in tasks) {
      if (excludeSelf && task.id == newTask.id) continue; // 排除自身
      // 重叠条件：新任务开始 < 现有任务结束，且新任务结束 > 现有任务开始
      final isOverlap = newTask.start.isBefore(task.plannedEnd) &&
          newTask.plannedEnd.isAfter(task.start);
      if (isOverlap) return true;
    }
    return false;
  }

  // 时间吸附到最近5分钟刻度（四舍五入，支持自动进位）
  DateTime _alignTo5Minutes(DateTime time) {
    final roundedMinutes = (time.minute / 5).round() * 5; // 四舍五入到5的倍数
    // 处理分钟进位（如59分钟→60分钟→自动转为下一小时0分）
    return DateTime(time.year, time.month, time.day, time.hour, 0)
        .add(Duration(minutes: roundedMinutes));
  }

  // 切换日期（用于横向日期轴）
  Future<void> changeDate(DateTime newDate) async {
    await loadForDate(newDate);
  }

  // 获取当前选中的日期（对外提供）
  DateTime get currentDate => _currentDate;
}