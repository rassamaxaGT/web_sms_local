import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'host/service/background_service_logic.dart';
import 'host/presentation/screens/inbox_screen.dart';
import 'shared/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await initializeBackgroundService();
  SfxService.init();

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'SMS Host',
    themeMode: ThemeMode.dark,
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    home: const InboxScreen(),
  ));
}