import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/attendance_day.dart';
import '../services/attendance_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _attendance = AttendanceService();
  List<AttendanceDay>? _days;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, 1);
    final to = DateTime(now.year, now.month + 1, 0);

    final result = await _attendance.fetchSummary(from: from, to: to);
    if (!mounted) return;
    setState(() {
      _days = result;
      _loading = false;
    });
  }

  String _fmtTime(DateTime? t) {
    if (t == null) return '—';
    final h = t.hour;
    final m = t.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final hh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '${hh.toString().padLeft(2, '0')}:$m $period';
  }

  String _fmtDuration(Duration d) {
    if (d.inMinutes == 0) return '—';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h == 0) return '${m}m';
    return '${h}h ${m}m';
  }

  String _fmtTotalHours(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return '${h}h ${m}m';
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _fmtMonthYear(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

  ({Color bg, Color fg, String label}) _statusStyle(AttendanceDay day) {
    final status = day.status;
    final s = status.toLowerCase();

    // If this is today and user has checked in but not checked out,
    // override the badge to "In Progress" — they still have time to check out.
    final now = DateTime.now();
    final isToday = day.date.year == now.year &&
        day.date.month == now.month &&
        day.date.day == now.day;
    final stillIn = day.firstInAt != null && day.lastOutAt == null;
    if (isToday && stillIn) {
      return (
        bg: const Color(0xFFDBEAFE),
        fg: const Color(0xFF1E40AF),
        label: 'In Progress',
      );
    }

    if (day.isPresent || s == 'present') {
      return (bg: const Color(0xFFD1FAE5), fg: const Color(0xFF065F46), label: 'Present');
    }
    if (s.contains('absent')) {
      return (bg: const Color(0xFFFEE2E2), fg: const Color(0xFF991B1B), label: 'Absent');
    }
    if (s.contains('leave')) {
      return (bg: const Color(0xFFDBEAFE), fg: const Color(0xFF1E40AF), label: 'Leave');
    }
    if (s == 'missingout' || s.contains('missing')) {
      return (bg: const Color(0xFFFEF3C7), fg: const Color(0xFF92400E), label: 'Missing Out');
    }
    if (s == 'timeshortage' || s.contains('shortage')) {
      return (bg: const Color(0xFFFEF3C7), fg: const Color(0xFF92400E), label: 'Time Shortage');
    }
    if (s == 'incomplete') {
      return (bg: const Color(0xFFE5E7EB), fg: const Color(0xFF374151), label: 'Incomplete');
    }
    return (bg: const Color(0xFFE5E7EB), fg: const Color(0xFF374151), label: status);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthLabel = _fmtMonthYear(now);
    final days = _days ?? const <AttendanceDay>[];
    final totals = AttendanceTotals.fromDays(days);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Text(
            'Attendance History',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.darkText,
            ),
          ),
        ),
        const Divider(height: 1, color: AppColors.borderGrey),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primaryBlue,
            onRefresh: _loadSummary,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.borderGrey),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                monthLabel,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.darkText,
                                ),
                              ),
                            ),
                            if (_loading)
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppColors.primaryBlue,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _Stat(
                                value: '${totals.present}',
                                label: 'Days Present',
                                color: const Color(0xFF10B981),
                              ),
                            ),
                            Expanded(
                              child: _Stat(
                                value: _fmtTotalHours(totals.totalHours),
                                label: 'Total Hours',
                                color: AppColors.primaryBlue,
                              ),
                            ),
                            Expanded(
                              child: _Stat(
                                value: '${totals.totalDays} days',
                                label: 'This Month',
                                color: const Color(0xFFF59E0B),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      monthLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.subtitleGrey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (!_loading && days.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.borderGrey),
                      ),
                      child: const Center(
                        child: Text(
                          'No attendance records this month',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.subtitleGrey,
                          ),
                        ),
                      ),
                    ),
                  for (final entry in days.reversed) ...[
                    _AttendanceCard(
                      dateLabel: _fmtDate(entry.date),
                      statusStyle: _statusStyle(entry),
                      checkIn: _fmtTime(entry.firstInAt),
                      checkOut: _fmtTime(entry.lastOutAt),
                      hours: _fmtDuration(entry.duration),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _Stat({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.subtitleGrey,
          ),
        ),
      ],
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  final String dateLabel;
  final ({Color bg, Color fg, String label}) statusStyle;
  final String checkIn;
  final String checkOut;
  final String hours;

  const _AttendanceCard({
    required this.dateLabel,
    required this.statusStyle,
    required this.checkIn,
    required this.checkOut,
    required this.hours,
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
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  dateLabel,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkText,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusStyle.bg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusStyle.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusStyle.fg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.borderGrey),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _TimeCol(
                  icon: Icons.login_rounded,
                  iconColor: const Color(0xFF10B981),
                  value: checkIn,
                  label: 'Check In',
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: AppColors.borderGrey,
              ),
              Expanded(
                child: _TimeCol(
                  icon: Icons.logout_rounded,
                  iconColor: const Color(0xFFEF4444),
                  value: checkOut,
                  label: 'Check Out',
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: AppColors.borderGrey,
              ),
              Expanded(
                child: _TimeCol(
                  icon: Icons.access_time_rounded,
                  iconColor: AppColors.primaryBlue,
                  value: hours,
                  label: 'Hours',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimeCol extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _TimeCol({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.darkText,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.subtitleGrey,
          ),
        ),
      ],
    );
  }
}
