import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_theme.dart';
import '../data/mock_data.dart';
import '../models/user.dart';
import '../services/attendance_service.dart';
import '../services/auth_service.dart';
import '../services/mobile_service.dart';
import 'forgot_password_screen.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final User? user;
  final Future<void> Function()? onRefreshUser;
  const ProfileScreen({super.key, this.user, this.onRefreshUser});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth = AuthService();
  final _attendance = AttendanceService();
  final _picker = ImagePicker();
  final _mobile = MobileService();
  String? _photoUrlOverride;
  bool _uploadingPhoto = false;
  String? _firstNameOverride;
  String? _lastNameOverride;
  String? _phoneOverride;

  String get _displayName {
    if (_firstNameOverride != null || _lastNameOverride != null) {
      return '${_firstNameOverride ?? ''} ${_lastNameOverride ?? ''}'.trim();
    }
    return widget.user?.displayName ?? MockUser.fullName;
  }

  String get _employeeCode =>
      widget.user?.employeeCode ?? MockUser.employeeId;

  String? get _email {
    final e = widget.user?.email?.trim();
    if (e == null || e.isEmpty) return null;
    return e;
  }

  String get _phone => _phoneOverride ?? MockUser.phone;

  String? get _photoUrl => _photoUrlOverride ?? widget.user?.profilePhotoUrl;

  String get _initials {
    if (_firstNameOverride != null && _firstNameOverride!.isNotEmpty) {
      final l = (_lastNameOverride ?? '').isNotEmpty
          ? _lastNameOverride![0]
          : '';
      return '${_firstNameOverride![0]}$l'.toUpperCase();
    }
    return widget.user?.initials ?? MockUser.initials;
  }

  Future<void> _logout() async {
    // Blocking loader while we auto check-out (if needed) and sign out.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
        ),
      ),
    );

    // If the user is still checked in, perform an automatic check-out first.
    try {
      if (await _attendance.isCheckedInToday()) {
        await _attendance.punch(direction: PunchDirection.checkOut);
      }
    } catch (_) {
      // Don't block sign-out if the auto check-out fails (e.g. no network
      // or outside geofence) — proceed to log the user out regardless.
    }

    await _auth.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _changeProfilePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderGrey,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded,
                  color: AppColors.primaryBlue),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.primaryBlue),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;

    // CAMERA permission is declared in the manifest, so it must be granted at
    // runtime before launching the camera.
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (!mounted) return;
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera permission denied. Allow it in settings.'),
          ),
        );
        return;
      }
    }

    XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1080,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open ${source.name}: $e')),
      );
      return;
    }
    if (picked == null) return;

    setState(() => _uploadingPhoto = true);
    final result = await _mobile.updateMe(profilePhoto: File(picked.path));
    if (!mounted) return;
    setState(() => _uploadingPhoto = false);

    if (result.isSuccess) {
      final url = result.user?.profilePhotoUrl;
      if (url != null && url.isNotEmpty) {
        // Cache-bust so the new image shows immediately (same URL otherwise
        // returns the cached old image).
        final bust = DateTime.now().millisecondsSinceEpoch;
        setState(() {
          _photoUrlOverride =
              url.contains('?') ? '$url&t=$bust' : '$url?t=$bust';
        });
      }
      await widget.onRefreshUser?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile picture updated')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Failed to update photo')),
      );
    }
  }

  void _openEditProfile() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) {
        final name = (widget.user?.displayName ?? MockUser.fullName).trim();
        final parts = name.split(RegExp(r'\s+'));
        final initialFirst = _firstNameOverride ??
            (parts.isNotEmpty ? parts.first : '');
        final initialLast = _lastNameOverride ??
            (parts.length > 1 ? parts.sublist(1).join(' ') : '');
        final initialPhone = widget.user?.mobileNo ?? _phone;
        return _EditProfileSheet(
          firstName: initialFirst,
          lastName: initialLast,
          email: _email ?? '',
          phone: initialPhone,
          onSave: (f, l, p) async {
            final result = await MobileService().updateMe(
              firstName: f,
              lastName: l,
              mobileNo: p,
              displayName: '$f $l'.trim(),
            );
            if (!mounted) return result.error;
            if (result.isSuccess) {
              setState(() {
                _firstNameOverride = f;
                _lastNameOverride = l;
                _phoneOverride = p;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Profile updated')),
              );
              await widget.onRefreshUser?.call();
            }
            return result.error;
          },
        );
      },
    );
  }

  Future<void> _openChangePassword() async {
    final username = await _auth.getUsername();
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(
          prefillUsername: username,
          isChangePassword: true,
        ),
      ),
    );
  }

  void _confirmSignOut() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _logout();
            },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Text(
            'Profile',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.darkText,
            ),
          ),
        ),
        const Divider(height: 1, color: AppColors.borderGrey),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: _ProfileAvatar(
                    photoUrl: _photoUrl,
                    initials: _initials,
                    uploading: _uploadingPhoto,
                    onTap: _uploadingPhoto ? null : _changeProfilePhoto,
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Text(
                    _displayName,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.darkText,
                    ),
                  ),
                ),
                if (widget.user?.departmentName != null &&
                    widget.user!.departmentName!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      widget.user!.departmentName!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.subtitleGrey,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                _InfoCard(
                  rows: [
                    _InfoRow(
                      icon: Icons.badge_outlined,
                      label: 'Employee ID',
                      value: _employeeCode,
                    ),
                    if (_email != null)
                      _InfoRow(
                        icon: Icons.mail_outline_rounded,
                        label: 'Email',
                        value: _email!,
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                _ActionList(
                  items: [
                    _ActionItem(
                      icon: Icons.edit_outlined,
                      label: 'Edit Profile',
                      onTap: _openEditProfile,
                    ),
                    _ActionItem(
                      icon: Icons.lock_outline_rounded,
                      label: 'Change Password',
                      onTap: _openChangePassword,
                    ),
                    _ActionItem(
                      icon: Icons.logout_rounded,
                      label: 'Sign Out',
                      isDestructive: true,
                      onTap: _confirmSignOut,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final String? photoUrl;
  final String initials;
  final bool uploading;
  final VoidCallback? onTap;

  const _ProfileAvatar({
    required this.photoUrl,
    required this.initials,
    this.uploading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 118,
        height: 118,
        child: Stack(
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      initials,
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                    if (hasPhoto)
                      Image.network(
                        photoUrl!,
                        fit: BoxFit.cover,
                        width: 110,
                        height: 110,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    if (uploading)
                      Container(
                        width: 110,
                        height: 110,
                        color: Colors.black.withValues(alpha: 0.35),
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Camera badge to signal the avatar is editable.
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  color: Colors.white,
                  size: 17,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
}

class _InfoCard extends StatelessWidget {
  final List<_InfoRow> rows;
  const _InfoCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderGrey),
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              child: Row(
                children: [
                  Icon(
                    rows[i].icon,
                    color: AppColors.subtitleGrey,
                    size: 22,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rows[i].label,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.subtitleGrey,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          rows[i].value,
                          style: const TextStyle(
                            fontSize: 16,
                            color: AppColors.darkText,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (i < rows.length - 1)
              const Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: AppColors.borderGrey,
              ),
          ],
        ],
      ),
    );
  }
}

class _ActionItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  const _ActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });
}

class _ActionList extends StatelessWidget {
  final List<_ActionItem> items;
  const _ActionList({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderGrey),
      ),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            InkWell(
              onTap: items[i].onTap,
              borderRadius: BorderRadius.vertical(
                top: i == 0 ? const Radius.circular(14) : Radius.zero,
                bottom: i == items.length - 1
                    ? const Radius.circular(14)
                    : Radius.zero,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: items[i].isDestructive
                            ? const Color(0xFFFEE2E2)
                            : AppColors.primaryBlue.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        items[i].icon,
                        size: 20,
                        color: items[i].isDestructive
                            ? const Color(0xFFEF4444)
                            : AppColors.primaryBlue,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        items[i].label,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: items[i].isDestructive
                              ? const Color(0xFFEF4444)
                              : AppColors.darkText,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: items[i].isDestructive
                          ? const Color(0xFFEF4444)
                          : AppColors.subtitleGrey,
                    ),
                  ],
                ),
              ),
            ),
            if (i < items.length - 1)
              const Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: AppColors.borderGrey,
              ),
          ],
        ],
      ),
    );
  }
}

