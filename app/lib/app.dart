import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

class UndersignApp extends StatelessWidget {
  const UndersignApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'undersign-assist',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const HomeScreen(),
    );
  }
}
