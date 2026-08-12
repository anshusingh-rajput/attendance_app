import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/sim_info_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import 'forgot_password_screen.dart';
import 'loader_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = false;
  List<SimCardInfo> _availableSims = [];
  bool _loadingSims = false;

  @override
  void initState() {
    super.initState();
    // Strip country-code artifacts (+1, +91, spaces) from ANY value that
    // lands in the field — including values injected by Android autofill or
    // the Google number-hint chip, which bypass _setNumber().
    _usernameController.addListener(_normalizeFieldText);
    WidgetsBinding.instance.addPostFrameCallback((_) => _preloadSims());
  }

  @override
  void dispose() {
    _usernameController.removeListener(_normalizeFieldText);
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _normalizeFieldText() {
    final current = _usernameController.text;
    final normalized = _normalizeNumber(current);
    if (normalized != current) {
      _usernameController.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
    }
  }

  Future<void> _preloadSims() async {
    setState(() => _loadingSims = true);
    try {
      await Permission.phone.request();
      final sims = await SimInfoService.instance.getSimCards();
      if (!mounted) return;
      setState(() {
        _availableSims = sims;
        _loadingSims = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingSims = false);
    }
  }

  Future<void> _openSimPicker() async {
    setState(() => _loadingSims = true);

    // 1) Try Google's Phone Number Hint sheet first (no permission needed,
    //    works on most devices even when the SIM has no stored number).
    try {
      final hinted = await SimInfoService.instance.requestPhoneNumberHint();
      if (!mounted) return;
      if (hinted != null && hinted.trim().isNotEmpty) {
        setState(() => _loadingSims = false);
        _setNumber(hinted);
        return;
      }
    } catch (_) {
      // fall through to the SIM-read flow below
    }

    // 2) Fallback: read numbers directly from the SIM cards.
    try {
      final phoneStatus = await Permission.phone.request();
      if (!mounted) return;
      if (!phoneStatus.isGranted) {
        setState(() => _loadingSims = false);
        _showSimMessage(
          'Phone permission denied. Allow it from app settings.',
        );
        return;
      }

      final sims = await SimInfoService.instance.getSimCards();
      if (!mounted) return;
      setState(() {
        _availableSims = sims;
        _loadingSims = false;
      });

      if (_availableSims.isEmpty) {
        _showSimMessage('No SIM card detected on this device.');
        return;
      }

      final chosen = await _showSimPicker(_availableSims);
      if (!mounted || chosen == null) return;

      if (!chosen.hasNumber) {
        _showSimMessage(
          '${chosen.label}: number is not stored on this SIM, so it '
          'cannot be read automatically. Please type it manually.',
        );
        return;
      }
      _setNumber(chosen.number);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingSims = false);
      _showSimMessage('Could not read SIMs: ${e.toString()}');
    }
  }

  void _showSimMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Normalizes any picked/autofilled value to `91` + 10-digit mobile
  /// (no `+`, no spaces). Handles messy variants seen across devices:
  ///   "+917000175344"  (real phone, E.164)     -> "917000175344"
  ///   "917000175344"   (raw hint)              -> "917000175344"
  ///   "+1917000175344" (emulator US-locale +1) -> "917000175344"
  ///   "07000175344" / "7000175344" (national)  -> "917000175344"
  static String _normalizeNumber(String raw) {
    // Keep digits only — drops +, spaces, and any country-code artifacts.
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    // The real mobile number is always the last 10 digits; prefix 91.
    if (digits.length >= 10) {
      return '91${digits.substring(digits.length - 10)}';
    }
    // Too short to be a full number — return as-is so the validator can flag it.
    return digits;
  }

  void _setNumber(String raw) {
    final num = _normalizeNumber(raw);
    setState(() {
      _usernameController.text = num;
    });
  }

  Future<SimCardInfo?> _showSimPicker(List<SimCardInfo> sims) {
    return showModalBottomSheet<SimCardInfo>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Choose SIM',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkText,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Select the SIM you want to login with',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.subtitleGrey,
                  ),
                ),
                const SizedBox(height: 16),
                for (final s in sims)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      onTap: () => Navigator.pop(ctx, s),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F8FA),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: AppColors.borderGrey),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.primaryBlue
                                    .withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.sim_card_rounded,
                                color: AppColors.primaryBlue,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.label,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.darkText,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    s.hasNumber
                                        ? s.number
                                        : '(Number not available)',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: s.hasNumber
                                          ? AppColors.subtitleGrey
                                          : Colors.redAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: AppColors.subtitleGrey,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleSignIn() {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LoaderScreen(
          username: _normalizeNumber(_usernameController.text),
          password: _passwordController.text,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 48),
                const AppLogo(),
                const SizedBox(height: 32),
                const Text(
                  'Welcome back',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkText,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sign in to your MEDHA account',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.subtitleGrey,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 36),
                const _FieldLabel('Username / Mobile Number'),
                const SizedBox(height: 8),
                _AppTextField(
                  controller: _usernameController,
                  hintText: 'Tap SIM icon to select your number',
                  keyboardType: TextInputType.text,
                  readOnly: true,
                  onTap: _loadingSims ? null : _openSimPicker,
                  prefixIcon: Icons.person_outline_rounded,
                  suffixIcon: IconButton(
                    tooltip: 'Pick from SIM',
                    onPressed: _loadingSims ? null : _openSimPicker,
                    icon: _loadingSims
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primaryBlue,
                            ),
                          )
                        : const Icon(
                            Icons.sim_card_rounded,
                            color: AppColors.primaryBlue,
                          ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your username or pick from SIM';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                const _FieldLabel('Password'),
                const SizedBox(height: 8),
                _AppTextField(
                  controller: _passwordController,
                  hintText: 'Enter your password',
                  obscureText: _obscurePassword,
                  prefixIcon: Icons.lock_outline_rounded,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: AppColors.iconGrey,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    if (value.length < 4) {
                      return 'Password is too short';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _RememberMeRow(
                        value: _rememberMe,
                        onChanged: (v) =>
                            setState(() => _rememberMe = v ?? false),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ForgotPasswordScreen(),
                          ),
                        );
                      },
                      child: const Text(
                        'Forgot Password?',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.primaryBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _handleSignIn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Sign In',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Center(
                  child: Text(
                    'MEDHA v1.0',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.versionGrey,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: AppColors.darkText,
      ),
    );
  }
}

class _AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final bool enabled;
  final bool readOnly;
  final VoidCallback? onTap;

  const _AppTextField({
    required this.controller,
    required this.hintText,
    required this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.enabled = true,
    this.readOnly = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      enabled: enabled,
      readOnly: readOnly,
      onTap: onTap,
      showCursor: !readOnly,
      style: const TextStyle(fontSize: 16, color: AppColors.darkText),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          color: AppColors.hintGrey,
          fontSize: 16,
        ),
        prefixIcon: Icon(prefixIcon, color: AppColors.iconGrey, size: 22),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: enabled ? Colors.white : const Color(0xFFF3F4F6),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderGrey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.primaryBlue, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
        ),
      ),
    );
  }
}

class _RememberMeRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;

  const _RememberMeRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: value,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                side: const BorderSide(
                  color: AppColors.borderGrey,
                  width: 1.6,
                ),
                activeColor: AppColors.primaryBlue,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Remember me',
              style: TextStyle(
                fontSize: 15,
                color: AppColors.darkText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
