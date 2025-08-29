import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:math';

// Make sure these import paths are correct for your project structure
import '../models/task_model.dart';
import '../viewmodels/task_view_model.dart';
import '../viewmodels/pomodoro_view_model.dart';
import 'task_editor_sheet.dart';
import 'pomodoro_sheet.dart';

class TimelinePage extends ConsumerStatefulWidget {
  const TimelinePage({super.key});

  // Layout configuration
  static const double hourWidth = 120;
  static const double dateAxisWidth = 80;
  static const double taskHeight = 60;
  static const double taskVerticalSpacing = 4;
  static const double timeLabelHeight = 30;

  @override
  ConsumerState<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends ConsumerState<TimelinePage> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();

    // FIX: Simplified and robust initialization logic.
    // This schedules a callback to run after the first frame is rendered.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Ensure the widget is still in the tree.
      if (mounted) {
        // Add a listener to rebuild the time labels when scrolling occurs.
        _scrollController.addListener(_onScroll);
        // Set the initial scroll position to the current time.
        _initializeScrollPosition();
      }
    });
  }

  // Listener to update the UI (specifically the time labels).
  void _onScroll() {
    setState(() {});
  }

  // Sets the initial scroll position to the current time.
  void _initializeScrollPosition() {
    final taskVM = ref.read(taskVMProvider.notifier);
    final now = DateTime.now();
    final isToday = DateFormat('yyyy-MM-dd').format(taskVM.currentDate) ==
        DateFormat('yyyy-MM-dd').format(now);
    
    // Only scroll if viewing today's timeline.
    if (isToday && _scrollController.hasClients) {
      final minutesFromStartOfDay = now.hour * 60 + now.minute;
      final offset = minutesFromStartOfDay * (TimelinePage.hourWidth / 60);
      final screenWidth = MediaQuery.of(context).size.width - TimelinePage.dateAxisWidth;
      // Position the current time about 1/3 of the way into the screen for better context.
      final initialOffset = max(0.0, offset - (screenWidth / 3));
      
      _scrollController.jumpTo(initialOffset);
    }
  }

  @override
  void dispose() {
    // IMPORTANT: Remove the listener before disposing the controller.
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final taskState = ref.watch(taskVMProvider);
    final taskVM = ref.read(taskVMProvider.notifier);
    final currentDate = taskVM.currentDate;

    return Scaffold(
      appBar: AppBar(
        title: Text('时间流程图 · ${DateFormat('yyyy-MM-dd').format(currentDate)}'),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => const TaskEditorSheet(),
        ),
        label: const Text('新建任务'),
        icon: const Icon(Icons.add),
      ),
      body: Row(
        children: [
          _buildDateAxis(context, ref),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: taskState.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('加载失败：$e')),
                    data: (tasks) => _buildTimelineContent(context, tasks, ref),
                  ),
                ),
                _buildPomodoroBar(context, ref),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateAxis(BuildContext context, WidgetRef ref) {
    final taskVM = ref.read(taskVMProvider.notifier);
    final currentDate = taskVM.currentDate;
    final dates = List.generate(15, (i) => currentDate.subtract(Duration(days: 7 - i)));

    return Container(
      width: TimelinePage.dateAxisWidth,
      color: Colors.grey[50],
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: dates.map((date) {
            final isCurrent = DateFormat('yyyy-MM-dd').format(date) ==
                DateFormat('yyyy-MM-dd').format(currentDate);
            return InkWell(
              onTap: () => taskVM.changeDate(date),
              child: Container(
                height: 70,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: isCurrent ? Theme.of(context).primaryColor : Colors.transparent,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(DateFormat('EEE').format(date), style: TextStyle(color: isCurrent ? Colors.white : Colors.black87, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(DateFormat('d').format(date), style: TextStyle(fontSize: 20, color: isCurrent ? Colors.white : Colors.black87, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTimelineContent(BuildContext context, List<TaskModel> tasks, WidgetRef ref) {
    final taskPositions = _calculateTaskPositions(tasks);
    final maxLanes = taskPositions.values.map((p) => p.lane).fold(0, max) + 1;
    final totalContentHeight = maxLanes * (TimelinePage.taskHeight + TimelinePage.taskVerticalSpacing);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTimeLabels(),
        const Divider(height: 1, thickness: 1),
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 24 * TimelinePage.hourWidth,
              height: totalContentHeight,
              child: Stack(
                children: [
                  _buildTimeGrid(),
                  ...tasks.map((task) {
                    final position = taskPositions[task.id]!;
                    return _buildTaskItem(context, task, ref, position.lane);
                  }).toList(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildTimeLabels() {
    // FIX: Safely get the scroll offset.
    // If the controller is not attached yet, default to 0.0.
    final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;

    return SizedBox(
      height: TimelinePage.timeLabelHeight,
      // Use a ClipRect to prevent the labels from drawing outside their bounds.
      child: ClipRect(
        child: Transform.translate(
          // The labels are shifted left as the user scrolls right.
          offset: Offset(-scrollOffset, 0),
          child: Row(
            children: List.generate(24, (hour) {
              return SizedBox(
                width: TimelinePage.hourWidth,
                child: Center(
                  child: Text(
                    '${hour.toString().padLeft(2, '0')}:00',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeGrid() {
    return Row(
      children: List.generate(24 * 4, (i) {
        final isHourLine = i % 4 == 0;
        return Container(
          width: TimelinePage.hourWidth / 4,
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isHourLine ? Colors.grey[300]! : Colors.grey[100]!,
                width: isHourLine ? 1.0 : 0.5,
              ),
            ),
          ),
        );
      }),
    );
  }

  Map<String, _TaskPosition> _calculateTaskPositions(List<TaskModel> tasks) {
    final sortedTasks = List<TaskModel>.from(tasks)..sort((a, b) => a.start.compareTo(b.start));
    final List<DateTime> laneEndTimes = [];
    final Map<String, _TaskPosition> positions = {};

    for (final task in sortedTasks) {
      int targetLane = -1;
      for (int i = 0; i < laneEndTimes.length; i++) {
        if (!task.start.isBefore(laneEndTimes[i])) {
          targetLane = i;
          break;
        }
      }
      final taskEnd = task.start.add(Duration(minutes: task.plannedMinutes));
      if (targetLane == -1) {
        laneEndTimes.add(taskEnd);
        targetLane = laneEndTimes.length - 1;
      } else {
        laneEndTimes[targetLane] = taskEnd;
      }
      positions[task.id] = _TaskPosition(targetLane);
    }
    return positions;
  }

  Widget _buildTaskItem(BuildContext context, TaskModel task, WidgetRef ref, int lane) {
    final taskVM = ref.read(taskVMProvider.notifier);
    final startOfDay = DateTime(task.start.year, task.start.month, task.start.day);

    final startOffset = task.start.difference(startOfDay).inMinutes * (TimelinePage.hourWidth / 60);
    final calculatedWidth = task.plannedMinutes * (TimelinePage.hourWidth / 60);
    final taskWidth = max(calculatedWidth, 30.0);
    final taskColor = Color(task.colorValue);
    final topOffset = lane * (TimelinePage.taskHeight + TimelinePage.taskVerticalSpacing);

    double totalDragDx = 0;
    double? initialLeft;

    return Positioned(
      top: topOffset,
      left: startOffset,
      width: taskWidth,
      height: TimelinePage.taskHeight,
      child: GestureDetector(
        onHorizontalDragStart: task.isLocked ? null : (details) {
          initialLeft = startOffset;
          totalDragDx = 0;
        },
        onHorizontalDragUpdate: task.isLocked ? null : (details) {
          totalDragDx += details.delta.dx;
        },
        onHorizontalDragEnd: task.isLocked ? null : (details) {
          if (initialLeft == null) return;
          
          final finalLeft = initialLeft! + totalDragDx;
          double draggedMinutes = finalLeft / (TimelinePage.hourWidth / 60);

          draggedMinutes = (draggedMinutes / 5).round() * 5;
          draggedMinutes = max(0, draggedMinutes);

          final newStart = startOfDay.add(Duration(minutes: draggedMinutes.round()));

          taskVM.adjustTaskTime(task: task, newStart: newStart);
          
          totalDragDx = 0;
          initialLeft = null;
        },
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: task.isLocked ? taskColor.withOpacity(0.4) : taskColor,
              borderRadius: BorderRadius.circular(8),
              boxShadow: !task.isLocked ? [const BoxShadow(color: Colors.grey, blurRadius: 2)] : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: InkWell(
              onTap: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => PomodoroSheet(task: task),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis, maxLines: 1),
                  const SizedBox(height: 2),
                  Text('${task.formattedStart} - ${task.formattedPlannedEnd}', style: const TextStyle(color: Colors.white70, fontSize: 11), maxLines: 1),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPomodoroBar(BuildContext context, WidgetRef ref) {
    final pomodoroState = ref.watch(pomodoroVMProvider);
    if (pomodoroState.currentTask == null || pomodoroState.state == PomodoroState.idle) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -1))],
      ),
      child: Row(
        children: [
          Expanded(child: Text(pomodoroState.currentTask!.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
          Text(_formatTime(pomodoroState.remainingTime, pomodoroState.isOverTime), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: pomodoroState.isOverTime ? Colors.red : Colors.black87, fontFamily: 'Monospace')),
          const SizedBox(width: 16),
          IconButton(
            icon: Icon(pomodoroState.state == PomodoroState.focusing ? Icons.pause : Icons.play_arrow, color: Colors.black87),
            onPressed: () => pomodoroState.state == PomodoroState.focusing ? ref.read(pomodoroVMProvider.notifier).pauseTask() : ref.read(pomodoroVMProvider.notifier).resumeTask(),
          ),
          IconButton(icon: const Icon(Icons.stop, color: Colors.red), onPressed: () => ref.read(pomodoroVMProvider.notifier).endTask()),
        ],
      ),
    );
  }

  String _formatTime(Duration duration, bool isOverTime) {
    final minutes = duration.inMinutes.remainder(60).abs().toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).abs().toString().padLeft(2, '0');
    return isOverTime ? "+$minutes:$seconds" : "$minutes:$seconds";
  }
}

class _TaskPosition {
  final int lane;
  _TaskPosition(this.lane);
}