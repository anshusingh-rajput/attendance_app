class AttendanceDay {
  final DateTime date;
  final String status;
  final DateTime? firstInAt;
  final DateTime? lastOutAt;
  final int minutesWorked;
  final bool isPresent;

  const AttendanceDay({
    required this.date,
    required this.status,
    this.firstInAt,
    this.lastOutAt,
    this.minutesWorked = 0,
    this.isPresent = false,
  });

  Duration get duration => Duration(minutes: minutesWorked);

  factory AttendanceDay.fromJson(Map<String, dynamic> json) {
    return AttendanceDay(
      date: _parseDate(json['date']) ?? DateTime.now(),
      status: (json['status'] as String?) ?? 'Unknown',
      firstInAt: _parseDateTime(json['firstInAt']),
      lastOutAt: _parseDateTime(json['lastOutAt']),
      minutesWorked: (json['minutesWorked'] as num?)?.toInt() ?? 0,
      isPresent: (json['isPresent'] as bool?) ?? false,
    );
  }

  static DateTime? _parseDate(dynamic v) {
    if (v is String && v.isNotEmpty) {
      try {
        return DateTime.parse(v);
      } catch (_) {}
    }
    return null;
  }

  static DateTime? _parseDateTime(dynamic v) {
    if (v is String && v.isNotEmpty) {
      try {
        // Backend stores time as wall-clock IST but appends "Z" (UTC marker).
        // Strip Z and parse as local to avoid double timezone conversion.
        final cleaned =
            v.endsWith('Z') ? v.substring(0, v.length - 1) : v;
        return DateTime.parse(cleaned);
      } catch (_) {}
    }
    return null;
  }
}

class AttendanceTotals {
  final int present;
  final int absent;
  final int leave;
  final int incomplete;
  final int totalDays;
  final Duration totalHours;

  const AttendanceTotals({
    this.present = 0,
    this.absent = 0,
    this.leave = 0,
    this.incomplete = 0,
    this.totalDays = 0,
    this.totalHours = Duration.zero,
  });

  factory AttendanceTotals.fromDays(List<AttendanceDay> days) {
    int present = 0, absent = 0, leave = 0, incomplete = 0;
    int totalMinutes = 0;
    for (final d in days) {
      totalMinutes += d.minutesWorked;
      final s = d.status.toLowerCase();
      if (d.isPresent || s == 'present') {
        present++;
      } else if (s.contains('absent')) {
        absent++;
      } else if (s.contains('leave')) {
        leave++;
      } else {
        incomplete++;
      }
    }
    return AttendanceTotals(
      present: present,
      absent: absent,
      leave: leave,
      incomplete: incomplete,
      totalDays: days.length,
      totalHours: Duration(minutes: totalMinutes),
    );
  }
}
