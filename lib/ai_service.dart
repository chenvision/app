// lib/ai_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;

class AIService {
  // 🔴 警告：正式上线时，API Key 应该放在后端 (如 Supabase Edge Function)，防止泄露。
  // 但作为个人项目，直接写在这里跑通功能是最快的。
  static const String _apiKey = 'sk-2d84097582744db3a2c3613cf231bf4b';
  static const String _baseUrl = 'https://api.deepseek.com/chat/completions';

  /// 智能拆解任务
  /// 输入："备考雅思"
  /// 输出：["背诵核心词汇", "练习剑桥雅思听力", "准备口语话题卡"]
  static Future<List<String>> splitTask(String taskName) async {
    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          "model": "deepseek-chat", // 使用 DeepSeek V3
          "messages": [
            {
              "role": "system",
              "content": """
你是一个高效的时间管理专家。
请将用户的任务拆解为 3 到 5 个具体的、可执行的子任务。
要求：
1. 直接返回一个纯 JSON 字符串数组。
2. 不要包含 Markdown 格式（如 ```json）。
3. 不要说废话。
例如输入："做饭"，输出：["买菜", "洗菜切菜", "炒菜", "煮饭"]
""",
            },
            {"role": "user", "content": taskName},
          ],
          "temperature": 0.7, // 创造性适中
        }),
      );

      if (response.statusCode == 200) {
        // 1. 解析 UTF-8 (防止中文乱码)
        final body = utf8.decode(response.bodyBytes);
        final jsonResponse = jsonDecode(body);

        // 2. 获取 AI 回复的内容
        String content = jsonResponse['choices'][0]['message']['content'];

        // 3. 清理一下可能存在的 Markdown 符号 (以防万一 AI 不听话)
        content = content
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();

        // 4. 转成 List<String>
        List<dynamic> list = jsonDecode(content);
        return list.map((e) => e.toString()).toList();
      } else {
        throw Exception('AI 请求失败: ${response.statusCode}');
      }
    } catch (e) {
      print('AI Error: $e');
      return []; // 出错返回空列表
    }
  }
  /// 获取每日 AI 评语
  static Future<String?> getDailyAdvice(List<dynamic> tasks) async {
    try {
      // 1. 简单的统计一下当前状态
      int importantUrgent = 0;
      int overdue = 0;
      int finished = 0;
      final now = DateTime.now();

      for (var t in tasks) {
        if (t['is_done'] == true) {
          finished++;
          continue;
        }
        if (t['priority'] == 0) importantUrgent++;
        if (t['deadline'] != null) {
          final deadline = DateTime.parse(t['deadline']);
          if (deadline.isBefore(now)) overdue++;
        }
      }

      // 2. 构造 Prompt (提示词) —— 这里就是你赋予它“人格”的地方！
      // 你可以在这里告诉 AI：你是个 Computer Science 学生，在备考雅思，性格需要鼓励还是鞭策。
      final prompt =
          """
你是一个个性鲜明的私人时间管理教练。
用户的当前状态：
- 待办的重要紧急任务：$importantUrgent 个
- 已过期任务：$overdue 个
- 近期已完成：$finished 个
- 用户身份：22岁 CS专业学生，正在备考雅思，有时会焦虑。

请根据以上数据，生成一句简短的早报评语（50字以内）。
风格要求：
- 如果有过任务或堆积多：犀利、幽默、带点“毒舌”的鞭策，提醒他雅思不等人。
- 如果状态好：温暖、幽默的鼓励，让他注意休息。
- 不要像个机器人，要像个认识很久的损友。
""";

      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          "model": "deepseek-chat",
          "messages": [
            {"role": "user", "content": prompt},
          ],
          "temperature": 1.0, // 温度高一点，让它说话更有趣
        }),
      );

      if (response.statusCode == 200) {
        final body = utf8.decode(response.bodyBytes);
        return jsonDecode(body)['choices'][0]['message']['content'].trim();
      }
    } catch (e) {
      print('AI Advice Error: $e');
    }
    return null;
  }
  // lib/ai_service.dart

  /// 生成长线学习计划
  /// 输入："备考雅思听力"，天数：30
  /// 输出：一个包含 30 个任务的 List，每个任务带具体的日期
  static Future<List<Map<String, dynamic>>> generateStudyPlan(
    String goal,
    int days,
  ) async {
    try {
      final now = DateTime.now();

      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          "model": "deepseek-chat",
          "messages": [
            {
              "role": "system",
              "content":
                  """
你是一个专业的学习规划师。当前日期是：${now.toIso8601String().split('T')[0]}。
请根据用户目标，生成一个为期 $days 天的详细学习计划。
要求：
1. 规划必须有阶段性（如：基础期 -> 强化期 -> 冲刺期）。
2. 每天生成 1 个核心任务（不要太碎）。
3. 自动推算每一天的日期（deadline）。
4. 优先级设置：关键节点设为 0 (重要紧急)，普通练习设为 1 (重要不急)。
5. 返回纯 JSON 数组格式，不要 Markdown。

格式示例：
[
  {"name": "第1天：雅思听力S1场景词汇听写", "priority": 1, "deadline": "2026-02-02T10:00:00"},
  {"name": "第2天：剑桥雅思4 Test1 听力精听", "priority": 1, "deadline": "2026-02-03T10:00:00"}
]
""",
            },
            {"role": "user", "content": "目标：$goal"},
          ],
          "temperature": 0.5, // 稍微严谨一点，保证计划合理
        }),
      );

      if (response.statusCode == 200) {
        final body = utf8.decode(response.bodyBytes);
        var content = jsonDecode(body)['choices'][0]['message']['content'];
        content = content
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();

        List<dynamic> list = jsonDecode(content);
        return list.map((e) => e as Map<String, dynamic>).toList();
      }
    } catch (e) {
      print('Plan Gen Error: $e');
    }
    return [];
  }

  // lib/ai_service.dart

  /// 智能分析任务意图
  /// 输入："下周五之前必须把雅思大作文写完，很急"
  /// 输出：{"name": "写完雅思大作文", "priority": 0, "deadline": "2026-02-13T00:00:00"}
  static Future<Map<String, dynamic>?> smartAnalyze(String text) async {
    try {
      final now = DateTime.now();

      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          "model": "deepseek-chat",
          "messages": [
            {
              "role": "system",
              "content":
                  """
你是一个任务分析助手。当前时间是：$now。
请分析用户的输入，提取以下信息并返回纯 JSON 格式：
1. name: 任务核心内容。
2. priority: 根据紧急程度判断，0=重要紧急, 1=重要不急, 2=紧急不重, 3=不重不急(默认)。
3. deadline: 推算具体的 ISO8601 时间字符串 (如 "2026-02-15T14:00:00")，如果没有提到时间则为 null。

示例输入："明天下午交报告，急"
示例输出：{"name": "交报告", "priority": 0, "deadline": "2026-02-02T14:00:00"}

注意：只返回 JSON，不要 Markdown 格式。
""",
            },
            {"role": "user", "content": text},
          ],
          "temperature": 0.1, // 低温度，保证输出格式稳定
        }),
      );

      if (response.statusCode == 200) {
        final body = utf8.decode(response.bodyBytes);
        var content = jsonDecode(body)['choices'][0]['message']['content'];
        // 清理一下可能的 markdown 符号
        content = content
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();
        return jsonDecode(content);
      }
    } catch (e) {
      print('AI Analyze Error: $e');
    }
    return null;
  }
}
