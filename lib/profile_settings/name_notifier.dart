// ========================= lib/profile_settings/name_notifier.dart =========================
import 'package:flutter/foundation.dart';

/// Global notifier for the display name.
/// Works exactly like themeNotifier — any widget that listens to it
/// will rebuild automatically when the name is changed in Profile Settings.
final nameNotifier = ValueNotifier<String>('');