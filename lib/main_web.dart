import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'client/presentation/screens/login_screen.dart';

void main() {
  runApp(const ProviderScope(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "SMS Web Client",
      home: LoginScreen(),
    ),
  ));
}