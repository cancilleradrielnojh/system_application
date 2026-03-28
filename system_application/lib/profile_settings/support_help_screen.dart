// ========================= lib/profile_settings/support_help_screen.dart =========================
import 'package:flutter/material.dart';

class SupportHelpScreen extends StatelessWidget {
  const SupportHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Support & Help'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.eco, color: Colors.green, size: 40),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Q-Lamansi',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        SizedBox(height: 4),
                        Text(
                          'Calamansi sapling health evaluation '
                          'for smart farmers.',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Text('App Features',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            _section(
              icon: Icons.camera_alt,
              color: Colors.green,
              title: 'Scanning a Sapling',
              steps: [
                'Tap START SCANNING on the Home screen.',
                'Choose Capture Image to use your camera, or '
                    'Upload from Gallery to pick an image.',
                'Position the sapling inside the green frame.',
                'The AI model will analyze the image automatically.',
                'If a calamansi sapling is detected, you will see '
                    'the result and a recommendation.',
                'Tap Done to save and go home, or Scan New to '
                    'scan another sapling.',
                'If no sapling is detected, the scan will NOT be saved.',
              ],
            ),

            _section(
              icon: Icons.bar_chart,
              color: Colors.blue,
              title: 'Health Score Explained',
              steps: [
                '90%–100% → ✅ Healthy: Sapling is in excellent condition.',
                '60%–89%  → 🟡 Yellowing: Possible nutrient deficiency.',
                '40%–59%  → 🥀 Wilting: Check watering and drainage.',
                '0%–39%   → 🐛 Pest-Damaged: Apply treatment immediately.',
              ],
            ),

            _section(
              icon: Icons.history,
              color: Colors.orange,
              title: 'Scan History',
              steps: [
                'Tap the History tab to view all previous scans.',
                'Each record shows the image, health score, '
                    'class label, and scan time.',
                'Only confirmed calamansi detections are saved.',
                'Pull down to refresh the list.',
              ],
            ),

            _section(
              icon: Icons.show_chart,
              color: Colors.teal,
              title: 'Market Insights',
              steps: [
                'Tap the Market tab for a summary of all scanned saplings.',
                'Cards show Healthy, Yellowing, Pest/Wilting counts '
                    'and total scanned.',
                'Pull down to refresh after new scans.',
              ],
            ),

            _section(
              icon: Icons.notifications,
              color: Colors.purple,
              title: 'Push Notifications',
              steps: [
                'After each successful scan you receive a snackbar alert.',
                'The alert shows the class and health score.',
                'Toggle notifications in Settings → Push Notifications.',
              ],
            ),

            _section(
              icon: Icons.person,
              color: Colors.indigo,
              title: 'Profile & Settings',
              steps: [
                'Tap the Settings tab to manage your profile.',
                'Profile Settings — change name, farm name, location.',
                'Dark Mode — switch between light and dark appearance.',
                'Push Notifications — toggle scan result alerts.',
                'Clear All App Data — permanently deletes all scans.',
              ],
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            const Text('Contact & Feedback',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'For bug reports or feature suggestions, please reach '
              'out to the development team. Your feedback helps '
              'improve Q-Lamansi for all farmers.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Version 1.0.0 — Q-Lamansi Calamansi '
                      'Sapling Health Evaluator',
                      style: TextStyle(
                          color: Colors.grey, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _section({
    required IconData icon,
    required Color color,
    required String title,
    required List<String> steps,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05), // ✅ fixed
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor:
                    color.withValues(alpha: 0.12), // ✅ fixed
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...steps.asMap().entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${e.key + 1}. ',
                          style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold)),
                      Expanded(
                          child: Text(e.value,
                              style: const TextStyle(
                                  fontSize: 13))),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}