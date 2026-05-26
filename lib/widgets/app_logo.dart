import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final double iconSize;
  final double radius;

  const AppLogo({
    super.key,
    this.size = 72,
    this.iconSize = 36,
    this.radius = 18,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primaryBlue,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(
        Icons.work_outline_rounded,
        color: Colors.white,
        size: iconSize,
      ),
    );
  }
}
