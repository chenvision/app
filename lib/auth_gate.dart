// lib/auth_gate.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// 👇 引入你的页面文件
import 'login_page.dart';
import 'main.dart'; // 如果你的 HomePage 类还在 main.dart 里，就需要引入这个。
// 如果你把 HomePage 也单独拆出去了（比如叫 home_page.dart），这里就改成 import 'home_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      // 监听 Supabase 的用户状态变化流
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // loading 状态
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // 核心判断：session 是否存在？
        final session = snapshot.data?.session;

        if (session != null) {
          // ✅ 已登录 -> 进主页
          return const HomePage();
        } else {
          // ❌ 未登录 -> 进登录页
          return const LoginPage();
        }
      },
    );
  }
}
