// ========================= lib/account_settings.dart =========================
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_settings/theme_notifier.dart';
import 'profile_settings/profile_settings_screen.dart';
import 'profile_settings/support_help_screen.dart';

class AccountSettingsScreen extends StatefulWidget {
  final String name;
  const AccountSettingsScreen({super.key, required this.name});

  @override
  State<AccountSettingsScreen> createState() =>
      _AccountSettingsScreenState();
}

class _AccountSettingsScreenState
    extends State<AccountSettingsScreen> {
  late String displayName;
  bool notificationsEnabled = true;
  int  totalScans           = 0;

  @override
  void initState() {
    super.initState();
    displayName = widget.name;
    loadPrefs();
    themeNotifier.addListener(() {
      if (mounted) setState(() {});
    });
  }

  Future<void> loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      notificationsEnabled =
          prefs.getBool('pushNotifications') ?? true;
      totalScans  = prefs.getInt('scansToday') ?? 0;
      displayName = prefs.getString('username') ?? widget.name;
    });
  }

  Future<void> toggleNotifications(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pushNotifications', value);
    if (!mounted) return;
    setState(() => notificationsEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // App header
          Row(
            children: [
              const CircleAvatar(
                  backgroundColor: Colors.green,
                  child: Icon(Icons.spa, color: Colors.white)),
              const SizedBox(width: 8),
              const Text('Q-Lamansi',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Settings',
              style: TextStyle(
                  fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          // Profile card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person,
                      color: Colors.green, size: 32),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    const Text('Q-Lamansi Farmer',
                        style: TextStyle(color: Colors.white70)),
                    Text('$totalScans total scan(s)',
                        style: const TextStyle(
                            color: Colors.white70)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Profile settings
          _tappableItem(
            icon: Icons.person,
            title: 'Profile Settings',
            subtitle: 'Change name, farm name, location',
            onTap: () async {
              final newName = await Navigator.push<String>(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfileSettingsScreen(
                      currentName: displayName),
                ),
              );
              // ✅ fixed: mounted check before using context
              if (!mounted) return;
              if (newName != null && newName.isNotEmpty) {
                setState(() => displayName = newName);
              } else if (newName == '') {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('history');
                await prefs.remove('scansToday');
                await prefs.remove('avgHealth');
                if (!mounted) return;
                if (!context.mounted) return;
                Navigator.of(context)
                    .pushNamedAndRemoveUntil('/', (r) => false);
              }
            },
          ),
          const SizedBox(height: 8),

          // Dark mode
          _toggleItem(
            icon: Icons.dark_mode,
            title: 'Dark Mode',
            subtitle: themeNotifier.isDark
                ? 'Currently: Dark'
                : 'Currently: Light',
            value: themeNotifier.isDark,
            onChanged: (_) => themeNotifier.toggleTheme(),
          ),
          const SizedBox(height: 8),

          // Push notifications
          _toggleItem(
            icon: Icons.notifications,
            title: 'Push Notifications',
            subtitle: notificationsEnabled
                ? 'Scan result alerts are ON'
                : 'Scan result alerts are OFF',
            value: notificationsEnabled,
            onChanged: toggleNotifications,
          ),
          const SizedBox(height: 8),

          // Support
          _tappableItem(
            icon: Icons.help_outline,
            title: 'Support & Help',
            subtitle: 'How to use Q-Lamansi',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const SupportHelpScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tappableItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04), // ✅ fixed
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.green),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _toggleItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04), // ✅ fixed
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.green),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.green, // ✅ fixed: was activeColor
          ),
        ],
      ),
    );
  }
}