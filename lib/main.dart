// ========================= lib/main.dart =========================
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'user_verification.dart';
import 'home.dart';
import 'profile_settings/theme_notifier.dart';
import 'profile_settings/name_notifier.dart';
import 'profile_settings/notification_service.dart';
import 'detection/inference_service.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Show the app immediately. The ONNX models load in the background: waiting
  // for them here left the app stuck on the launch screen whenever loading was
  // slow or failed (an uncaught error before runApp never shows anything).
  runApp(const MyApp());
  unawaited(
    inferenceService.loadModel().catchError((Object e) {
      debugPrint('Background model load failed: $e');
    }),
  );
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
    String? savedName;
    try {
      final prefs = await SharedPreferences.getInstance();
      savedName = prefs.getString('username');
      if (savedName != null) {
        nameNotifier.value = savedName;
      }
    } catch (e) {
      // Never leave the app on the loading spinner because saved settings
      // could not be read: continue as a first-time user instead.
      debugPrint('Could not read saved name: $e');
    }

    if (!mounted) return;
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
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