import 'package:flutter/material.dart';
import 'service/auth_service.dart';
import './screen/auth_screen.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Auth',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const AuthScreen(), // единый экран
    );
  }
}