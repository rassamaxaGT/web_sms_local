import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'client/presentation/screens/login_screen.dart';
import 'shared/theme.dart';
import 'shared/storage_helper.dart';
import 'client/logic/notification_service.dart';
import 'client/logic/callback_scheduler.dart';
import 'client/logic/providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initDesktopStorage();
  SfxService.init();
  
  globalContainer = ProviderContainer();
  await NotificationService.instance.init();
  CallbackScheduler.instance.start();
  
  runApp(UncontrolledProviderScope(
    container: globalContainer!,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "SMS Web Client",
      themeMode: ThemeMode.dark,
      darkTheme: AppTheme.darkTheme,
      home: const LoginScreen(),
    ),
  ));
}
