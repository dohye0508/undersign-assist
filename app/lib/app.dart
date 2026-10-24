import 'package:flutter/material.dart';

import 'screens/workspace_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/splash_gate.dart';

class UndersignApp extends StatelessWidget {
  const UndersignApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '들리는계약서',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      // 처음 켤 때 흰 시작 화면이 3.5초 동안 보였다가 걷히며 메인 화면이 드러난다
      builder: (context, child) => SplashGate(child: child ?? const SizedBox.shrink()),
      home: const WorkspaceScreen(),
    );
  }
}
