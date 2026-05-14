// lib/services/safety_api_service.dart
// ─────────────────────────────────────────────────────────────
// Talks to the FastAPI backend at BASE_URL.
//
// Android emulator  → http://10.0.2.2:8000
// Real device / iOS → your PC's LAN IP, e.g. http://192.168.1.5:8000
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:http/http.dart' as http;

// ▸ Change BASE_URL when testing on a real device or deploying to cloud
// ── Single source of truth: update IP here for your LAN ──────────────────
const String kBaseUrl = "https://supriyachola-nyvra-api.hf.space";

// ─────────────────────────────────────────────────────────────
// RESPONSE MODELS
// ─────────────────────────────────────────────────────────────

class AreaSafetyResult {
  final int safetyScore;
  final String dangerLevel; // "Low" | "Medium" | "High"
  final int dangerLabel; // 0 | 1 | 2
  final List<String> factors;

  AreaSafetyResult({
    required this.safetyScore,
    required this.dangerLevel,
    required this.dangerLabel,
    required this.factors,
  });

  factory AreaSafetyResult.fromJson(Map<String, dynamic> j) => AreaSafetyResult(
    safetyScore: j['safety_score'] as int,
    dangerLevel: j['danger_level'] as String,
    dangerLabel: j['danger_label'] as int,
    factors: List<String>.from(j['factors'] ?? []),
  );

  /// Fallback when the server is unreachable
  factory AreaSafetyResult.fallback() => AreaSafetyResult(
    safetyScore: 70,
    dangerLevel: 'Medium',
    dangerLabel: 1,
    factors: ['Could not reach server — showing default data'],
  );
}

class RouteResult {
  final String name;
  final String duration;
  final String distance;
  final int safetyScore;
  final List<String> factors;
  final bool isRecommended;

  RouteResult({
    required this.name,
    required this.duration,
    required this.distance,
    required this.safetyScore,
    required this.factors,
    required this.isRecommended,
  });

  factory RouteResult.fromJson(Map<String, dynamic> j) => RouteResult(
    name: j['name'] as String,
    duration: j['duration'] as String,
    distance: j['distance'] as String,
    safetyScore: j['safety_score'] as int,
    factors: List<String>.from(j['factors'] ?? []),
    isRecommended: j['is_recommended'] as bool? ?? false,
  );
}

class RouteAnalysisResult {
  final int overallScore;
  final List<RouteResult> routes;

  RouteAnalysisResult({required this.overallScore, required this.routes});

  factory RouteAnalysisResult.fromJson(Map<String, dynamic> j) =>
      RouteAnalysisResult(
        overallScore: j['overall_score'] as int,
        routes: (j['routes'] as List)
            .map((r) => RouteResult.fromJson(r as Map<String, dynamic>))
            .toList(),
      );

  factory RouteAnalysisResult.fallback() => RouteAnalysisResult(
    overallScore: 72,
    routes: [
      RouteResult(
        name: 'Safest Route',
        duration: '25 min',
        distance: '8.2 km',
        safetyScore: 88,
        factors: ['Well-lit streets', 'High foot traffic'],
        isRecommended: true,
      ),
      RouteResult(
        name: 'Fastest Route',
        duration: '18 min',
        distance: '6.5 km',
        safetyScore: 62,
        factors: ['Some isolated areas', 'Moderate incidents nearby'],
        isRecommended: false,
      ),
      RouteResult(
        name: 'Alternate Route',
        duration: '22 min',
        distance: '7.8 km',
        safetyScore: 74,
        factors: ['Residential areas', 'Low incident density'],
        isRecommended: false,
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────

class SafetyApiService {
  static const Duration _timeout = Duration(seconds: 10);

  // ── Predict danger for a single GPS point ──────────────────
  static Future<AreaSafetyResult> predictArea({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final response = await http
          .post(
        Uri.parse('$kBaseUrl/predict_area'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'latitude': latitude,
          'longitude': longitude,
        }),
      )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return AreaSafetyResult.fromJson(data);
      }
      return AreaSafetyResult.fallback();
    } catch (_) {
      return AreaSafetyResult.fallback();
    }
  }

  // ── Analyse route between two points ──────────────────────
  static Future<RouteAnalysisResult> analyzeRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    String time = 'Now',
  }) async {
    try {
      final response = await http
          .post(
        Uri.parse('$kBaseUrl/analyze_route'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'origin_lat': originLat,
          'origin_lng': originLng,
          'dest_lat': destLat,
          'dest_lng': destLng,
          'time': time,
        }),
      )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return RouteAnalysisResult.fromJson(data);
      }
      return RouteAnalysisResult.fallback();
    } catch (_) {
      return RouteAnalysisResult.fallback();
    }
  }

  // ── Health check ───────────────────────────────────────────
  static Future<bool> isServerOnline() async {
    try {
      final res = await http
          .get(Uri.parse('$kBaseUrl/health'))
          .timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}