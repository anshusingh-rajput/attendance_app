class AttendanceSummary {
  final int present;
  final int absent;
  final int leave;
  final int incomplete;
  final Duration totalHours;

  const AttendanceSummary({
    this.present = 0,
    this.absent = 0,
    this.leave = 0,
    this.incomplete = 0,
    this.totalHours = Duration.zero,
  });

  int get totalDays => present + absent + leave + incomplete;

  factory AttendanceSummary.fromJson(Map<String, dynamic> json) {
    return AttendanceSummary(
      present: _parseInt(
          json, ['present', 'daysPresent', 'presentDays', 'presentCount']),
      absent: _parseInt(
          json, ['absent', 'daysAbsent', 'absentDays', 'absentCount']),
      leave: _parseInt(
          json, ['leave', 'leaves', 'daysLeave', 'leaveDays', 'leaveCount']),
      incomplete: _parseInt(json, [
        'incomplete',
        'daysIncomplete',
        'incompleteDays',
        'incompleteCount',
        'partial',
      ]),
      totalHours: _parseDuration(json, [
        'totalHours',
        'totalTime',
        'totalDuration',
        'workedHours',
        'workedDuration',
        'totalMinutes',
        'workedMinutes',
        'totalSeconds',
        'workedSeconds',
      ]),
    );
  }

  static int _parseInt(Map<String, dynamic> json, List<String> keys) {
    for (final k in keys) {
      final v = json[k];
      if (v is num) return v.toInt();
      if (v is String) {
        final n = int.tryParse(v);
        if (n != null) return n;
      }
    }
    return 0;
  }

  static Duration _parseDuration(
      Map<String, dynamic> json, List<String> keys) {
    for (final k in keys) {
      final v = json[k];
      if (v == null) continue;
      final lowerKey = k.toLowerCase();

      if (v is num) {
        final n = v.toDouble();
        if (lowerKey.contains('second')) {
          return Duration(seconds: n.toInt());
        }
        if (lowerKey.contains('minute')) {
          return Duration(minutes: n.toInt());
        }
        // Default: treat as hours (possibly fractional)
        final totalMinutes = (n * 60).round();
        return Duration(minutes: totalMinutes);
      }

      if (v is String && v.isNotEmpty) {
        final d = _parseDurationString(v);
        if (d != null) return d;
      }
    }
    return Duration.zero;
  }

  static Duration? _parseDurationString(String s) {
    // Format: "HH:MM:SS" or "HH:MM"
    final colonParts = s.split(':');
    if (colonParts.length == 3 || colonParts.length == 2) {
      final h = int.tryParse(colonParts[0]);
      final m = int.tryParse(colonParts[1]);
      final sec = colonParts.length == 3 ? int.tryParse(colonParts[2]) : 0;
      if (h != null && m != null) {
        return Duration(hours: h, minutes: m, seconds: sec ?? 0);
      }
    }
    // Format: "Xh Ym"
    final hMatch = RegExp(r'(\d+)\s*h').firstMatch(s);
    final mMatch = RegExp(r'(\d+)\s*m').firstMatch(s);
    if (hMatch != null || mMatch != null) {
      final h = hMatch != null ? int.parse(hMatch.group(1)!) : 0;
      final m = mMatch != null ? int.parse(mMatch.group(1)!) : 0;
      return Duration(hours: h, minutes: m);
    }
    // Plain number → treat as minutes (loose default)
    final n = double.tryParse(s);
    if (n != null) return Duration(minutes: n.toInt());
    return null;
  }
}
