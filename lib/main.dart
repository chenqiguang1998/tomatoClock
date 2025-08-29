import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/db_service.dart';
import 'views/timeline_page.dart';

void main() async {
  // 初始化Flutter绑定（确保在调用平台通道前初始化）
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化日期格式化
  await initializeDateFormatting();
  
  // 优化：添加数据库初始化错误处理（优雅降级）
  try {
    // 初始化数据库（确保任务数据可持久化）
    await DBService.instance.init();
  } catch (e) {
    debugPrint('数据库初始化警告：$e');
    // 即使数据库初始化失败，仍继续启动应用
  }
  
  // 启动应用（ProviderScope提供Riverpod状态管理）
  runApp(const ProviderScope(child: PomodoroApp()));
}

class PomodoroApp extends StatelessWidget {
  const PomodoroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '番茄时钟 V1.0',
      debugShowCheckedModeBanner: false, // 隐藏调试横幅
      theme: ThemeData(
        useMaterial3: true, // 启用Material 3设计
        colorSchemeSeed: const Color(0xFF6A8DFF), // 主题色种子
        brightness: Brightness.light,
      ),
      home: const TimelinePage(), // 首页为时间轴页面
    );
  }
}