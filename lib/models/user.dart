class User {
  final int? employeeId;
  final String? employeeCode;
  final String displayName;
  final String? email;
  final String? mobileNo;
  final String? departmentName;
  final String? presenceState;
  final bool gpsTrackingActive;
  final List<dynamic> vehicles;
  final String? profilePhotoUrl;
  final String? shiftName;
  final String? shiftStart;
  final String? shiftEnd;

  const User({
    this.employeeId,
    this.employeeCode,
    required this.displayName,
    this.email,
    this.mobileNo,
    this.departmentName,
    this.presenceState,
    this.gpsTrackingActive = false,
    this.vehicles = const [],
    this.profilePhotoUrl,
    this.shiftName,
    this.shiftStart,
    this.shiftEnd,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? shift;
    final s = json['shift'] ?? json['currentShift'];
    if (s is Map<String, dynamic>) shift = s;

    return User(
      employeeId: (json['employeeId'] as num?)?.toInt(),
      employeeCode: json['employeeCode'] as String?,
      displayName: (json['displayName'] as String?) ?? '',
      email: json['email'] as String?,
      mobileNo: json['mobileNo'] as String?,
      departmentName: json['departmentName'] as String?,
      presenceState: json['presenceState'] as String?,
      gpsTrackingActive: (json['gpsTrackingActive'] as bool?) ?? false,
      vehicles: (json['vehicles'] as List?) ?? const [],
      profilePhotoUrl: json['profilePhotoUrl'] as String?,
      shiftName: shift?['name'] as String?,
      shiftStart: shift?['start'] as String? ?? shift?['startTime'] as String?,
      shiftEnd: shift?['end'] as String? ?? shift?['endTime'] as String?,
    );
  }

  String get firstName {
    if (displayName.trim().isEmpty) return 'User';
    return displayName.trim().split(RegExp(r'\s+')).first;
  }

  String get initials {
    final name = displayName.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    final p = parts[0];
    return (p.length >= 2 ? p.substring(0, 2) : p).toUpperCase();
  }
}
