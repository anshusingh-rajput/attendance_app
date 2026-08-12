import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/consent_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'registration_selfie_screen.dart';

/// One-time consent form shown on a user's first sign-in (requirement 27).
/// The user must tick "I Agree" and tap Accept to enter the app; declining
/// signs them out.
class ConsentScreen extends StatefulWidget {
  final String token;
  final bool needsSetup;
  final String? username;

  /// When true, a successful accept just pops this screen with `true` instead
  /// of navigating into the app. Used when the screen is opened mid-flow (e.g.
  /// a punch was rejected with "Consent required") so the caller can retry.
  final bool returnOnAccept;

  const ConsentScreen({
    super.key,
    required this.token,
    required this.needsSetup,
    this.username,
    this.returnOnAccept = false,
  });

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _agreed = false;
  bool _submitting = false;
  bool _loadingDoc = true;
  ConsentDocument? _doc;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  Future<void> _loadDocument() async {
    final doc = await ConsentService.instance.fetchDocument();
    if (!mounted) return;
    setState(() {
      _doc = doc;
      _loadingDoc = false;
    });
  }

  /// The policy body to render: server fullText, else joined sections, else
  /// the built-in fallback text.
  String get _bodyText {
    final full = _doc?.fullText;
    if (full != null && full.trim().isNotEmpty) return full;
    final sections = _doc?.sections ?? const [];
    if (sections.isNotEmpty) return sections.join('\n\n');
    return _consentText;
  }

  Future<void> _onAccept() async {
    if (!_agreed || _submitting) return;
    setState(() => _submitting = true);
    final ok = await ConsentService.instance.submitConsent(
      username: widget.username,
      version: _doc?.version,
    );
    if (!mounted) return;

    // Only proceed once the backend has actually recorded the acceptance —
    // otherwise the user would re-enter the app and be blocked again at punch.
    if (!ok) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not record your consent. Check your connection and try again.',
          ),
        ),
      );
      return;
    }

    if (widget.returnOnAccept) {
      Navigator.of(context).pop(true);
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => widget.needsSetup
            ? RegistrationSelfieScreen(token: widget.token)
            : HomeScreen(token: widget.token),
      ),
    );
  }

  Future<void> _onDecline() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Consent required'),
        content: const Text(
          'You must accept the consent to use MEDHA. Declining will sign '
          'you out. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Go Back'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFEF4444),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Decline & Sign Out'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await AuthService().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Block back navigation — consent must be answered explicitly.
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const AppLogo(size: 44, iconSize: 22, radius: 12),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        (_doc?.title?.trim().isNotEmpty ?? false)
                            ? _doc!.title!
                            : 'User Consent',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.darkText,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  (_doc?.introduction?.trim().isNotEmpty ?? false)
                      ? _doc!.introduction!
                      : 'Please read and accept to continue.',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.subtitleGrey,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.borderGrey),
                    ),
                    child: _loadingDoc
                        ? const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : SingleChildScrollView(
                            child: Text(
                              _bodyText,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.55,
                                color: AppColors.darkText,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _submitting
                      ? null
                      : () => setState(() => _agreed = !_agreed),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: _agreed,
                            onChanged: _submitting
                                ? null
                                : (v) =>
                                    setState(() => _agreed = v ?? false),
                            activeColor: AppColors.primaryBlue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            (_doc?.acceptanceLabel?.trim().isNotEmpty ?? false)
                                ? _doc!.acceptanceLabel!
                                : 'I have read and agree to the consent above.',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.darkText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _submitting ? null : _onDecline,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          side: const BorderSide(color: AppColors.borderGrey),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Decline',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.darkText,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: (_agreed && !_submitting && !_loadingDoc)
                            ? _onAccept
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              AppColors.primaryBlue.withValues(alpha: 0.4),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Accept',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const String _consentText = '''
Welcome to MEDHA — Attendance Management.

By accepting this consent, you acknowledge and agree to the following:

1. Location Tracking
The app collects your device's GPS location during your shift (while you are checked in) to verify attendance and confirm that you are within the designated work area (geofence). Location is not tracked after you check out.

2. Attendance Data
Your check-in and check-out times, working duration, and geofence status (inside/outside the work area) are recorded for attendance and payroll purposes.

3. Camera / Selfie
A selfie may be captured during check-in for face verification to confirm your identity.

4. Device Information
Basic device details (device ID, platform, OS version) are stored to secure your account and link attendance records to your device.

5. Data Usage
The information collected is used solely for attendance management, reporting, and related HR purposes by your organization. It is stored securely and is not shared with third parties except as required by law.

6. Your Acceptance
By ticking "I Agree" and tapping Accept, you confirm that you have read, understood, and consented to the collection and use of the above data while using MEDHA.

If you do not agree, you will not be able to use the application.
''';
