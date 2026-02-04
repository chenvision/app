import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async'; // <--- 新增这一行
import 'package:confetti/confetti.dart';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_animate/flutter_animate.dart';
// 记得导入
import 'package:flutter_heatmap_calendar/flutter_heatmap_calendar.dart';
// 1. 引入头文件
import 'package:google_fonts/google_fonts.dart';
import 'auth_gate.dart'; // 👈 1. 引入新文件
import 'ai_service.dart';
// 1. 定义一个全局的主题控制器
// 使用 ValueNotifier 可以让我们在任何地方修改它，并通知界面刷新
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔴 【重要】在这里填入你在 Supabase 设置里看到的 URL 和 Key
  await Supabase.initialize(
    url: 'https://vmecbslypbrrshrzljll.supabase.co',
    anonKey: 'sb_publishable_jntyIT3GHMQ4xJLmE7FG9A_JMm_F8Df',
  );

  runApp(const MyApp());
}
// 1. 数据模型：增加了 id 字段，因为数据库需要靠 id 来区分每一行
class Task {
  int? id; // 新增：数据库里的唯一ID
  String name;
  int priority;
  bool isDone;
  DateTime? deadline;
  DateTime? completedAt; // 👈 新增：完成时间

  Task({
    this.id,
    required this.name,
    required this.priority,
    this.isDone = false,
    this.deadline,
    this.completedAt, // 👈 新增
  });

