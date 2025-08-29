import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/task_model.dart';
import '../viewmodels/task_view_model.dart';

// 任务编辑弹窗（支持新建/编辑，基于ConsumerStatefulWidget）
class TaskEditorSheet extends ConsumerStatefulWidget {
  final TaskModel? task; // 编辑时传入任务，新建时为null

  const TaskEditorSheet({super.key, this.task});

  @override
  ConsumerState<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends ConsumerState<TaskEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController(); // 任务名称输入
  final _durationCtrl = TextEditingController(text: '40'); // 计划时长（默认40分钟）
  DateTime _selectedStart = DateTime.now(); // 选中的开始时间
  Color _selectedColor = Colors.blueAccent; // 选中的任务颜色

  @override
  void initState() {
    super.initState();
    // 编辑任务：初始化表单数据
    if (widget.task != null) {
      _nameCtrl.text = widget.task!.name;
      _durationCtrl.text = widget.task!.plannedMinutes.toString();
      _selectedStart = widget.task!.start;
      _selectedColor = Color(widget.task!.colorValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final taskVM = ref.read(taskVMProvider.notifier); // 读取任务VM

    return Align(
      alignment: Alignment.center,
      child: Padding(
        // 适配键盘弹出（避免输入框被遮挡）
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 标题（新建/编辑区分）
                Text(
                  widget.task == null ? '新建任务' : '编辑任务',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // 1. 任务名称输入
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '任务名称',
                    border: OutlineInputBorder(),
                    hintText: '请输入任务名称（如“学习Flutter”）',
                  ),
                  validator: (value) => value?.trim().isEmpty ?? true
                      ? '请输入有效的任务名称'
                      : null,
                  autofocus: true,
                ),
                const SizedBox(height: 12),

                // 2. 计划时长输入
                TextFormField(
                  controller: _durationCtrl,
                  decoration: const InputDecoration(
                    labelText: '计划时长（分钟）',
                    border: OutlineInputBorder(),
                    hintText: '请输入大于0的整数',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final duration = int.tryParse(value ?? '');
                    return duration == null || duration <= 0
                        ? '请输入有效的时长（大于0的整数）'
                        : null;
                  },
                ),
                const SizedBox(height: 12),

                // 3. 开始时间选择
                Row(
                  children: [
                    const Text('开始时间：', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () async {
                        // 显示系统时间选择器
                        final pickedTime = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(_selectedStart),
                        );
                        if (pickedTime != null) {
                          setState(() {
                            // 更新选中的开始时间（保留日期，仅修改时分）
                            _selectedStart = DateTime(
                              _selectedStart.year,
                              _selectedStart.month,
                              _selectedStart.day,
                              pickedTime.hour,
                              pickedTime.minute,
                            );
                          });
                        }
                      },
                      child: Text(DateFormat('HH:mm').format(_selectedStart)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 4. 任务颜色选择
                Row(
                  children: [
                    const Text('任务颜色：', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                    // 颜色选择按钮
                    GestureDetector(
                      onTap: () async {
                        final selectedColor = await showDialog<Color>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('选择任务颜色'),
                            content: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Colors.blueAccent, Colors.green, Colors.orange,
                                Colors.purple, Colors.redAccent, Colors.teal,
                              ].map((color) => _buildColorOption(color)).toList(),
                            ),
                          ),
                        );
                        if (selectedColor != null) {
                          setState(() => _selectedColor = selectedColor);
                        }
                      },
                      child: CircleAvatar(
                        backgroundColor: _selectedColor,
                        radius: 16,
                        // 显示当前选中状态
                        child: _selectedColor == _selectedColor
                            ? const Icon(Icons.check, color: Colors.white, size: 16)
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // 5. 提交按钮（新建/更新区分）
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      if (_formKey.currentState!.validate()) {
                        // 确保所有必填字段不为空
                        final taskName = _nameCtrl.text.trim();
                        final duration = int.tryParse(_durationCtrl.text.trim()) ?? 40;
                        
                        // 构建任务对象（确保所有属性都有值）
                        final task = (widget.task ?? TaskModel(
                          name: taskName,
                          start: _selectedStart,
                          plannedMinutes: duration,
                          colorValue: _selectedColor?.value ?? 0xFF448AFF,
                        )).copyWith(
                          name: taskName,
                          start: _selectedStart,
                          plannedMinutes: duration,
                          colorValue: _selectedColor?.value ?? 0xFF448AFF,
                        );
                        
                        try {
                          if (widget.task == null) {
                            await taskVM.addTask(task);
                          } else {
                            await taskVM.updateTask(task);
                          }

                          if (!context.mounted) return;
                          Navigator.pop(context);
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e.toString())),
                          );
                        }
                      }
                    },
                    child: Text(widget.task == null ? '创建任务' : '更新任务'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 构建颜色选择选项
  Widget _buildColorOption(Color color) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, color),
      child: CircleAvatar(
        backgroundColor: color,
        radius: 16,
        // 显示当前选中的颜色标记
        child: _selectedColor == color
            ? const Icon(Icons.check, color: Colors.white, size: 16)
            : null,
      ),
    );
  }

  // 释放资源（避免内存泄漏）
  @override
  void dispose() {
    _nameCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }
}