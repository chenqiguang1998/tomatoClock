import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task_model.dart';
import '../viewmodels/pomodoro_view_model.dart';

// 番茄钟控制弹窗（点击任务条打开）
class PomodoroSheet extends ConsumerWidget {
  final TaskModel task;
  const PomodoroSheet({super.key, required this.task});

  // 格式化剩余时间（mm:ss，超时前缀加“+”）
  String _formatRemainingTime(PomodoroUIState state) {
    final minutes = state.remainingTime.inMinutes.remainder(60).abs().toString().padLeft(2, '0');
    final seconds = state.remainingTime.inSeconds.remainder(60).abs().toString().padLeft(2, '0');
    return state.isOverTime ? "+$minutes:$seconds" : "$minutes:$seconds";
  }

  // 根据番茄钟状态返回对应的文本
  String _getStateText(PomodoroState state) {
    switch (state) {
      case PomodoroState.focusing:
        return '专注中 · 专注时长 ${task.plannedMinutes}分钟';
      case PomodoroState.breaking:
        return '休息中 · 剩余休息时间';
      case PomodoroState.paused:
        return '已暂停 · 点击开始继续';
      default:
        return '未开始 · 点击开始启动专注';
    }
  }

  // 根据番茄钟状态返回对应的颜色
  Color _getStateColor(PomodoroState state) {
    switch (state) {
      case PomodoroState.focusing:
        return Colors.blue;
      case PomodoroState.breaking:
        return Colors.green;
      case PomodoroState.paused:
        return Colors.grey;
      default:
        return Colors.black54;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pomodoroState = ref.watch(pomodoroVMProvider);
    final pomodoroVM = ref.read(pomodoroVMProvider.notifier);

    // 格式化剩余时间（mm:ss，超时显示“+mm:ss”）
 //   String _formatRemainingTime() {
//      final minutes = pomodoroState.remainingTime.inMinutes.remainder(60).abs().toString().padLeft(2, '0');
 //     final seconds = pomodoroState.remainingTime.inSeconds.remainder(60).abs().toString().padLeft(2, '0');
 //     return pomodoroState.isOverTime ? "+$minutes:$seconds" : "$minutes:$seconds";
 //   }

    return Align(
      alignment: Alignment.center,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              spreadRadius: 2,
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. 任务名称
            Text(
              task.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            // 2. 当前状态提示（专注中/休息中/已暂停）
            Text(
              _getStateText(pomodoroState.state),
              style: TextStyle(
                color: _getStateColor(pomodoroState.state),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // 3. 剩余时间显示（大字体）
            Center(
              child: Text(
                _formatRemainingTime(pomodoroState),
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: pomodoroState.isOverTime ? Colors.red : Colors.black87,
                  fontFamily: 'Monospace', // 等宽字体，确保时间对齐
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 4. 控制按钮（开始/暂停/结束）
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // 开始/继续按钮（空闲/暂停状态显示）
                if (pomodoroState.state == PomodoroState.idle || pomodoroState.state == PomodoroState.paused)
                  FilledButton.icon(
                    onPressed: () => pomodoroVM.startTask(task),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('开始'),
                  ),

                // 暂停/结束休息按钮（专注/休息状态显示）
                if (pomodoroState.state == PomodoroState.focusing || pomodoroState.state == PomodoroState.breaking)
                  FilledButton.icon(
                    onPressed: () => pomodoroState.state == PomodoroState.focusing
                        ? pomodoroVM.pauseTask()
                        : pomodoroVM.endBreak(),
                    icon: const Icon(Icons.pause),
                    label: Text(
                      pomodoroState.state == PomodoroState.focusing
                          ? '暂停'
                          : '结束休息'
                    ),
                  ),

                // 结束任务按钮（始终显示，红色）
                OutlinedButton.icon(
                  onPressed: () async {
                    await pomodoroVM.endTask(); // 结束任务并记录用时
                    if (context.mounted) Navigator.pop(context); // 关闭弹窗
                  },
                  icon: const Icon(Icons.stop, color: Colors.red),
                  label: const Text('结束任务', style: TextStyle(color: Colors.red)),
                  // 修复：用styleFrom设置边框（正确使用OutlinedButton.icon）
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 根据番茄钟状态返回对应的文本
 // String _getStateText(PomodoroState state) {
 //   switch (state) {
 //     case PomodoroState.focusing:
 //       return '专注中 · 专注时长 ${task.plannedMinutes}分钟';
  //    case PomodoroState.breaking:
  //      return '休息中 · 剩余休息时间';
  //    case PomodoroState.paused:
  //      return '已暂停 · 点击开始继续';
 //     default:
 //       return '未开始 · 点击开始启动专注';
 //   }
 // }

  // 根据番茄钟状态返回对应的颜色
  //Color _getStateColor(PomodoroState state) {
  //  switch (state) {
  //    case PomodoroState.focusing:
  //      return Colors.blue;
  //    case PomodoroState.breaking:
   //     return Colors.green;
  //    case PomodoroState.paused:
  //      return Colors.grey;
  //    default:
  //      return Colors.black54;
 //   }
 // }
}