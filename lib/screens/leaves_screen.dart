import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../data/mock_data.dart';
import 'apply_leave_screen.dart';

class LeavesScreen extends StatefulWidget {
  const LeavesScreen({super.key});

  @override
  State<LeavesScreen> createState() => _LeavesScreenState();
}

class _LeavesScreenState extends State<LeavesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _changeMonth(int delta) {
    setState(() {
      _currentMonth = DateTime(
        _currentMonth.year,
        _currentMonth.month + delta,
      );
    });
  }

  void _openApplyLeave() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ApplyLeaveScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Leaves',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.darkText,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: () => setState(() {}),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              labelColor: AppColors.primaryBlue,
              unselectedLabelColor: AppColors.subtitleGrey,
              indicatorColor: AppColors.primaryBlue,
              indicatorWeight: 2.5,
              labelStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'My Leaves'),
              ],
            ),
            const Divider(height: 1, color: AppColors.borderGrey),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _OverviewTab(
                    currentMonth: _currentMonth,
                    onChangeMonth: _changeMonth,
                  ),
                  _MyLeavesTab(onApply: _openApplyLeave),
                ],
              ),
            ),
          ],
        ),
        Positioned(
          right: 20,
          bottom: 20,
          child: FloatingActionButton.extended(
            onPressed: _openApplyLeave,
            backgroundColor: AppColors.primaryBlue,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: const Text(
              'Apply',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final DateTime currentMonth;
  final void Function(int delta) onChangeMonth;

  const _OverviewTab({
    required this.currentMonth,
    required this.onChangeMonth,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Leave balances',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.darkText,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (int i = 0; i < mockLeaveBalances.length; i++) ...[
                Expanded(
                  child: _LeaveBalanceCard(balance: mockLeaveBalances[i]),
                ),
                if (i < mockLeaveBalances.length - 1)
                  const SizedBox(width: 12),
              ],
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Calendar',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.darkText,
            ),
          ),
          const SizedBox(height: 12),
          _Calendar(
            month: currentMonth,
            onPrev: () => onChangeMonth(-1),
            onNext: () => onChangeMonth(1),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderGrey),
            ),
            child: const Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _LegendDot(color: Color(0xFFEF4444), label: 'Holiday'),
                _LegendDot(color: Color(0xFFF59E0B), label: 'Optional'),
                _LegendDot(color: Color(0xFF10B981), label: 'Approved'),
                _LegendDot(color: Color(0xFFF59E0B), label: 'Pending'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Upcoming holidays',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.darkText,
            ),
          ),
          const SizedBox(height: 12),
          for (final h in mockHolidays) ...[
            _HolidayCard(holiday: h),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _LeaveBalanceCard extends StatelessWidget {
  final LeaveBalance balance;
  const _LeaveBalanceCard({required this.balance});

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
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: balance.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  balance.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.subtitleGrey,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${balance.remaining}',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: balance.color,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'of ${balance.total} days',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.subtitleGrey,
            ),
          ),
        ],
      ),
    );
  }
}

class _Calendar extends StatelessWidget {
  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _Calendar({
    required this.month,
    required this.onPrev,
    required this.onNext,
  });

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  Holiday? _holidayFor(DateTime d) {
    for (final h in mockHolidays) {
      if (h.date.year == d.year &&
          h.date.month == d.month &&
          h.date.day == d.day) {
        return h;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final firstDay = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingEmpty = firstDay.weekday % 7;

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
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: onPrev,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_monthNames[month.month - 1]} ${month.year}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkText,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: onNext,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: const [
              _DayHeader('S'),
              _DayHeader('M'),
              _DayHeader('T'),
              _DayHeader('W'),
              _DayHeader('T'),
              _DayHeader('F'),
              _DayHeader('S'),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1,
            ),
            itemCount: leadingEmpty + daysInMonth,
            itemBuilder: (context, i) {
              if (i < leadingEmpty) return const SizedBox.shrink();
              final day = i - leadingEmpty + 1;
              final date = DateTime(month.year, month.month, day);
              final isToday = date.year == today.year &&
                  date.month == today.month &&
                  date.day == today.day;
              final isPast = date.isBefore(
                DateTime(today.year, today.month, today.day),
              );
              final holiday = _holidayFor(date);
              final isSunday = date.weekday == DateTime.sunday;
              final isSaturday = date.weekday == DateTime.saturday;
              final isWeekend = isSunday || isSaturday;

              Color? bg;
              Color textColor = AppColors.darkText;
              Color? dotColor;

              if (holiday != null) {
                bg = holiday.isOptional
                    ? const Color(0xFFFEF3C7)
                    : const Color(0xFFFEE2E2);
                textColor = holiday.isOptional
                    ? const Color(0xFFD97706)
                    : const Color(0xFFEF4444);
                dotColor = holiday.isOptional
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFFEF4444);
              } else if (isPast || isWeekend) {
                textColor = AppColors.hintGrey;
              }

              return Padding(
                padding: const EdgeInsets.all(2),
                child: Container(
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(10),
                    border: isToday
                        ? Border.all(
                            color: AppColors.primaryBlue,
                            width: 1.5,
                          )
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$day',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isToday
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isToday
                              ? AppColors.primaryBlue
                              : textColor,
                        ),
                      ),
                      if (dotColor != null) ...[
                        const SizedBox(height: 2),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: dotColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  final String label;
  const _DayHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.subtitleGrey,
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.darkText,
          ),
        ),
      ],
    );
  }
}

class _HolidayCard extends StatelessWidget {
  final Holiday holiday;
  const _HolidayCard({required this.holiday});

  static const _monthAbbr = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final monthLabel = _monthAbbr[holiday.date.month - 1];
    final weekday = _weekdays[holiday.date.weekday - 1];
    final tileBg = holiday.isOptional
        ? const Color(0xFFFEF3C7)
        : AppColors.primaryBlue.withValues(alpha: 0.10);
    final tileText = holiday.isOptional
        ? const Color(0xFFD97706)
        : AppColors.primaryBlue;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderGrey),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: tileBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  monthLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: tileText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${holiday.date.day}',
                  style: TextStyle(
                    fontSize: 20,
                    color: tileText,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  holiday.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  weekday,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.subtitleGrey,
                  ),
                ),
              ],
            ),
          ),
          if (holiday.isOptional)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Optional',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFD97706),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MyLeavesTab extends StatelessWidget {
  final VoidCallback onApply;
  const _MyLeavesTab({required this.onApply});

  @override
  Widget build(BuildContext context) {
    if (mockLeaveRequests.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.event_available_outlined,
                  size: 40,
                  color: AppColors.subtitleGrey,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'No leave requests yet',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.subtitleGrey,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tap Apply to submit your first request',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.subtitleGrey,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      itemCount: mockLeaveRequests.length,
      itemBuilder: (context, i) {
        final r = mockLeaveRequests[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderGrey),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.leaveType,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkText,
                  ),
                ),
                Text(
                  '${r.from.toString().split(' ').first} - ${r.to.toString().split(' ').first}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.subtitleGrey,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
