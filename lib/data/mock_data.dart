import 'package:flutter/material.dart';

class MockUser {
  static const String firstName = 'Anshu';
  static const String lastName = 'Singh';
  static const String employeeId = 'EPI001';
  static const String email = 'anshusinghrajput739080@gmail.com';
  static const String phone = '';

  static String get fullName => '$firstName $lastName';
  static String get initials => '${firstName[0]}${lastName[0]}';
}

class LeaveBalance {
  final String name;
  final int remaining;
  final int total;
  final Color color;

  const LeaveBalance({
    required this.name,
    required this.remaining,
    required this.total,
    required this.color,
  });
}

const mockLeaveBalances = <LeaveBalance>[
  LeaveBalance(
    name: 'Casual Leave',
    remaining: 12,
    total: 12,
    color: Color(0xFF10B981),
  ),
  LeaveBalance(
    name: 'Earned Leave',
    remaining: 15,
    total: 15,
    color: Color(0xFF2563EB),
  ),
];

const leaveTypes = <String>[
  'Casual Leave',
  'Earned Leave',
  'Loss of Pay',
  'Sick Leave',
];

class Holiday {
  final DateTime date;
  final String name;
  final bool isOptional;

  const Holiday({
    required this.date,
    required this.name,
    this.isOptional = false,
  });
}

final mockHolidays = <Holiday>[
  Holiday(date: DateTime(2026, 5, 1), name: 'Labour Day'),
  Holiday(date: DateTime(2026, 5, 27), name: 'Eid-ul-Adha (Bakrid)'),
  Holiday(date: DateTime(2026, 6, 25), name: 'Muharram'),
  Holiday(date: DateTime(2026, 8, 4), name: 'Janmashtami', isOptional: true),
  Holiday(date: DateTime(2026, 8, 15), name: 'Independence Day'),
  Holiday(date: DateTime(2026, 8, 26), name: 'Eid-e-Milad'),
  Holiday(date: DateTime(2026, 8, 28), name: 'Raksha Bandhan'),
];

class AttendanceEntry {
  final DateTime date;
  final TimeOfDay? checkIn;
  final TimeOfDay? checkOut;
  final Duration? hours;
  final String status;

  const AttendanceEntry({
    required this.date,
    this.checkIn,
    this.checkOut,
    this.hours,
    this.status = 'Present',
  });
}

final mockAttendance = <AttendanceEntry>[
  AttendanceEntry(
    date: DateTime(2026, 5, 26),
    checkIn: const TimeOfDay(hour: 10, minute: 24),
    hours: const Duration(minutes: 48),
  ),
  AttendanceEntry(
    date: DateTime(2026, 5, 25),
    checkIn: const TimeOfDay(hour: 9, minute: 58),
    checkOut: const TimeOfDay(hour: 18, minute: 34),
    hours: const Duration(hours: 8, minutes: 36),
  ),
  AttendanceEntry(
    date: DateTime(2026, 5, 22),
    checkIn: const TimeOfDay(hour: 9, minute: 45),
    checkOut: const TimeOfDay(hour: 18, minute: 10),
    hours: const Duration(hours: 8, minutes: 25),
  ),
  AttendanceEntry(
    date: DateTime(2026, 5, 21),
    checkIn: const TimeOfDay(hour: 10, minute: 5),
    checkOut: const TimeOfDay(hour: 19, minute: 0),
    hours: const Duration(hours: 8, minutes: 55),
  ),
  AttendanceEntry(
    date: DateTime(2026, 5, 20),
    checkIn: const TimeOfDay(hour: 9, minute: 30),
    checkOut: const TimeOfDay(hour: 18, minute: 15),
    hours: const Duration(hours: 8, minutes: 45),
  ),
];

class AttendanceSummary {
  final int daysPresent;
  final Duration totalHours;
  final int totalDaysInMonth;

  const AttendanceSummary({
    required this.daysPresent,
    required this.totalHours,
    required this.totalDaysInMonth,
  });
}

const mockAttendanceSummary = AttendanceSummary(
  daysPresent: 9,
  totalHours: Duration(hours: 61, minutes: 10),
  totalDaysInMonth: 9,
);

class LeaveRequest {
  final String leaveType;
  final DateTime from;
  final DateTime to;
  final String reason;
  final String status;

  const LeaveRequest({
    required this.leaveType,
    required this.from,
    required this.to,
    required this.reason,
    this.status = 'Pending',
  });
}

final mockLeaveRequests = <LeaveRequest>[];
