import 'package:flutter/material.dart';

import 'core/access/auth_session.dart';
import 'features/access/access_page.dart';
import 'features/donantes/data/donante_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key, this.session, this.donantes});
  final AuthSession? session;
  final DonanteRepository? donantes;

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
      home: AccessPage(session: session, donantes: donantes),
    );
  }
}
