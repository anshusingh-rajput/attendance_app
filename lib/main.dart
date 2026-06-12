import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/auth_gate.dart';

void main() {
  runApp(const HR360FlowApp());
}

class HR360FlowApp extends StatelessWidget {
  const HR360FlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HIMMAT',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const AuthGate(),
    );
  }
}
