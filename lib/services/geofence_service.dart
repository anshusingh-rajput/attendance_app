import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class Geofence {
  final int id;
  final String name;
  final List<List<double>> coordinates;

  const Geofence({
    required this.id,
    required this.name,
    required this.coordinates,
  });

  factory Geofence.fromJson(Map<String, dynamic> json) {
    final coords = (json['coordinates'] as List?) ?? const [];
    final parsed = <List<double>>[];
    for (final c in coords) {
      if (c is List && c.length >= 2) {
        parsed.add([
          (c[0] as num).toDouble(),
          (c[1] as num).toDouble(),
        ]);
      }
    }
    return Geofence(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? 'Unknown',
      coordinates: parsed,
    );
  }

  bool contains(double lat, double lng) {
    if (coordinates.length < 3) return false;
    var inside = false;
    final n = coordinates.length;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final yi = coordinates[i][0];
      final xi = coordinates[i][1];
      final yj = coordinates[j][0];
      final xj = coordinates[j][1];
      final intersect = ((yi > lat) != (yj > lat)) &&
          (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }
}

class GeofenceService {
  GeofenceService._();
  static final GeofenceService instance = GeofenceService._();

  static const String _baseUrl = 'https://bhsmart.satoop.com';
  static const String _fencesPath = '/api/mobile/geofences';
  static const Duration _cacheDuration = Duration(minutes: 2);

  List<Geofence> _cached = [];
  DateTime? _cachedAt;

  Future<List<Geofence>> getFences({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cached.isNotEmpty &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _cacheDuration) {
      return _cached;
    }

    try {
      final token = await AuthService().getToken();
      if (token == null || token.isEmpty) return _cached;

      final response = await http.get(
        Uri.parse('$_baseUrl$_fencesPath'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final fencesList =
            (data is Map<String, dynamic> ? data['fences'] as List? : null) ??
                const [];
        _cached = fencesList
            .whereType<Map<String, dynamic>>()
            .map(Geofence.fromJson)
            .toList();
        _cachedAt = DateTime.now();
      }
    } catch (_) {}

    return _cached;
  }

  Future<bool> isInsideAnyFence(double lat, double lng) async {
    final fences = await getFences();
    if (fences.isEmpty) return true;
    return fences.any((f) => f.contains(lat, lng));
  }

  Future<({double distance, String name})?> nearestFenceInfo(
    double lat,
    double lng,
  ) async {
    final fences = await getFences();
    if (fences.isEmpty) return null;
    double? minDist;
    String? nearestName;
    for (final f in fences) {
      for (final v in f.coordinates) {
        final d = Geolocator.distanceBetween(lat, lng, v[0], v[1]);
        if (minDist == null || d < minDist) {
          minDist = d;
          nearestName = f.name;
        }
      }
    }
    if (minDist == null || nearestName == null) return null;
    return (distance: minDist, name: nearestName);
  }
}
