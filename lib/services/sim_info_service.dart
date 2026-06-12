import 'package:flutter/services.dart';

class SimCardInfo {
  final int slotIndex;
  final String carrierName;
  final String displayName;
  final String number;

  const SimCardInfo({
    required this.slotIndex,
    required this.carrierName,
    required this.displayName,
    required this.number,
  });

  bool get hasNumber => number.trim().isNotEmpty;

  String get label {
    if (carrierName.isNotEmpty) return carrierName;
    if (displayName.isNotEmpty) return displayName;
    return 'SIM ${slotIndex + 1}';
  }

  factory SimCardInfo.fromMap(Map<dynamic, dynamic> map) {
    return SimCardInfo(
      slotIndex: (map['slotIndex'] as int?) ?? 0,
      carrierName: (map['carrierName'] as String?) ?? '',
      displayName: (map['displayName'] as String?) ?? '',
      number: (map['number'] as String?) ?? '',
    );
  }
}

class SimInfoService {
  SimInfoService._();
  static final SimInfoService instance = SimInfoService._();

  static const _channel = MethodChannel('com.hr360flow.hr360flow/sim');

  Future<List<SimCardInfo>> getSimCards() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('getSimCards');
      if (raw == null) return [];
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map(SimCardInfo.fromMap)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Shows the Google Phone Number Hint sheet (same approach Paytm/PhonePe
  /// use). Returns the picked number, or null if unavailable/dismissed.
  /// Needs no runtime permission and works on most Google-certified devices.
  Future<String?> requestPhoneNumberHint() async {
    try {
      return await _channel.invokeMethod<String>('requestPhoneNumberHint');
    } catch (_) {
      return null;
    }
  }
}