class _EditProfileSheet extends StatefulWidget {
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final Future<String?> Function(String firstName, String lastName, String phone)
      onSave;

  const _EditProfileSheet({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.onSave,
  });

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _firstNameCtrl = TextEditingController(text: widget.firstName);
    _lastNameCtrl = TextEditingController(text: widget.lastName);
    _emailCtrl = TextEditingController(text: widget.email);
    _phoneCtrl = TextEditingController(text: widget.phone);
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Edit Profile',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.darkText,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _LabeledField(
              label: 'First Name',
              controller: _firstNameCtrl,
            ),
            const SizedBox(height: 14),
            _LabeledField(
              label: 'Last Name',
              controller: _lastNameCtrl,
            ),
            const SizedBox(height: 14),
            _LabeledField(
              label: 'Email',
              controller: _emailCtrl,
              enabled: false,
            ),
            const SizedBox(height: 14),
            _LabeledField(
              label: 'Phone',
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              enabled: false,
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _saving
                    ? null
                    : () async {
                        setState(() => _saving = true);
                        final error = await widget.onSave(
                          _firstNameCtrl.text.trim(),
                          _lastNameCtrl.text.trim(),
                          _phoneCtrl.text.trim(),
                        );
                        if (!mounted) return;
                        if (error == null) {
                          Navigator.pop(context);
                        } else {
                          setState(() => _saving = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(error)),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Save Changes',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool enabled;
  final TextInputType? keyboardType;

  const _LabeledField({
    required this.label,
    required this.controller,
    this.enabled = true,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: enabled ? Colors.white : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderGrey),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            fontSize: 13,
            color: AppColors.subtitleGrey,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
        ),
        style: const TextStyle(
          fontSize: 16,
          color: AppColors.darkText,
        ),
      ),
    );
  }
}
