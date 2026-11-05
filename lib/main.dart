import 'package:flutter/material.dart';

import 'features/access/demo_access_page.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'HemoLink',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF9B2743)),
        scaffoldBackgroundColor: const Color(0xFFF4F6F6),
        useMaterial3: true,
      ),
      home: const DemoAccessPage(),
    );
  }
}
