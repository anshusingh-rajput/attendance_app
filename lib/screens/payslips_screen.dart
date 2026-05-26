import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PayslipsScreen extends StatefulWidget {
  const PayslipsScreen({super.key});

  @override
  State<PayslipsScreen> createState() => _PayslipsScreenState();
}

class _PayslipsScreenState extends State<PayslipsScreen> {
  static const _years = <int>[2025, 2026, 2027];
  int _year = 2026;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.darkText),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Payslips',
          style: TextStyle(
            color: AppColors.darkText,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: PopupMenuButton<int>(
              onSelected: (v) => setState(() => _year = v),
              offset: const Offset(0, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              itemBuilder: (_) => [
                for (final y in _years)
                  PopupMenuItem<int>(
                    value: y,
                    child: Text(
                      '$y',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: y == _year
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: AppColors.darkText,
                      ),
                    ),
                  ),
              ],
              child: Row(
                children: [
                  Text(
                    '$_year',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkText,
                    ),
                  ),
                  const Icon(
                    Icons.arrow_drop_down_rounded,
                    color: AppColors.darkText,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 72,
                color: AppColors.subtitleGrey.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 18),
              const Text(
                'No payslips yet',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.subtitleGrey,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your monthly payslips will appear here once HR uploads them.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.subtitleGrey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
