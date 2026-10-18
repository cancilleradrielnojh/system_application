// ========================= lib/main.dart =========================
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'user_verification.dart';
import 'home.dart';
import 'profile_settings/theme_notifier.dart';
import 'profile_settings/name_notifier.dart';
import 'profile_settings/notification_service.dart';
import 'detection/inference_service.dart';
import 'theme/app_theme.dart';

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
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Scaffold(
          backgroundColor: AppColors.mist,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.spa_rounded,
                      color: AppColors.lime, size: 28),
                ),
                const SizedBox(height: 20),
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColors.teal,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: NotificationService.messengerKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeNotifier.value,
      home: name == null
          ? const UserVerification()
          : Home(name: name!),
    );
  }
}
