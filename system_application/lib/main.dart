// ========================= lib/main.dart =========================
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'user_verification.dart';
import 'home.dart';
import 'profile_settings/theme_notifier.dart';
import 'profile_settings/name_notifier.dart';         // ← new import
import 'profile_settings/notification_service.dart';
import 'detection/inference_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await inferenceService.loadModel();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String? name;
  bool    isLoading = true;

  @override
  void initState() {
    super.initState();
    loadUser();
    themeNotifier.addListener(() {
      setState(() {});
    });
  }

  Future<void> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString('username');

    // ── Initialize nameNotifier so home.dart has the correct name
    //    from the very first frame, even before any profile change.
    if (savedName != null) {
      nameNotifier.value = savedName;
    }

    setState(() {
      name      = savedName;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: NotificationService.messengerKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: themeNotifier.value,
      home: name == null
          ? const UserVerification()
          : Home(name: name!),
    );
  }
}