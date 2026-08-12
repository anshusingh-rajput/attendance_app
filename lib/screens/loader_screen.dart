import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../services/auth_service.dart';
import '../services/consent_service.dart';
import 'consent_screen.dart';
import 'home_screen.dart';
import 'registration_selfie_screen.dart';

class LoaderScreen extends StatefulWidget {
  final String username;
  final String password;

  const LoaderScreen({
    super.key,
    required this.username,
    required this.password,
  });

  @override
  State<LoaderScreen> createState() => _LoaderScreenState();
}

class _LoaderScreenState extends State<LoaderScreen> {
  final _auth = AuthService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _login());
  }

  Future<void> _login() async {
    final result = await _auth.login(
      username: widget.username,
      password: widget.password,
    );

    if (!mounted) return;

    if (result.isSuccess) {
      final photoUrl = await _auth.getProfilePhotoUrl();
      if (!mounted) return;
      final needsSetup = photoUrl == null || photoUrl.isEmpty;

      // First sign-in → show the one-time consent form before entering.
      final username = await _auth.getUsername();
      final mustConsent =
          await ConsentService.instance.needsConsent(username);
      if (!mounted) return;
      if (mustConsent) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ConsentScreen(
              token: result.token!,
              needsSetup: needsSetup,
              username: username,
            ),
          ),
        );
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => needsSetup
              ? RegistrationSelfieScreen(token: result.token!)
              : HomeScreen(token: result.token!),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Login failed')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AppLogo(size: 96, iconSize: 48, radius: 22),
              const SizedBox(height: 28),
              const Text(
                'MEDHA',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkText,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Attendance Management',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.subtitleGrey,
                ),
              ),
              const SizedBox(height: 56),
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
