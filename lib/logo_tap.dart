import 'package:flutter/material.dart';

class LogoTap extends StatefulWidget {
  const LogoTap({super.key});

  @override
  State<LogoTap> createState() => _LogoTapState();
}

class _LogoTapState extends State<LogoTap> {
  bool _big = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () => setState(() => _big = !_big),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            width: _big ? 500: 250,
            height: _big ? 400 : 200,
            child: Image.asset(
              'assets/images/logo.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: _big ? 1 : 0,
          child: const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text(
              'Q-LAMANSI',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}