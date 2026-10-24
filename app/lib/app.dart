import 'package:flutter/material.dart';

import 'screens/workspace_screen.dart';
import 'theme/app_theme.dart';

class UndersignApp extends StatelessWidget {
  const UndersignApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'undersign',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const WorkspaceScreen(),
    );
  }
}
