// ========================= lib/profile_settings/profile_settings_screen.dart =========================
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'name_notifier.dart';                            // ← new import

class ProfileSettingsScreen extends StatefulWidget {
  final String currentName;
  const ProfileSettingsScreen({super.key, required this.currentName});

  @override
  State<ProfileSettingsScreen> createState() =>
      _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState
    extends State<ProfileSettingsScreen> {
  late TextEditingController nameController;
  final TextEditingController locationController =
      TextEditingController();
  final TextEditingController farmNameController =
      TextEditingController();

  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    nameController =
        TextEditingController(text: widget.currentName);
    loadExtra();
  }

  Future<void> loadExtra() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      locationController.text =
          prefs.getString('location') ?? '';
      farmNameController.text =
          prefs.getString('farmName') ?? '';
    });
  }

  Future<void> saveProfile() async {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name cannot be empty')),
      );
      return;
    }

    setState(() => isSaving = true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', name);
    await prefs.setString(
        'location', locationController.text.trim());
    await prefs.setString(
        'farmName', farmNameController.text.trim());

    // ── Notify all listeners (home.dart greeting) of the new name.
    //    This fires instantly — home.dart updates before the user
    //    even navigates back to the Home tab.
    nameNotifier.value = name;

    setState(() => isSaving = false);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Profile saved successfully!'),
        backgroundColor: Colors.green,
      ),
    );

    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile Settings'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 48,
                    backgroundColor: Colors.green,
                    child: Icon(Icons.person,
                        size: 52, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    nameController.text.isEmpty
                        ? 'Farmer'
                        : nameController.text,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const Text('Personal Info',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildField(
              controller: nameController,
              label: 'Display Name',
              icon: Icons.person_outline,
              hint: 'e.g. Juan Dela Cruz',
            ),
            const SizedBox(height: 14),
            _buildField(
              controller: farmNameController,
              label: 'Farm Name (optional)',
              icon: Icons.agriculture,
              hint: 'e.g. Dela Cruz Farm',
            ),
            const SizedBox(height: 14),
            _buildField(
              controller: locationController,
              label: 'Location (optional)',
              icon: Icons.location_on_outlined,
              hint: 'e.g. Iloilo City, Philippines',
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: isSaving ? null : saveProfile,
              icon: const Icon(Icons.save),
              label: Text(
                  isSaving ? 'Saving…' : 'Save Changes'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),

          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    locationController.dispose();
    farmNameController.dispose();
    super.dispose();
  }
}