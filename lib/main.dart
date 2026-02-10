import 'package:flutter/material.dart';
import 'host/service/background_service_logic.dart';
import 'host/presentation/screens/inbox_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeBackgroundService();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'SMS Host',
    home: InboxScreen(),
  ));
}