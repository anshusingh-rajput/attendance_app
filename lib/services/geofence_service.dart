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
    return Geofence(
      id: (json['id'] as num?)?.toInt() ??
          (json['geofenceId'] as num?)?.toInt() ??
          0,
      name: (json['name'] as String?) ??
          (json['title'] as String?) ??
          'Unknown',
      coordinates: _parseCoordinates(json),
    );
  }

  /// Extracts the polygon vertices as `[lat, lng]` pairs, tolerating the
  /// different shapes the backend has used over time. Without this, a single
  /// shape change makes the list parse to empty → every point counts as
  /// "inside" → no breach is ever detected.
  static List<List<double>> _parseCoordinates(Map<String, dynamic> json) {
    // The vertex array may live under any of these keys.
    dynamic raw;
    for (final key in const [
      'coordinates',
      'points',
      'polygon',
      'path',
      'vertices',
      'boundary',
    ]) {
      if (json[key] is List && (json[key] as List).isNotEmpty) {
        raw = json[key];
        break;
      }
    }
    if (raw is! List) return const [];

    // GeoJSON Polygon nests one extra level: [[[lng,lat], ...]] — unwrap it.
    if (raw.isNotEmpty && raw.first is List && (raw.first as List).isNotEmpty &&
        (raw.first as List).first is List) {
      raw = raw.first;
    }

    final parsed = <List<double>>[];
    for (final c in raw) {
      final point = _parsePoint(c);
      if (point != null) parsed.add(point);
    }
    return parsed;
  }

  /// Parses one vertex into `[lat, lng]` from either an array (`[lat, lng]`)
  /// or an object (`{lat/latitude, lng/lon/long/longitude}`).
  static List<double>? _parsePoint(dynamic c) {
    if (c is List && c.length >= 2 && c[0] is num && c[1] is num) {
      return [(c[0] as num).toDouble(), (c[1] as num).toDouble()];
    }
    if (c is Map) {
      final lat = c['lat'] ?? c['latitude'] ?? c['Latitude'] ?? c['Lat'];
      final lng = c['lng'] ??
          c['lon'] ??
          c['long'] ??
          c['longitude'] ??
          c['Longitude'] ??
          c['Lng'];
      if (lat is num && lng is num) {
        return [lat.toDouble(), lng.toDouble()];
      }
    }
    return null;
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
  bool _lastLoadOk = false;

  /// Number of fences currently loaded (for on-screen diagnostics).
  int get fenceCount => _cached.length;

  /// Whether the most recent fetch actually returned a usable fence list.
  /// `false` means we never positively loaded fences — so an "inside" result
  /// is an assumption, not a verified fact.
  bool get lastLoadOk => _lastLoadOk;

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
        final fencesList = _extractFenceList(data);
        final parsed = fencesList.map(Geofence.fromJson).toList();
        // Only replace the cache when we got something usable, so a transient
        // empty/odd response doesn't wipe a previously-good fence list.
        if (parsed.isNotEmpty) {
          _cached = parsed;
          _cachedAt = DateTime.now();
          _lastLoadOk = true;
        } else {
          _lastLoadOk = _cached.isNotEmpty;
        }
      }
    } catch (_) {}

    return _cached;
  }

  /// Finds the fence array regardless of how the response is wrapped:
  /// a bare list, or under `fences`/`geofences`/`data`/`items`/`result`,
  /// including one level of nesting (e.g. `{data: {fences: [...]}}`).
  List<Map<String, dynamic>> _extractFenceList(dynamic data) {
    dynamic raw;
    if (data is List) {
      raw = data;
    } else if (data is Map) {
      for (final key in const [
        'fences',
        'geofences',
        'data',
        'items',
        'result',
        'results',
      ]) {
        if (data[key] is List) {
          raw = data[key];
          break;
        }
      }
      if (raw == null && data['data'] is Map) {
        final inner = data['data'] as Map;
        for (final key in const ['fences', 'geofences', 'items']) {
          if (inner[key] is List) {
            raw = inner[key];
            break;
          }
        }
      }
    }
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList();
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
