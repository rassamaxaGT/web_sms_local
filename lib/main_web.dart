import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'client/presentation/screens/login_screen.dart';
import 'shared/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SfxService.init();
  runApp(ProviderScope(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "SMS Web Client",
      themeMode: ThemeMode.dark,
      darkTheme: AppTheme.darkTheme,
      home: const LoginScreen(),
    ),
  ));
}