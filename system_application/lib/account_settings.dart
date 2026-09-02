// ========================= lib/account_settings.dart =========================
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_settings/theme_notifier.dart';
import 'profile_settings/profile_settings_screen.dart';
import 'profile_settings/support_help_screen.dart';
import 'theme/app_theme.dart';
import 'theme/app_widgets.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? AppColors.darkText : AppColors.ink;
    final muted = isDark ? AppColors.darkMuted : AppColors.steel;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BrandMark(size: 36),
              const SizedBox(width: 10),
              Text(
                'Q-LAMANSI',
                style: GoogleFonts.spaceGrotesk(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 1.5,
                  color: muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Settings',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              color: ink,
            ),
          ),
          const SizedBox(height: 18),

          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? const [Color(0xFF16352C), Color(0xFF0E1A16)]
                    : const [AppColors.ink, Color(0xFF16352C)],
              ),
              border: Border.all(
                color: AppColors.lime.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.lime,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.person_rounded,
                      color: AppColors.ink, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: GoogleFonts.spaceGrotesk(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Field operator',
                        style: GoogleFonts.dmSans(
                          color: AppColors.lime.withValues(alpha: 0.9),
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '$totalScans session scan(s)',
                        style: GoogleFonts.dmSans(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionLabel('Preferences'),
          const SizedBox(height: 10),

          _tappableItem(
            icon: Icons.badge_outlined,
            title: 'Profile Settings',
            subtitle: 'Name, farm, location',
            onTap: () async {
              final newName = await Navigator.push<String>(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfileSettingsScreen(
                      currentName: displayName),
                ),
              );
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
          _toggleItem(
            icon: Icons.dark_mode_outlined,
            title: 'Dark Mode',
            subtitle: themeNotifier.isDark ? 'Dark active' : 'Light active',
            value: themeNotifier.isDark,
            onChanged: (_) => themeNotifier.toggleTheme(),
          ),
          const SizedBox(height: 8),
          _toggleItem(
            icon: Icons.notifications_none_rounded,
            title: 'Push Notifications',
            subtitle: notificationsEnabled ? 'Alerts on' : 'Alerts off',
            value: notificationsEnabled,
            onChanged: toggleNotifications,
          ),
          const SizedBox(height: 8),
          _tappableItem(
            icon: Icons.help_outline_rounded,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: GlassPanel(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon,
                color: isDark ? AppColors.lime : AppColors.tealDeep),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: isDark ? AppColors.darkMuted : AppColors.steel,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: isDark ? AppColors.darkMuted : AppColors.steel),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Icon(icon,
              color: isDark ? AppColors.lime : AppColors.tealDeep),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: isDark ? AppColors.darkMuted : AppColors.steel,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: isDark ? AppColors.ink : Colors.white,
            activeTrackColor: isDark ? AppColors.lime : AppColors.teal,
          ),
        ],
      ),
    );
  }
}
