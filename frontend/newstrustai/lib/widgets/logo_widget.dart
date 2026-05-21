import 'package:flutter/material.dart';

/// Circular logo container used on splash, login, and signup screens.
class LogoWidget extends StatelessWidget {
  final double size;
  final double padding;
  final double shadowBlur;

  const LogoWidget({
    super.key,
    this.size = 150,
    this.padding = 5,
    this.shadowBlur = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.1),
            blurRadius: shadowBlur,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Image.asset(
        'assets/images/logo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }
}