  // 把数据库的一行数据变成 Task 对象
  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'],
      name: map['name'],
      priority: map['priority'],
      isDone: map['is_done'] ?? false,
      deadline: map['deadline'] != null ? DateTime.tryParse(map['deadline']) : null,
      // 👇 新增：解析数据库里的完成时间
      completedAt: map['completed_at'] != null
          ? DateTime.parse(map['completed_at']).toLocal()
          : null,
    );
  }

  // 把 Task 对象变成数据，准备上传
  Map<String, dynamic> toMap() {
    return {
      // id 不需要传，Supabase 会自动生成
      'name': name,
      'priority': priority,
      'is_done': isDone,
      'deadline': deadline?.toIso8601String(),
    };
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 2. 使用 ValueListenableBuilder 包裹 MaterialApp
    // 这样每当 themeNotifier 变化时，整个 App 都会重绘
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          title: 'Priority Master Cloud',
          debugShowCheckedModeBanner: false,

          // --- 亮色主题 ---
          theme: ThemeData(
            textTheme: GoogleFonts.notoSansScTextTheme(),
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
            scaffoldBackgroundColor: Colors.grey[50], // 浅灰背景，不刺眼
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black, // 标题黑色
              elevation: 0,
            ),
          ),

          // --- 暗色主题 (Dark Mode) ---
          darkTheme: ThemeData(
            textTheme: GoogleFonts.notoSansScTextTheme(),
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.dark, // 关键：告诉 Flutter 这是暗色模式
            ),
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xFF121212), // 经典的深色背景
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF1E1E1E),
              foregroundColor: Colors.white, // 标题白色
              elevation: 0,
            ),    // 卡片也是深灰色
          ),

          // 当前使用哪种模式
          themeMode: currentMode,

          home: const AuthGate(),
        );
      },
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _dailyQuote;
  bool _loadingQuote = false;
  // 🎵 1. 定义播放器实例
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  // 获取 Supabase 客户端实例
  final _supabase = Supabase.instance.client;
  List<Task> tasks = [];
  // 2. 新增烟花控制器
  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _fetchTasks().then((_) {
      // 等任务加载完了，再加载评语
      _fetchDailyQuote();
    });
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 2),
    ); // 持续2秒
    _fetchTasks();
  }
  @override
  void dispose() {
    _confettiController.dispose(); // 记得销毁
    super.dispose();
  }

  // --- 核心：云端增删改查 ---
  Future<void> _fetchDailyQuote() async {
    // 如果没有任务，就不问 AI 了
    if (tasks.isEmpty) return;

    setState(() => _loadingQuote = true);

    // 把 task 转成简单的 Map 列表传给 AI
    final taskMaps = tasks
        .map(
          (t) => {
            'priority': t.priority,
            'is_done': t.isDone,
            'deadline': t.deadline?.toIso8601String(),
          },
        )
        .toList();

    final quote = await AIService.getDailyAdvice(taskMaps);

    if (mounted) {
      setState(() {
        _dailyQuote = quote;
        _loadingQuote = false;
      });
    }
  }
  // 🎵 2. 简单的播放工具函数
  Future<void> _playSound(bool isImportant) async {
    try {
      // 如果是重要任务 (优先级 0 或 1)，播放胜利音效
      if (isImportant) {
        // 假设你放了一个叫 win.mp3 的文件
        await _audioPlayer.play(AssetSource('sounds/success.mp3'));
      } else {
        // 普通任务播放清脆的叮一声
        await _audioPlayer.play(AssetSource('sounds/ding.mp3'));
      }
    } catch (e) {
      debugPrint("播放声音失败: $e");
    }
  }

  // 1. 查 (Read)
  Future<void> _fetchTasks() async {
    // 从 'tasks' 表里查所有数据，按 id 排序
    final data = await _supabase.from('tasks').select().order('id', ascending: true);
    setState(() {
      tasks = (data as List).map((e) => Task.fromMap(e)).toList();
    });
  }

  // 2. 增 (Create)
  // 1. 修改参数名：把 date 改为 deadline
  Future<void> _addTask(String name, int priority, DateTime? deadline) async {
    final userId = _supabase.auth.currentUser!.id;

    final newTask = {
      'user_id': userId,
      'name': name,
      'priority': priority,
      'is_done': false,
      // 2. 这里现在可以正确识别 deadline 了
      'deadline': deadline?.toIso8601String(),
    };

    // 3. 修复 insert 报错：直接传入 newTask 即可，不用 .toMap()
    // 因为 newTask 本身已经是 Map 类型了
    final data = await _supabase.from('tasks').insert(newTask).select();

    setState(() {
      tasks.add(Task.fromMap(data.first));
    });
  }

  // 3. 改 (Update)
  Future<void> _updateTask(Task task) async {
    // 乐观更新：先改界面，再改数据库（让用户感觉不到延迟）
    setState(() {}); 
    
    await _supabase.from('tasks').update({
      'is_done': task.isDone,
      'priority': task.priority, // 比如拖拽后改优先级
    }).eq('id', task.id!); // 这里的 eq 意思是：只改 id 等于这个任务的那一行
  }

  // 4. 删 (Delete)
  Future<void> _deleteTask(Task task) async {
    setState(() {
      tasks.remove(task);
    });
    await _supabase.from('tasks').delete().eq('id', task.id!);
  }

  // 🤖 模拟 AI 智能拆解功能 (Mock版)
  // ✨ 真正的 AI 拆解逻辑
  Future<void> _realAISplit(Task task) async {
    // 1. 显示加载中 (给个用户反馈)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 10),
            Text('AI 正在思考如何拆解任务...'),
          ],
        ),
        duration: Duration(seconds: 10), // 给 AI 一点时间
      ),
    );

    

    // 2. 调用 AI
    final subTaskNames = await AIService.splitTask(task.name);

    // 隐藏之前的 SnackBar
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (subTaskNames.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('AI 脑袋卡壳了，请重试')));
      return;
    }

    // 3. 批量添加到数据库
    // 获取当前用户 ID
    final userId = _supabase.auth.currentUser!.id;

    for (String subName in subTaskNames) {
      // 这里的逻辑是：子任务通常优先级和父任务一样，或者稍微低一点
      // 咱们简单处理：都设为“计划中 (Priority 1)”
      final newTask = {
        'user_id': userId,
        'name': '$subName (子任务)', // 标记一下
        'priority': 1, // 放入第二象限
        'is_done': false,
        'deadline': task.deadline?.toIso8601String(), // 继承截止日期
      };

      await _supabase.from('tasks').insert(newTask);
    }

    // 4. 刷新列表 & 播放成功音效
    _fetchTasks();
    HapticFeedback.mediumImpact();
    // 没必要放烟花，简单的音效即可
  }
  // --- 下面是界面代码，几乎不用动，只是调用上面的新函数 ---
  // 🔘 切换任务完成状态（打钩/取消打钩）
  Future<void> _toggleTaskStatus(Task task) async {
    final newState = !task.isDone;

    // 如果变成完成，记录当前时间（转成 UTC 存数据库更稳健）；取消完成则清空时间
    // toUtc() 确保发给数据库的是绝对时间，不受 VPN 或时区影响
    final completedAt = newState
        ? DateTime.now().toUtc().toIso8601String()
        : null;

    // 1. 先更新本地 UI（让用户感觉瞬间反应，不用等网络）
    setState(() {
      task.isDone = newState;
      // 本地显示时，我们需要把 UTC 转回本地时间，或者直接用 DateTime.now() 给用户看
      task.completedAt = newState ? DateTime.now() : null;
    });

    try {
      // 2. 再静默更新数据库
      await _supabase
          .from('tasks')
          .update({
            'is_done': newState,
            'completed_at': completedAt, // 👈 把时间存进去
          })
          .eq('id', task.id!);

      // 3. (可选) 给点爽感反馈：如果是完成任务，震动一下
      if (newState) {
        // 需要 import 'package:flutter/services.dart';
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      // 如果网络失败，把状态回滚（可选）
      print('更新失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('同步失败，请检查网络')));
      }
    }
  }
  // 📅 数据转换：把任务列表转成热力图数据
  // 📅 数据转换：把任务列表转成热力图数据 (真实版)
  // 秘书 1：生成真实的热力图数据 (只看 completedAt)
  Map<DateTime, int> _getHeatmapData() {
    Map<DateTime, int> dataset = {};
    for (var task in tasks) {
      if (task.isDone && task.completedAt != null) {
        final d = task.completedAt!;
        // 归一化：把时间去掉，只保留日期 (2026-02-01 00:00:00)
        final normalizeDate = DateTime(d.year, d.month, d.day);
        dataset[normalizeDate] = (dataset[normalizeDate] ?? 0) + 1;
      }
    }
    return dataset;
  }

  // 秘书 2：计算生产力积分 (优先级 + 速度奖励)
  int _calculateScore() {
    int score = 0;
    for (var task in tasks) {
      if (task.isDone) {
        // 基础分：P0=40, P1=30, P2=20, P3=10
        score += (4 - task.priority) * 10;

        // 速度奖励：如果在截止日期前一天完成，+20分
        if (task.deadline != null &&
            task.completedAt != null &&
            task.completedAt!.isBefore(
              task.deadline!.subtract(const Duration(days: 1)),
            )) {
          score += 20;
        }
      }
    }
    return score;
  }

  
  String _formatTime(DateTime dt) {
    String hour = dt.hour.toString().padLeft(2, '0');
    String minute = dt.minute.toString().padLeft(2, '0');

    final now = DateTime.now();
    // 判断是不是今天
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return "今天 $hour:$minute"; // 如果是今天，显示 "今天 21:31"
    } else {
      return "${dt.month}月${dt.day}日 $hour:$minute"; // 如果不是今天，显示 "2月1日 21:31"
    }
  }
  void _showPlanWizard() {
    final goalController = TextEditingController();
    final daysController = TextEditingController(text: '30'); // 默认30天
    bool isGenerating = false;

    showDialog(
      context: context,
      barrierDismissible: false, // 生成时禁止点击背景关闭
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.auto_awesome_motion, color: Colors.purpleAccent),
                SizedBox(width: 8),
                Text('AI 学习规划师'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('告诉我你的目标，我帮你安排未来每一天。'),
                const SizedBox(height: 16),
                TextField(
                  controller: goalController,
                  decoration: const InputDecoration(
                    labelText: '学习目标',
                    hintText: '例：一个月内雅思听力达到 7 分',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.flag),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: daysController,
                  decoration: const InputDecoration(
                    labelText: '计划天数',
                    hintText: '30',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.timer),
                  ),
                  keyboardType: TextInputType.number,
                ),
                if (isGenerating) ...[
                  const SizedBox(height: 20),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  const Text(
                    'AI 正在为您排兵布阵，请稍候...',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ],
            ),
            actions: [
              if (!isGenerating)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              FilledButton(
                onPressed: isGenerating
                    ? null
                    : () async {
                        if (goalController.text.isEmpty) return;
                        final days = int.tryParse(daysController.text) ?? 7;

                        // 1. 开始生成
                        setDialogState(() => isGenerating = true);

                        // 2. 调用 AI
                        final plan = await AIService.generateStudyPlan(
                          goalController.text,
                          days,
                        );

                        // 3. 批量写入数据库
                        if (plan.isNotEmpty) {
                          final userId = _supabase.auth.currentUser!.id;

                          // 构造批量插入的数据
                          final insertData = plan
                              .map(
                                (item) => {
                                  'user_id': userId,
                                  'name': item['name'],
                                  'priority': item['priority'] ?? 1, // 默认为计划象限
                                  'is_done': false,
                                  'deadline': item['deadline'], // AI 算好的日期
                                },
                              )
                              .toList();

                          await _supabase.from('tasks').insert(insertData);

                          // 4. 结束流程
                          if (mounted) {
                            Navigator.pop(context); // 关弹窗
                            _fetchTasks(); // 刷新列表
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '🎉 成功生成了 ${plan.length} 天的学习计划！',
                                ),
                              ),
                            );
                            // 触发个大震动
                            HapticFeedback.heavyImpact();
                          }
                        } else {
                          setDialogState(() => isGenerating = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('生成失败，请重试')),
                            );
                          }
                        }
                      },
                child: const Text('生成计划'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSmartAddDialog() {
    final inputController = TextEditingController();
    bool isAnalyzing = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.bolt, color: Colors.amber),
                SizedBox(width: 8),
                Text('AI 极速录入'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: inputController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: '例如：周五前要把雅思阅读做完，很急',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                if (isAnalyzing)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.auto_awesome),
                label: const Text('识别并添加'),
                onPressed: isAnalyzing
                    ? null
                    : () async {
                        if (inputController.text.isEmpty) return;

                        setDialogState(() => isAnalyzing = true);

                        // 1. 调用 AI 分析
                        final result = await AIService.smartAnalyze(
                          inputController.text,
                        );

                        setDialogState(() => isAnalyzing = false);
                        Navigator.pop(context); // 关闭输入弹窗

                        if (result != null) {
                          // 2. 解析 AI 返回的数据
                          final name = result['name'];
                          final priority = result['priority'] ?? 3;
                          final deadlineStr = result['deadline'];
                          DateTime? deadline;
                          if (deadlineStr != null) {
                            deadline = DateTime.tryParse(deadlineStr);
                          }

                          // 3. 直接调用你现有的添加任务函数！
                          _addTask(name, priority, deadline);

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('✨ 已智能添加：$name (P$priority)'),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('AI 没听懂，请手动添加吧')),
                          );
                          // 也可以选择在这里打开手动弹窗 _showTaskDialog()
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }
  void _showStatsDialog() {
    // --- 1. 先在弹窗前把数据算好 ---
    final total = tasks.length;
    final done = tasks.where((t) => t.isDone).length;
    final progress = total == 0 ? 0.0 : done / total;

    final score = _calculateScore(); // 调用秘书2
    final heatmapDataset = _getHeatmapData(); // 调用秘书1

    // --- 2. 弹出底部面板 ---
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // 允许弹窗高度自适应
      backgroundColor: Colors.transparent, // 背景透明，为了显示上方圆角
      builder: (context) {
        return Container(
          height: 700, // 限制最大高度
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor, // 适配深色模式背景
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- 顶部标题 ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '📊 今日生产力战报',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 20),

              // --- 核心数据展示区域 (环形图 + 积分) ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // 左侧：环形进度条
                  Column(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 100,
                            height: 100,
                            child: CircularProgressIndicator(
                              value: progress,
                              strokeWidth: 12,
                              backgroundColor: Colors.grey.withOpacity(0.2),
                              color: progress == 1.0
                                  ? Colors.green
                                  : Colors.blueAccent,
                              strokeCap: StrokeCap.round,
                            ),
                          ),
                          Text(
                            '${(progress * 100).toInt()}%',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text('列表完成率', style: TextStyle(color: Colors.grey)),
                    ],
                  ),

                  // 右侧：积分大数字
                  Column(
                    children: [
                      Text(
                        '$score',
                        style: const TextStyle(
                          fontSize: 60,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                      const Text(
                        '生产力积分',
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '已完成 $done / $total',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 30),

              // --- 🔥 热力图区域 (真实数据) ---
              const Text(
                "坚持记录",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 10),

              // ⚠️ 确保你 import 了 'package:flutter_heatmap_calendar/flutter_heatmap_calendar.dart';
              Expanded(
                child: SingleChildScrollView(
                  child: HeatMap(
                    datasets: heatmapDataset, // 👈 注入真实数据
                    colorMode: ColorMode.opacity,
                    showText: false,
                    scrollable: true,
                    startDate: DateTime.now().subtract(
                      const Duration(days: 80),
                    ),
                    endDate: DateTime.now(),
                    textColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black,
                    colorsets: {
                      1: Colors.green.shade200,
                      3: Colors.green.shade500,
                      5: Colors.green.shade900,
                    },
                    onClick: (value) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            "这一天完成了 ${heatmapDataset[value] ?? 0} 个任务",
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // --- 底部鼓励语 ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey.shade800
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _getMotivationalMessage(progress), // 调用秘书3
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
  // 一个简单的辅助函数，根据进度返回不同的鼓励语
  String _getMotivationalMessage(double progress) {
    if (progress == 0) return "千里之行，始于足下。做一个任务试试？";
    if (progress < 0.3) return "好的开始是成功的一半，继续加油！";
    if (progress < 0.6) return "状态不错！保持专注，你可以的！";
    if (progress < 1.0) return "太棒了！离目标越来越近了！";
    return "完美！今天的你简直不可战胜！🎉";
  }

  // --- 新增功能：沉浸式专注模式 ---
  void _startFocusSession(Task task) {
    // 默认专注 25 分钟 (25 * 60 秒)
    int secondsLeft = 25 * 60;
    Timer? timer;

    showDialog(
      context: context,
      barrierDismissible: false, // 禁止点击背景关闭，强制专注
      builder: (context) {
        // 使用 StatefulBuilder 让 Dialog 内部可以刷新 UI (倒计时跳动)
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // 启动定时器 (只在第一次构建时启动)
            timer ??= Timer.periodic(const Duration(seconds: 1), (t) {
              if (secondsLeft > 0) {
                setDialogState(() {
                  secondsLeft--;
                });
              } else {
                // 时间到！自动结束
                t.cancel();
              }
            });

            // 计算分和秒
            final minutesStr = (secondsLeft ~/ 60).toString().padLeft(2, '0');
            final secondsStr = (secondsLeft % 60).toString().padLeft(2, '0');
            final progress = 1.0 - (secondsLeft / (25 * 60)); // 进度条

            return PopScope(
              canPop: false, // 禁止安卓物理返回键，防止误触退出
              child: Dialog(
                backgroundColor: const Color(0xFF1E1E1E), // 深色背景
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                insetPadding: const EdgeInsets.all(20),
                child: Padding(
                  padding: const EdgeInsets.all(30.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '🔥 专注挑战',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 16,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 30),

                      // 倒计时大字
                      Text(
                        '$minutesStr:$secondsStr',
                        style: const TextStyle(
                          fontSize: 80,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFeatures: [
                            FontFeature.tabularFigures(),
                          ], // 防止数字跳动抖动
                        ),
                      ),

                      const SizedBox(height: 20),
                      Text(
                        '当前任务：${task.name}',
                        style: const TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 18,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 30),

                      // 进度条
                      LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.white10,
                        color: Colors.orange,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),

                      const SizedBox(height: 40),

                      // 按钮区域
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          TextButton(
                            onPressed: () {
                              timer?.cancel();
                              Navigator.pop(context);
                            },
                            child: const Text(
                              '放弃',
                              style: TextStyle(color: Colors.white30),
                            ),
                          ),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                            icon: const Icon(Icons.check),
                            label: const Text('完成任务'),
                            onPressed: () {
                              timer?.cancel();
                              // 1. 关闭弹窗
                              Navigator.pop(context);
                              // 2. 标记任务为完成
                              setState(() => task.isDone = true);
                              _updateTask(task);
                              // 3. 提示庆祝
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('🎉 挑战成功！专注力爆棚！')),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
  // ✏️ 通用弹窗：既能添加，也能编辑
  void _showTaskDialog({Task? taskToEdit}) {
    // 如果传入了 taskToEdit，说明是编辑模式，预填数据
    final bool isEditMode = taskToEdit != null;

    String name = isEditMode ? taskToEdit.name : '';
    int priority = isEditMode ? taskToEdit.priority : 0;
    DateTime? selectedDate = isEditMode ? taskToEdit.deadline : null;

    // 编辑时，默认光标在文字最后，体验更好
    final TextEditingController textController = TextEditingController(
      text: name,
    );

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEditMode ? '编辑任务' : '添加新任务'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: textController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: '要做什么？',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => name = value,
                  ),
                  const SizedBox(height: 20),
                  // 日期选择器
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        selectedDate == null
                            ? '无截止日期'
                            : '${selectedDate!.month}月${selectedDate!.day}日',
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () async {
                          final DateTime? picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate ?? DateTime.now(),
                            firstDate: DateTime.now().subtract(
                              const Duration(days: 365),
                            ), // 允许选以前的日期补录
                            lastDate: DateTime(2030),
                          );
                          if (picked != null)
                            setDialogState(() => selectedDate = picked);
                        },
                        child: const Text('选择日期'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // 优先级选择器
                  DropdownButton<int>(
                    value: priority,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('🔴 重要且紧急')),
                      DropdownMenuItem(value: 1, child: Text('🔵 重要不紧急')),
                      DropdownMenuItem(value: 2, child: Text('🟠 紧急不重要')),
                      DropdownMenuItem(value: 3, child: Text('🟢 不重要不紧急')),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => priority = value!),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    if (name.isNotEmpty) {
                      if (isEditMode) {
                        // --- 编辑逻辑 ---
                        setState(() {
                          taskToEdit.name = name;
                          taskToEdit.priority = priority;
                          taskToEdit.deadline = selectedDate;
                        });
                        // 别忘了创建一个新的 _updateContent 方法或直接复用 _updateTask
                        // 这里我们直接调用 Supabase 更新
                        _supabase
                            .from('tasks')
                            .update({
                              'name': name,
                              'priority': priority,
                              'deadline': selectedDate?.toIso8601String(),
                            })
                            .eq('id', taskToEdit.id!);
                      } else {
                        // --- 新增逻辑 ---
                        _addTask(name, priority, selectedDate);
                      }
                      Navigator.pop(context);
                    }
                  },
                  child: Text(isEditMode ? '保存' : '添加'),
                ),
              ],
            );
          },
        );
      },
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的云端优先级'),
        elevation: 2,
        actions: [
          IconButton(
            tooltip: '退出登录',
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: () async {
              // 1. 调用 Supabase 登出
              await _supabase.auth.signOut();

              // 2. 这里的妙处：
              // 你不需要手动写 Navigator.push 去登录页。
              // 因为 main.dart 里的 AuthGate 正在监听。
              // 一旦监测到 signOut，它会自动把你踢回 LoginPage。
            },
          ),
          // 📅 长线计划生成器按钮
          IconButton(
            tooltip: '生成长线计划',
            icon: const Icon(
              Icons.date_range_rounded,
              color: Colors.purpleAccent,
            ),
            onPressed: _showPlanWizard, // 点击触发弹窗
          ),
          IconButton(
            tooltip: '切换主题',
            icon: Icon(
              themeNotifier.value == ThemeMode.light
                  ? Icons.dark_mode_outlined
                  : Icons.light_mode_outlined,
            ),
            onPressed: () {
              themeNotifier.value = themeNotifier.value == ThemeMode.light
                  ? ThemeMode.dark
                  : ThemeMode.light;
            },
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded, color: Colors.blueAccent),
            tooltip: '查看报表',
            onPressed: _showStatsDialog,
          ),
          const SizedBox(width: 8),
        ],
      ),
      // 1. 使用 LayoutBuilder 获取屏幕宽度
      // ... AppBar 保持不变 ...
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isWide = constraints.maxWidth > 600;

          // 1. 准备 4 个象限的内容
          // 这里我们稍微改一下 _buildQuadrant，让它在 Tab 模式下不要显示标题（因为 Tab 栏上有标题）
          // 但为了简单，我们先直接复用
          List<Widget> quadrants = [
            _buildQuadrant(0, '重要且紧急', '立即去做！', Colors.red),
            _buildQuadrant(1, '重要不紧急', '制定计划', Colors.blue),
            _buildQuadrant(2, '紧急不重要', '授权', Colors.orange),
            _buildQuadrant(3, '不重要不紧急', '断舍离', Colors.green),
          ];

          Widget content;

          if (isWide) {
            // --- 💻 宽屏/电脑模式 ---
            content = Column(
              children: [
                // 👇 新增：AI 早报栏
                if (_dailyQuote != null || _loadingQuote)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      // 根据深色模式调整背景
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.indigo.shade900.withOpacity(0.3)
                          : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.indigoAccent.withOpacity(0.3)
                            : Colors.blue.shade100,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 左边的机器人头像/图标
                        const Icon(
                          Icons.smart_toy_rounded,
                          color: Colors.blueAccent,
                          size: 28,
                        ),
                        const SizedBox(width: 12),

                        // 右边的文字
                        Expanded(
                          child: _loadingQuote
                              ? const Text(
                                  'AI 正在观察你的状态...',
                                  style: TextStyle(color: Colors.grey),
                                )
                              : Text(
                                  _dailyQuote!,
                                  style: TextStyle(
                                    fontSize: 15,
                                    height: 1.4,
                                    fontWeight: FontWeight.w500,
                                    color:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.blue.shade100
                                        : Colors.blue.shade900,
                                  ),
                                ),
                        ),

                        // 关闭按钮 (不想看的时候关掉)
                        InkWell(
                          onTap: () => setState(() => _dailyQuote = null),
                          child: Icon(
                            Icons.close,
                            size: 18,
                            color: Colors.grey.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn().slideY(begin: -0.2, end: 0), // 加个丝滑入场动画
                // ✅ 手动在这里给每个象限包上 Expanded
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: quadrants[0]), // 左上
                      Expanded(child: quadrants[1]), // 右上
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: quadrants[2]), // 左下
                      Expanded(child: quadrants[3]), // 右下
                    ],
                  ),
                ),
              ],
            );
          } else {
            // --- 📱 手机模式：Tab 切换布局 (新功能) ---
            // 使用 DefaultTabController 包裹，无需手动管理 Controller
            return DefaultTabController(
              length: 4,
              child: Stack(
                children: [
                  Scaffold(
                    //把 TabBar 放在底部，更符合手机单手操作习惯
                    bottomNavigationBar: Material(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF1E1E1E)
                          : Colors.white,
                      elevation: 10,
                      // 👇 1. 包裹一层 Padding
                      child: Padding(
                        padding: const EdgeInsets.only(
                          right: 80.0,
                        ), // 👈 给右边留出 80像素 的空间给 FAB
                        child: TabBar(
                          labelColor: Colors.blueAccent,
                          unselectedLabelColor: Colors.grey,
                          indicatorSize: TabBarIndicatorSize.label,
                          // ... 其他属性不变 ...
                          tabs: const [
                            Tab(icon: Icon(Icons.flash_on), text: '紧急'),
                            Tab(icon: Icon(Icons.calendar_today), text: '计划'),
                            Tab(icon: Icon(Icons.people), text: '授权'),
                            Tab(icon: Icon(Icons.coffee), text: '闲事'),
                          ],
                        ),
                      ),
                    ),
                    body: TabBarView(
                      children: quadrants, // 直接把 4 个象限放进去，可以左右滑动！
                    ),
                  ),
                  // 别忘了把烟花层也加在手机模式里
                  Align(
                    alignment: Alignment.center,
                    child: ConfettiWidget(
                      confettiController: _confettiController,
                      blastDirectionality: BlastDirectionality.explosive,
                      shouldLoop: false,
                      createParticlePath: drawStar,
                      colors: const [
                        Colors.red,
                        Colors.blue,
                        Colors.amber,
                        Colors.green,
                      ],
                      numberOfParticles: 50,
                      gravity: 0.3,
                    ),
                  ),
                ],
              ),
            );
          }

          // --- 电脑模式的 Stack 返回 ---
          return Stack(
            children: [
              content,
              Align(
                alignment: Alignment.center,
                child: ConfettiWidget(
                  confettiController: _confettiController,
                  blastDirectionality: BlastDirectionality.explosive,
                  shouldLoop: false,
                  createParticlePath: drawStar,
                  colors: const [
                    Colors.red,
                    Colors.blue,
                    Colors.amber,
                    Colors.green,
                  ],
                  minBlastForce: 10,
                  maxBlastForce: 30,
                  numberOfParticles: 50,
                  gravity: 0.3,
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: GestureDetector(
        // 长按触发智能录入
        onLongPress: _showSmartAddDialog,
        child: FloatingActionButton(
          onPressed: () => _showTaskDialog(), // 普通点击还是原来的手动录入
          tooltip: '长按尝试 AI 智能录入',
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
  
  // ✨ 辅助函数：绘制五角星形状
  Path drawStar(Size size) {
    double degToRad(double deg) => deg * (pi / 180.0);

    const numberOfPoints = 5;
    final halfWidth = size.width / 2;
    final externalRadius = halfWidth;
    final internalRadius = halfWidth / 2.5;
    final degreesPerStep = degToRad(360 / numberOfPoints);
    final halfDegreesPerStep = degreesPerStep / 2;
    final path = Path();
    final fullAngle = degToRad(360);
    path.moveTo(size.width, halfWidth);

    for (double step = 0; step < fullAngle; step += degreesPerStep) {
      path.lineTo(
        halfWidth + externalRadius * cos(step),
        halfWidth + externalRadius * sin(step),
      );
      path.lineTo(
        halfWidth + internalRadius * cos(step + halfDegreesPerStep),
        halfWidth + internalRadius * sin(step + halfDegreesPerStep),
      );
    }
    path.close();
    return path;
  }

  // 修改：最后一个参数改为 MaterialColor baseColor，让函数内部决定深浅
  Widget _buildQuadrant(
    int priorityFilter,
    String title,
    String subtitle,
    MaterialColor baseColor,
  ) {
    final quadrantTasks = tasks
        .where((t) => t.priority == priorityFilter)
        .toList();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 🎨 智能颜色计算
    // 深色模式：背景要很暗 (opacity 0.15)，文字要亮 (shade100)
    // 亮色模式：背景要亮 (shade100)，文字要深 (shade900)
    final Color bgColor = isDark
        ? baseColor.shade400.withValues(alpha: 0.15)
        : baseColor.shade100;
    final Color textColor = isDark ? baseColor.shade100 : baseColor.shade900;

    // ✅ 现在直接返回 DragTarget
    return DragTarget<Task>(
      builder: (context, candidateData, rejectedData) {
        return Container(
          padding: const EdgeInsets.all(16),
          color: candidateData.isNotEmpty
              ? bgColor.withValues(alpha: isDark ? 0.3 : 0.8)
              : bgColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: textColor.withValues(alpha: 0.8),
                ),
              ),
              Divider(color: textColor.withValues(alpha: 0.2)),
              Expanded(
                child: ListView.builder(
                  itemCount: quadrantTasks.length,
                  itemBuilder: (context, index) {
                    final task = quadrantTasks[index];
                    return Draggable<Task>(
                      data: task,
                      feedback: Material(
                        color: Colors.transparent,
                        child: SizedBox(
                          width: 250,
                          child: _buildTaskCard(task, textColor),
                        ),
                      ),
                      childWhenDragging: Opacity(
                        opacity: 0.3,
                        child: _buildTaskCard(task, textColor),
                      ),
                      child: _buildTaskCard(task, textColor),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
      onAccept: (task) {
        if (task.priority != priorityFilter) {
          setState(() => task.priority = priorityFilter);
          _updateTask(task);
        }
      },
    );
  }
  Widget _buildTaskCard(Task task, Color textColor) {
    // 1. 处理日期显示逻辑
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String dateText = '';
    Color dateColor = Colors.grey;

    if (task.deadline != null) {
      dateText = '截止: ${task.deadline!.month}月${task.deadline!.day}日';
      // 只有未完成的任务才计算过期颜色
      if (task.deadline!.isBefore(
            DateTime.now().subtract(const Duration(days: 1)),
          ) &&
          !task.isDone) {
        dateColor = Colors.red;
        dateText += ' (已过期)';
      }
    }

    // 2. 构建卡片主体内容
    Widget cardContent =
        Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              color: (task.isDone)
                  ? (isDark
                        ? Colors.grey[800]!.withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.4))
                  : (isDark
                        ? const Color(0xFF2C2C2C)
                        : Colors.white.withValues(alpha: 0.95)),
              elevation: 0,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                // 双击进入专注模式
                onDoubleTap: () {
                  if (!task.isDone) {
                    _startFocusSession(task);
                  }
                },
                // 单击编辑任务
                onTap: () {
                  _showTaskDialog(taskToEdit: task);
                },
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  visualDensity: VisualDensity.compact,

                  // --- 🟢 修改点 1：左侧打钩按钮 ---
                  // 将原来的手动 setState 逻辑，替换为调用统一的 _toggleTaskStatus 方法
                  leading: IconButton(
                    icon: Icon(
                      task.isDone ? Icons.check_circle : Icons.circle_outlined,
                      size: 24, //稍微调大一点点更好点
                      color: task.isDone ? Colors.grey : textColor,
                    ),
                    onPressed: () {
                      // ✅ 调用新写的封装函数，它包含了：
                      // 1. 修改 isDone
                      // 2. 记录 completedAt 时间
                      // 3. 存入数据库
                      // 4. 震动反馈
                      _toggleTaskStatus(task);

                      // 🎉 只有烟花逻辑留在 UI 层（因为它属于纯视觉效果）
                      if (!task.isDone && task.priority <= 1) {
                        // 注意：因为 _toggleTaskStatus 是异步的，这里判断 !task.isDone
                        // 是因为点击的一瞬间状态还没变，或者你可以简单地直接播放
                        _confettiController.play();
                      }
                    },
                  ),

                  // --- 中间：任务标题 ---
                  title: Text(
                    task.name,
                    style: TextStyle(
                      fontSize: 14,
                      decoration: task.isDone
                          ? TextDecoration.lineThrough
                          : null,
                      color: task.isDone ? Colors.grey : Colors.black87,
                    ),
                  ),

                  // --- 🟢 修改点 2：副标题显示完成时间 ---
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 情况 A: 显示截止日期 (未完成时)
                      if (task.deadline != null && !task.isDone)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            dateText,
                            style: TextStyle(fontSize: 12, color: dateColor),
                          ),
                        ),

                      // 情况 B: 显示完成时间 (已完成时)
                      if (task.isDone && task.completedAt != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check,
                                size: 12,
                                color: Colors.green,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                // 记得在类里补上 _formatTime 函数，或者直接写 '${task.completedAt!.hour}:${task.completedAt!.minute}'
                                '完成于 ${_formatTime(task.completedAt!)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.green,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),

                  // --- 右侧：AI 拆解与删除 ---
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ✨ 魔法棒按钮
                      if (!task.isDone)
                        IconButton(
                          tooltip: 'AI 智能拆解',
                          icon: const Icon(
                            Icons.auto_awesome,
                            size: 20,
                            color: Colors.purpleAccent,
                          ),
                          onPressed: () {
                            _realAISplit(task);
                            HapticFeedback.mediumImpact();
                          },
                        ),

                      // 🗑️ 删除按钮 (手动点击)
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('删除任务？'),
                              content: Text('确定要删除“${task.name}”吗？'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('取消'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    _deleteTask(task);
                                    Navigator.pop(ctx);
                                  },
                                  child: const Text(
                                    '删除',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            )
            .animate()
            .fadeIn(duration: 500.ms)
            .slideY(
              begin: 0.1,
              end: 0,
              duration: 500.ms,
              curve: Curves.easeOutQuad,
            );

    // 3. 返回被 Dismissible 包裹的卡片 (实现右滑删除)
    return Dismissible(
      key: ValueKey(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              '删除',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.delete_forever, color: Colors.white),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        return await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('确认删除？'),
            content: Text('你要删除“${task.name}”吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('留着'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('删掉', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
      },
      onDismissed: (direction) {
        _deleteTask(task);
        HapticFeedback.mediumImpact();
      },
      child: cardContent,
    );
  }
}