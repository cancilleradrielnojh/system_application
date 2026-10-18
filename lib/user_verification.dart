// ========================= lib/user_verification.dart =========================
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home.dart';
import 'theme/app_theme.dart';
import 'theme/app_widgets.dart';

class UserVerification extends StatefulWidget {
  const UserVerification({super.key});

  @override
  State<UserVerification> createState() => _UserVerificationState();
}

class _UserVerificationState extends State<UserVerification>
    with SingleTickerProviderStateMixin {
  final TextEditingController controller = TextEditingController();
  late final AnimationController _anim;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward();
  }

  Future<void> saveName() async {
    if (controller.text.trim().isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', controller.text.trim());

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
          builder: (_) => Home(name: controller.text.trim())),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BrandMark(size: 48),
                    const Spacer(flex: 2),
                    Text(
                      'Q-LAMANSI',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.0,
                        color: Theme.of(context).colorScheme.onSurface,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Sapling health, read at a glance.',
                      style: GoogleFonts.dmSans(
                        fontSize: 16,
                        height: 1.4,
                        color: AppColors.steel,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 48,
                      height: 3,
                      decoration: BoxDecoration(
                        color: AppColors.limeDeep,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const Spacer(flex: 2),
                    const SectionLabel('Identify yourself'),
                    const SizedBox(height: 10),
                    TextField(
                      controller: controller,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Your name',
                        hintText: 'e.g. DELA CRUZ, JUAN',
                      ),
                      onSubmitted: (_) => saveName(),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton(
                      onPressed: saveName,
                      child: const Text('Enter workspace'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Built for calamansi growers — scan, classify, act.',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: AppColors.steel.withValues(alpha: 0.85),
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    controller.dispose();
    super.dispose();
  }
}
