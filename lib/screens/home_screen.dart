import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../data/mock_data.dart';
import '../models/user.dart';
import '../services/attendance_service.dart';
import '../services/mobile_service.dart';
import 'checkin_camera_screen.dart';
import 'history_screen.dart';
import 'leaves_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  final String token;
  const HomeScreen({super.key, required this.token});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final _mobile = MobileService();
  User? _user;

  @override
  void initState() {
    super.initState();
    _loadMe();
  }

  Future<void> _loadMe() async {
    final user = await _mobile.fetchMe();
    if (!mounted) return;
    setState(() => _user = user);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      _DashboardTab(user: _user, onRefreshUser: _loadMe),
      const HistoryScreen(),
      const LeavesScreen(),
      ProfileScreen(user: _user, onRefreshUser: _loadMe),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _currentIndex, children: tabs),
      ),
      bottomNavigationBar: _BottomNav(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

class _DashboardTab extends StatefulWidget {
  final User? user;
  final Future<void> Function()? onRefreshUser;
  const _DashboardTab({this.user, this.onRefreshUser});

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  final _attendance = AttendanceService();
  DateTime? _checkInAt;
  DateTime? _lastCheckIn;
  DateTime? _lastCheckOut;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;
  bool _isPunching = false;
  bool _externalCheckedIn = false;

  bool get _isCheckedIn => _checkInAt != null || _externalCheckedIn;

  static const _onDutyStates = {
    'onduty',
    'on_duty',
    'on-duty',
    'working',
    'checkedin',
    'checked_in',
    'checked-in',
    'in',
    'present',
    'active',
  };

  @override
  void initState() {
    super.initState();
    _syncFromUser();
  }

  @override
  void didUpdateWidget(covariant _DashboardTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user?.presenceState != widget.user?.presenceState) {
      _syncFromUser();
    }
  }

  void _syncFromUser() {
    final raw = widget.user?.presenceState;
    if (raw == null) return;
    final normalized = raw.toLowerCase().replaceAll(' ', '');
    final shouldBeIn = _onDutyStates.contains(normalized);
    if (shouldBeIn && _checkInAt == null) {
      setState(() => _externalCheckedIn = true);
    } else if (!shouldBeIn) {
      setState(() => _externalCheckedIn = false);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning,';
    if (h < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  String get _formattedDate {
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final d = DateTime.now();
    return '${weekdays[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _fmtElapsed(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  String _fmtTime(DateTime d) {
    final period = d.hour >= 12 ? 'PM' : 'AM';
    final hh = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
    final mm = d.minute.toString().padLeft(2, '0');
    return '${hh.toString().padLeft(2, '0')}:$mm $period';
  }

  void _openDayMarkSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderGrey,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Day options',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkText,
                ),
              ),
            ),
            const SizedBox(height: 4),
            _DayMarkOption(
              icon: Icons.event_busy_rounded,
              iconColor: const Color(0xFFF59E0B),
              iconBg: const Color(0xFFFEF3C7),
              label: 'Mark today as Absent',
              subtitle: 'Blocks check-in/out for today',
              onTap: () {
                Navigator.pop(ctx);
                _markDay(kind: _DayMarkKind.absent);
              },
            ),
            _DayMarkOption(
              icon: Icons.beach_access_rounded,
              iconColor: AppColors.primaryBlue,
              iconBg: AppColors.primaryBlue.withValues(alpha: 0.12),
              label: 'Mark today as On Leave',
              subtitle: 'Blocks check-in/out for today',
              onTap: () {
                Navigator.pop(ctx);
                _markDay(kind: _DayMarkKind.leave);
              },
            ),
            _DayMarkOption(
              icon: Icons.restart_alt_rounded,
              iconColor: const Color(0xFFEF4444),
              iconBg: const Color(0xFFFEE2E2),
              label: "Clear today's mark",
              subtitle: 'Re-enables check-in/out',
              onTap: () {
                Navigator.pop(ctx);
                _clearDayMark();
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<String?> _promptNote(String title) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Add a note (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  Future<void> _markDay({required _DayMarkKind kind}) async {
    final title =
        kind == _DayMarkKind.absent ? 'Mark Absent' : 'Mark On Leave';
    final note = await _promptNote(title);
    if (note == null || !mounted) return;

    final result = kind == _DayMarkKind.absent
        ? await _attendance.markAbsent(note: note)
        : await _attendance.markLeave(note: note);

    if (!mounted) return;
    if (result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kind == _DayMarkKind.absent
                ? 'Marked as absent for today'
                : 'Marked as on leave for today',
          ),
        ),
      );
      await widget.onRefreshUser?.call();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Failed to mark day')),
      );
    }
  }

  Future<void> _clearDayMark() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear day mark?'),
        content: const Text(
            "This will clear today's absent/leave mark and re-enable check-in."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final result = await _attendance.clearDayMark();
    if (!mounted) return;
    if (result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Today's mark cleared")),
      );
      await widget.onRefreshUser?.call();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Failed to clear mark')),
      );
    }
  }

  Future<void> _onCheckInTap() async {
    if (_isPunching) return;

    setState(() => _isPunching = true);
    final direction =
        _isCheckedIn ? PunchDirection.checkOut : PunchDirection.checkIn;

    bool success = false;

    if (direction == PunchDirection.checkIn) {
      final captured = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => CheckInCameraScreen(direction: direction),
        ),
      );
      if (!mounted) return;
      success = captured == true;
    } else {
      final result = await _attendance.punch(direction: direction);
      if (!mounted) return;
      if (!result.isSuccess) {
        setState(() => _isPunching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Check-out failed'),
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }
      success = true;
    }

    setState(() => _isPunching = false);

    if (!success) {
      return;
    }

    if (_isCheckedIn) {
      _ticker?.cancel();
      setState(() {
        _lastCheckOut = DateTime.now();
        _checkInAt = null;
        _externalCheckedIn = false;
        _elapsed = Duration.zero;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Checked out'), duration: Duration(seconds: 1)),
      );
    } else {
      final now = DateTime.now();
      setState(() {
        _checkInAt = now;
        _lastCheckIn = now;
        _lastCheckOut = null;
        _elapsed = Duration.zero;
      });
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _checkInAt == null) return;
        setState(() {
          _elapsed = DateTime.now().difference(_checkInAt!);
        });
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Checked in'), duration: Duration(seconds: 1)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            greeting: _greeting,
            name: widget.user?.firstName ?? MockUser.firstName,
            initials: widget.user?.initials ?? MockUser.initials,
            onMenuTap: _openDayMarkSheet,
          ),
          const SizedBox(height: 20),
          _DateCard(
            date: _formattedDate,
            isCheckedIn: _isCheckedIn,
            elapsedText: _checkInAt != null ? _fmtElapsed(_elapsed) : null,
            checkInTimeText:
                _lastCheckIn == null ? null : _fmtTime(_lastCheckIn!),
          ),
          const SizedBox(height: 36),
          Center(
            child: _CheckInButton(
              isCheckedIn: _isCheckedIn,
              isLoading: _isPunching,
              onTap: _onCheckInTap,
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              _isPunching
                  ? 'Getting location…'
                  : (_isCheckedIn ? 'Tap to check out' : 'Tap to check in'),
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.subtitleGrey,
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            "Today's Summary",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.darkText,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  icon: Icons.login_rounded,
                  iconColor: const Color(0xFF10B981),
                  iconBg: const Color(0xFFD1FAE5),
                  label: 'Check In',
                  value:
                      _lastCheckIn == null ? '—' : _fmtTime(_lastCheckIn!),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _SummaryCard(
                  icon: Icons.logout_rounded,
                  iconColor: const Color(0xFFEF4444),
                  iconBg: const Color(0xFFFEE2E2),
                  label: 'Check Out',
                  value:
                      _lastCheckOut == null ? '—' : _fmtTime(_lastCheckOut!),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String greeting;
  final String name;
  final String initials;
  final VoidCallback? onMenuTap;

  const _Header({
    required this.greeting,
    required this.name,
    required this.initials,
    this.onMenuTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.subtitleGrey,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkText,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
        if (onMenuTap != null)
          IconButton(
            icon: const Icon(
              Icons.more_vert_rounded,
              color: AppColors.subtitleGrey,
            ),
            onPressed: onMenuTap,
            tooltip: 'Day options',
          ),
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            initials,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryBlue,
            ),
          ),
        ),
      ],
    );
  }
}

