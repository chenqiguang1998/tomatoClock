import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

// 任务状态枚举
enum TaskStatus { planned, inProgress, done, locked }

// 实际用时分段模型（记录暂停/继续的时间段）
class TimeSegment {
  final DateTime start;
  final DateTime end;

  TimeSegment({required this.start, required this.end});

  // 转为Map（用于JSON序列化）
  Map<String, dynamic> toMap() => {
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
      };

  // 从Map解析
  static TimeSegment fromMap(Map<String, dynamic> map) => TimeSegment(
        start: DateTime.parse(map['start']),
        end: DateTime.parse(map['end']),
      );
}

// 核心任务模型
class TaskModel {
  final String id;
  final String name;
  final DateTime start;         // 计划开始时间
  final int plannedMinutes;     // 计划时长（分钟）
  final List<TimeSegment> actualSegments; // 实际用时分段列表
  final int colorValue;         // 任务条颜色（int值）
  final TaskStatus status;      // 任务状态
  final DateTime updatedAt;     // 最后更新时间

  TaskModel({
    String? id,
    required this.name,
    required this.start,
    required this.plannedMinutes,
    this.actualSegments = const [],
    this.colorValue = 0xFF448AFF, // 使用blueAccent的十六进制值
    this.status = TaskStatus.planned,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
        updatedAt = updatedAt ?? DateTime.now();

  // 计算计划结束时间
  DateTime get plannedEnd => start.add(Duration(minutes: plannedMinutes));

  // 计算总实际用时（分钟）
  int get totalActualMinutes => actualSegments.fold(
        0,
        (sum, seg) => sum + seg.end.difference(seg.start).inMinutes,
      );

  // 判断任务是否锁定（已过期：计划结束时间早于当前时间）
  bool get isLocked => plannedEnd.isBefore(DateTime.now());

  // 复制任务（用于更新状态/属性）
  TaskModel copyWith({
    String? id,
    String? name,
    DateTime? start,
    int? plannedMinutes,
    List<TimeSegment>? actualSegments,
    int? colorValue,
    TaskStatus? status,
    DateTime? updatedAt,
  }) => TaskModel(
        id: id ?? this.id,
        name: name ?? this.name,
        start: start ?? this.start,
        plannedMinutes: plannedMinutes ?? this.plannedMinutes,
        actualSegments: actualSegments ?? this.actualSegments,
        colorValue: colorValue ?? this.colorValue,
        status: status ?? this.status,
        updatedAt: updatedAt ?? DateTime.now(),
      );

  // 转为Map（用于SQLite存储，JSON序列化actualSegments）
  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'start': start.toIso8601String(),
        'plannedMinutes': plannedMinutes,
        'actualSegments': jsonEncode(actualSegments.map((e) => e.toMap()).toList()),
        'colorValue': colorValue,
        'status': status.index,
        'updatedAt': updatedAt.toIso8601String(),
      };

  // 从Map解析（SQLite读取后重建模型）
  static TaskModel fromMap(Map<String, dynamic> map) {
    // 解析JSON格式的实际用时分段
    final segmentsJson = jsonDecode(map['actualSegments']) as List;
    final actualSegments = segmentsJson
        .map((e) => TimeSegment.fromMap(e as Map<String, dynamic>))
        .toList();

    return TaskModel(
      id: map['id'],
      name: map['name'],
      start: DateTime.parse(map['start']),
      plannedMinutes: map['plannedMinutes'],
      actualSegments: actualSegments,
      colorValue: map['colorValue'],
      status: TaskStatus.values[map['status'] ?? 0],
      updatedAt: DateTime.parse(map['updatedAt']),
    );
  }

  // 格式化时间（优化：确保多语言环境下时间格式一致）
  String get formattedStart => DateFormat('HH:mm', 'zh_CN').format(start);
  String get formattedPlannedEnd => DateFormat('HH:mm', 'zh_CN').format(plannedEnd);
}