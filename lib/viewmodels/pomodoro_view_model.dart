import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task_model.dart';
import 'task_view_model.dart';

// 番茄钟状态枚举
enum PomodoroState { idle, focusing, paused, breaking }

// 番茄钟UI状态（供视图层渲染）
class PomodoroUIState {
  final PomodoroState state;
  final Duration remainingTime;
  final TaskModel? currentTask;
  final bool isOverTime; // 是否超时（超出计划时长）

  PomodoroUIState({
    required this.state,
    required this.remainingTime,
    this.currentTask,
    this.isOverTime = false,
  });

  // 复制状态（用于局部更新）
  PomodoroUIState copyWith({
    PomodoroState? state,
    Duration? remainingTime,
    TaskModel? currentTask,
    bool? isOverTime,
  }) => PomodoroUIState(
        state: state ?? this.state,
        remainingTime: remainingTime ?? this.remainingTime,
        currentTask: currentTask ?? this.currentTask,
        isOverTime: isOverTime ?? this.isOverTime,
      );

  // 初始空闲状态
  static PomodoroUIState idle() => PomodoroUIState(
        state: PomodoroState.idle,
        remainingTime: const Duration(minutes: 40),
        currentTask: null,
      );
}

// 番茄钟视图模型Provider（Riverpod 2.x 规范：直接用Ref）
final pomodoroVMProvider = StateNotifierProvider<PomodoroViewModel, PomodoroUIState>(
  (ref) => PomodoroViewModel(ref),
);

class PomodoroViewModel extends StateNotifier<PomodoroUIState> {
  final Ref _ref; // 优化：替换Reader为Ref（Riverpod 2.x 推荐）
  Timer? _timer;      // 计时定时器
  DateTime? _currentSegmentStart; // 当前用时分段的开始时间
  final int _focusMinutes = 40;   // 默认专注时长（分钟）
  final int _breakMinutes = 15;   // 默认休息时长（分钟）

  // 优化：用Ref初始化，而非Reader
  PomodoroViewModel(this._ref) : super(PomodoroUIState.idle());

  // 1. 开始任务（启动番茄钟专注）
  void startTask(TaskModel task) {
    if (task.isLocked) return; // 锁定任务（已过期）不可启动

    _timer?.cancel(); // 取消现有定时器
    _currentSegmentStart = DateTime.now(); // 记录当前分段开始时间
    // 更新番茄钟状态为“专注中”
    state = PomodoroUIState(
      state: PomodoroState.focusing,
      remainingTime: Duration(minutes: _focusMinutes),
      currentTask: task,
    );
    _startTimer(); // 启动计时
  }

  // 2. 暂停任务（记录当前用时分段）
  Future<void> pauseTask() async {
    if (state.state != PomodoroState.focusing || _currentSegmentStart == null || state.currentTask == null) return;

    _timer?.cancel(); // 取消定时器
    // 记录当前用时分段（从开始到暂停）
    final segment = TimeSegment(start: _currentSegmentStart!, end: DateTime.now());
    final updatedSegments = [...state.currentTask!.actualSegments, segment];
    // 更新任务状态（标记为“进行中”）
    final updatedTask = state.currentTask!.copyWith(
      actualSegments: updatedSegments,
      status: TaskStatus.inProgress,
    );
    // 提交任务更新到数据库
    await _ref.read(taskVMProvider.notifier).updateTask(updatedTask);
    // 更新番茄钟状态为“暂停中”
    state = state.copyWith(
      state: PomodoroState.paused,
      currentTask: updatedTask,
    );
    _currentSegmentStart = null; // 重置当前分段开始时间
  }

  // 3. 继续任务（恢复专注）
  void resumeTask() {
    if (state.state != PomodoroState.paused || state.currentTask == null) return;

    _currentSegmentStart = DateTime.now(); // 重新记录分段开始时间
    state = state.copyWith(state: PomodoroState.focusing); // 切换回专注状态
    _startTimer(); // 重启计时
  }

  // 4. 结束任务（最终记录用时分段）
  Future<void> endTask() async {
    if (state.currentTask == null) return;

    _timer?.cancel(); // 取消定时器
    // 若当前处于专注中，记录最后一段用时
    if (_currentSegmentStart != null && state.state == PomodoroState.focusing) {
      final segment = TimeSegment(start: _currentSegmentStart!, end: DateTime.now());
      final updatedSegments = [...state.currentTask!.actualSegments, segment];
      // 更新任务状态为“已完成”
      final updatedTask = state.currentTask!.copyWith(
        actualSegments: updatedSegments,
        status: TaskStatus.done,
      );
      await _ref.read(taskVMProvider.notifier).updateTask(updatedTask);
    }
    // 重置番茄钟状态为空闲
    state = PomodoroUIState.idle();
    _currentSegmentStart = null;
  }

  // 5. 启动计时器（每秒刷新一次状态）
  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final newRemaining = state.remainingTime - const Duration(seconds: 1);
      final isOverTime = newRemaining.inSeconds < 0; // 判断是否超时
      final currentTask = state.currentTask!;

      // 专注结束：切换到休息状态
      if (newRemaining.inSeconds == 0 && !isOverTime) {
        _timer?.cancel();
        // 记录专注完成的用时分段
        final segment = TimeSegment(start: _currentSegmentStart!, end: DateTime.now());
        final updatedSegments = [...currentTask.actualSegments, segment];
        final updatedTask = currentTask.copyWith(actualSegments: updatedSegments);
        _ref.read(taskVMProvider.notifier).updateTask(updatedTask);
        // 切换到休息状态
        state = state.copyWith(
          state: PomodoroState.breaking,
          remainingTime: Duration(minutes: _breakMinutes),
          currentTask: updatedTask,
        );
        _startTimer(); // 启动休息计时器
        return;
      }

      // 更新剩余时间和超时状态
      state = state.copyWith(
        remainingTime: newRemaining,
        isOverTime: isOverTime,
      );
    });
  }

  // 6. 结束休息（回到专注状态）
  void endBreak() {
    if (state.state != PomodoroState.breaking || state.currentTask == null) return;

    _timer?.cancel();
    _currentSegmentStart = DateTime.now();
    state = state.copyWith(
      state: PomodoroState.focusing,
      remainingTime: Duration(minutes: _focusMinutes),
      isOverTime: false,
    );
    _startTimer();
  }

  // 释放资源（防止内存泄漏）
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