enum _DayMarkKind { absent, leave }

class _DayMarkOption extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _DayMarkOption({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.subtitleGrey,
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
    );
  }
}

class _DateCard extends StatelessWidget {
  final String date;
  final bool isCheckedIn;
  final String? elapsedText;
  final String? checkInTimeText;

  const _DateCard({
    required this.date,
    required this.isCheckedIn,
    required this.elapsedText,
    required this.checkInTimeText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  date,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isCheckedIn ? 'Active' : 'No Check-in',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (isCheckedIn && elapsedText != null) ...[
            Text(
              'Time Elapsed',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              elapsedText!,
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.1,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 10),
            if (checkInTimeText != null)
              Text(
                'Checked in at $checkInTimeText',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
          ] else if (isCheckedIn) ...[
            const Text(
              'Currently checked in',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap below to check out',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ] else ...[
            const Text(
              'Not checked in yet',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Start your workday by checking in',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CheckInButton extends StatelessWidget {
  final bool isCheckedIn;
  final bool isLoading;
  final VoidCallback onTap;

  const _CheckInButton({
    required this.isCheckedIn,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final mainColor = isCheckedIn
        ? const Color(0xFFEF4444)
        : AppColors.primaryBlue;

    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: mainColor.withValues(alpha: 0.06),
            ),
          ),
          Container(
            width: 190,
            height: 190,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: mainColor.withValues(alpha: 0.12),
            ),
          ),
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: isLoading ? null : onTap,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mainColor,
                  boxShadow: [
                    BoxShadow(
                      color: mainColor.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: isLoading
                    ? const Center(
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isCheckedIn
                                ? Icons.logout_rounded
                                : Icons.login_rounded,
                            color: Colors.white,
                            size: 36,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isCheckedIn ? 'Check Out' : 'Check In',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String value;

  const _SummaryCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderGrey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.darkText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.subtitleGrey,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final items = [
      (icon: Icons.home_rounded, label: 'Home'),
      (icon: Icons.calendar_today_outlined, label: 'History'),
      (icon: Icons.event_note_outlined, label: 'Leaves'),
      (icon: Icons.person_outline_rounded, label: 'Profile'),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.borderGrey)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: List.generate(items.length, (i) {
              final active = i == currentIndex;
              return Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onTap(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.primaryBlue.withValues(alpha: 0.10)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          items[i].icon,
                          size: 24,
                          color: active
                              ? AppColors.primaryBlue
                              : AppColors.subtitleGrey,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          items[i].label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: active
                                ? AppColors.primaryBlue
                                : AppColors.subtitleGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
