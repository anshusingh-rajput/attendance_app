import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../data/mock_data.dart';
import '../models/attendance_summary.dart' as model;
import '../services/attendance_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _attendance = AttendanceService();
  model.AttendanceSummary? _summary;
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
      _summary = result;
      _loading = false;
    });
  }

  String _fmtTime(TimeOfDay? t) {
    if (t == null) return '—';
    final h = t.hour;
    final m = t.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final hh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '${hh.toString().padLeft(2, '0')}:$m $period';
  }

  String _fmtDuration(Duration? d) {
    if (d == null) return '—';
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

  @override
  Widget build(BuildContext context) {
    final entries = mockAttendance;
    final now = DateTime.now();
    final monthLabel = _fmtMonthYear(now);

    final int daysPresent =
        _summary?.present ?? mockAttendanceSummary.daysPresent;
    final Duration totalHours =
        _summary?.totalHours ?? mockAttendanceSummary.totalHours;
    final int thisMonth = _summary?.totalDays ??
        mockAttendanceSummary.totalDaysInMonth;

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
                                value: '$daysPresent',
                                label: 'Days Present',
                                color: const Color(0xFF10B981),
                              ),
                            ),
                            Expanded(
                              child: _Stat(
                                value: _fmtTotalHours(totalHours),
                                label: 'Total Hours',
                                color: AppColors.primaryBlue,
                              ),
                            ),
                            Expanded(
                              child: _Stat(
                                value: '$thisMonth days',
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
                for (final entry in entries) ...[
                  _AttendanceCard(
                    dateLabel: _fmtDate(entry.date),
                    status: entry.status,
                    checkIn: _fmtTime(entry.checkIn),
                    checkOut: _fmtTime(entry.checkOut),
                    hours: _fmtDuration(entry.hours),
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
  final String status;
  final String checkIn;
  final String checkOut;
  final String hours;

  const _AttendanceCard({
    required this.dateLabel,
    required this.status,
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
                  color: const Color(0xFFD1FAE5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF065F46),
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
                  iconColor: Color(0xFF10B981),
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
                  iconColor: Color(0xFFEF4444),
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
