import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../services/auth_service.dart';
import '../services/consent_service.dart';
import 'consent_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'registration_selfie_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _auth = AuthService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final existing = await _auth.getToken();
    if (!mounted) return;

    if (existing == null || existing.isEmpty) {
      _goLogin();
      return;
    }

    final result = await _auth.refreshToken();
    if (!mounted) return;

    if (result.isSuccess) {
      final photoUrl = await _auth.getProfilePhotoUrl();
      if (!mounted) return;
      final needsSetup = photoUrl == null || photoUrl.isEmpty;

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
      await _auth.logout();
      if (!mounted) return;
      _goLogin();
    }
  }

  void _goLogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              AppLogo(size: 96, iconSize: 48, radius: 22),
              SizedBox(height: 28),
              Text(
                'MEDHA',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkText,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Attendance Management',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.subtitleGrey,
                ),
              ),
              SizedBox(height: 56),
              SizedBox(
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
