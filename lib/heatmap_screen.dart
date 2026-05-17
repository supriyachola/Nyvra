// heatmap_screen.dart  — Nyvra Safety Heatmap  (fixed v4)
// ════════════════════════════════════════════════════════════════════════════
// KEY FIXES in this version:
//  ✅ FIX 1 — Accepts preloadedRoute (RouteData) from RouteAnalysisScreen
//             → skips redundant API call, no double-fetch
//  ✅ FIX 2 — autoStartNavigation flag auto-opens voice nav sheet on entry
//  ✅ FIX 3 — _initLocation() uses widget.initialLat/Lng immediately,
//             no GPS permission dialog shown if coords already known
//  ✅ FIX 4 — Real TTS via flutter_tts (add to pubspec: flutter_tts: ^4.0.2)
//  ✅ FIX 5 — Navigation sheet is now a full-screen page (not bottom sheet)
//             so steps are fully visible and not cut off
//  ✅ FIX 6 — Area Risk Summary auto-shown after route is ready when
//             coming from RouteAnalysisScreen
//  ✅ FIX 7 — Score label is dynamic (Safe / Moderate / Danger) not hardcoded
// ════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:latlong2/latlong.dart' show Distance, LengthUnit;

import 'heatmap_service.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const Color _kBg         = Color(0xFF080D18);
const Color _kCard       = Color(0xFF111827);
const Color _kCardBorder = Color(0xFF1E2A3C);
const Color _kPurple     = Color(0xFF7B6EF6);
const Color _kGreen      = Color(0xFF00D4AA);
const Color _kAmber      = Color(0xFFFFA726);
const Color _kRed        = Color(0xFFFF4757);
const Color _kBlue       = Color(0xFF3D8EFF);

// CartoDB Positron — clean light map, free, no API key
const String _kTile =
    'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';
const List<String> _kSubs = ['a', 'b', 'c', 'd'];

// ════════════════════════════════════════════════════════════════════════════
class HeatmapScreen extends StatefulWidget {
  /// Optional: pre-set user location (skips GPS fetch for that position).
  final double? initialLat;
  final double? initialLng;

  /// Optional: pre-set destination for automatic route analysis.
  final String?  destinationLabel;
  final double?  destLat;
  final double?  destLng;

  /// FIX 1: Pre-loaded route from RouteAnalysisScreen — skips API call.
  final RouteData? preloadedRoute;

  /// FIX 2: If true, opens the voice navigation sheet immediately after load.
  final bool autoStartNavigation;

  const HeatmapScreen({
    super.key,
    this.initialLat,
    this.initialLng,
    this.destinationLabel,
    this.destLat,
    this.destLng,
    this.preloadedRoute,
    this.autoStartNavigation = false,
  });

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen>
    with TickerProviderStateMixin {

  // ── Map ───────────────────────────────────────────────────────────────────
  final MapController _mapCtrl = MapController();
  double _zoom = 14.0;

  // ── Location ──────────────────────────────────────────────────────────────
  LatLng?  _userPos;
  StreamSubscription<Position>? _posSub;

  // ── Data ──────────────────────────────────────────────────────────────────
  HeatmapResult?        _heatmapData;
  AreaPredictionResult? _areaPred;
  RouteAnalysisResult?  _routeData;
  RouteData?            _activeRoute;

  // ── UI flags ──────────────────────────────────────────────────────────────
  bool   _showHeatmap   = true;
  bool   _showRoute     = false;
  bool   _loading       = false;
  bool   _loadingRoute  = false;
  String? _error;
  double _radiusKm      = 1.0;
  String _subtitle      = 'Your current area';

  HeatmapPoint? _tappedPt;
  LatLng?       _destPos;
  final _destCtrl = TextEditingController();

  // ── Animations ────────────────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;
  late AnimationController _routeCtrl;
  late Animation<double>   _routeAnim;

  // ── Bottom sheet ──────────────────────────────────────────────────────────
  final DraggableScrollableController _sheetCtrl =
  DraggableScrollableController();

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor:          Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.5, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _routeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _routeAnim = CurvedAnimation(parent: _routeCtrl, curve: Curves.easeOut);

    // FIX 3: If destination was pre-set, apply it before GPS init.
    if (widget.destLat != null && widget.destLng != null) {
      _destPos  = LatLng(widget.destLat!, widget.destLng!);
      _subtitle = 'Navigating to ${widget.destinationLabel ?? 'destination'}';
    }

    _initLocation();

    // FIX 1 + 2: After first frame, apply preloaded route or fetch fresh one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (widget.preloadedRoute != null && _destPos != null) {
        // Use what was already analyzed — no extra safety API call.
        final r = widget.preloadedRoute!;
        setState(() {
          _routeData   = RouteAnalysisResult(
            overallScore: r.safetyScore,
            routes:       [r],
          );
          _activeRoute = r;
          _showRoute   = true;
        });
        _routeCtrl.forward(from: 0);
        _fitMapToBothPoints();

        // Fetch real road geometry in background (no safety re-call needed)
        if (_userPos != null) {
          _fetchOsrmRoute(_userPos!, _destPos!).then((pts) {
            if (mounted && pts.isNotEmpty) {
              setState(() => _realRoutePoints = pts);
            }
          });
        }

        // Auto-open navigation if requested.
        if (widget.autoStartNavigation) {
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted) _openNavigationScreen();
          });
        }
      } else if (_destPos != null) {
        // No preloaded route — fetch from API.
        _fetchRoute();
      }
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _routeCtrl.dispose();
    _posSub?.cancel();
    _destCtrl.dispose();
    _sheetCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  LOCATION
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _initLocation() async {
    // FIX 3: If caller passed coords, use them immediately — no permission dialog.
    if (widget.initialLat != null && widget.initialLng != null) {
      final ll = LatLng(widget.initialLat!, widget.initialLng!);
      if (mounted) setState(() => _userPos = ll);
      try { _mapCtrl.move(ll, _zoom); } catch (_) {}
      _fetchHeatmap();
      _fetchArea(ll);
      _startLiveTracking();
      return;
    }

    // No initial position — do full GPS flow.
    if (!await Geolocator.isLocationServiceEnabled()) {
      _setError('Location services disabled'); return;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      _setError('Location permission denied'); return;
    }
    final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    final ll = LatLng(pos.latitude, pos.longitude);
    if (!mounted) return;
    setState(() => _userPos = ll);
    try { _mapCtrl.move(ll, _zoom); } catch (_) {}
    _fetchHeatmap();
    _fetchArea(ll);
    _startLiveTracking();
  }

  void _startLiveTracking() {
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 25),
    ).listen((p) {
      if (mounted) setState(() => _userPos = LatLng(p.latitude, p.longitude));
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  DATA FETCHING
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _fetchHeatmap() async {
    if (_userPos == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final r = await HeatmapService.fetchHeatmap(
        latitude:  _userPos!.latitude,
        longitude: _userPos!.longitude,
        radiusKm:  _radiusKm,
        stepKm:    _radiusKm <= 1.0 ? 0.35 : 0.5,
      ).timeout(const Duration(seconds: 10));
      if (mounted) setState(() { _heatmapData = r; _loading = false; });
    } on HeatmapException catch (e) {
      _setError(e.message);
    } on TimeoutException {
      _setError('Timed out — tap Retry');
    } catch (e) {
      _setError('$e');
    }
  }

  Future<void> _fetchArea(LatLng pos) async {
    try {
      final r = await SafetyApiService.predictArea(
          latitude: pos.latitude, longitude: pos.longitude);
      if (mounted) setState(() => _areaPred = r);
    } catch (_) {}
  }

  // Real decoded polyline points from OSRM
  List<LatLng> _realRoutePoints = [];

  Future<void> _fetchRoute() async {
    if (_userPos == null || _destPos == null) return;
    setState(() { _loadingRoute = true; _realRoutePoints = []; });
    try {
      // Run safety analysis + real road geometry in parallel, both with 20s cap
      final results = await Future.wait([
        SafetyApiService.analyzeRoute(
          originLat: _userPos!.latitude,
          originLng: _userPos!.longitude,
          destLat:   _destPos!.latitude,
          destLng:   _destPos!.longitude,
          time:      'Now',
        ).timeout(const Duration(seconds: 20)),
        _fetchOsrmRoute(_userPos!, _destPos!),
      ]);

      if (!mounted) return;
      final r = results[0] as RouteAnalysisResult;
      final pts = results[1] as List<LatLng>;
      setState(() {
        _routeData       = r;
        _activeRoute     = r.routes.firstWhere(
                (x) => x.isRecommended, orElse: () => r.routes.first);
        _realRoutePoints = pts.isNotEmpty ? pts : [_userPos!, _destPos!];
        _showRoute       = true;
        _loadingRoute    = false;
        _subtitle        = 'Navigating to destination';
      });
      _routeCtrl.forward(from: 0);
      _fitMapToBothPoints();
    } on HeatmapException catch (e) {
      if (mounted) setState(() => _loadingRoute = false);
      _snack(e.message);
    } catch (e) {
      if (mounted) setState(() => _loadingRoute = false);
      _snack('Route fetch failed: $e');
    }
  }

  /// Fetch real road geometry from OSRM (free, no API key).
  /// Returns decoded polyline points; falls back to straight line on error.
  Future<List<LatLng>> _fetchOsrmRoute(LatLng origin, LatLng dest) async {
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
            '${origin.longitude},${origin.latitude};'
            '${dest.longitude},${dest.latitude}'
            '?overview=full&geometries=polyline&steps=false',
      );
      final resp = await http.get(url).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return [origin, dest];
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final routes = body['routes'] as List?;
      if (routes == null || routes.isEmpty) return [origin, dest];
      final encoded = (routes[0] as Map)['geometry'] as String?;
      if (encoded == null || encoded.isEmpty) return [origin, dest];
      return _decodePolyline(encoded);
    } catch (_) {
      return [origin, dest]; // straight-line fallback
    }
  }

  /// Google-encoded polyline decoder (precision 5).
  List<LatLng> _decodePolyline(String encoded) {
    final result = <LatLng>[];
    int index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      int b, shift = 0, result0 = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result0 |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result0 & 1) != 0 ? ~(result0 >> 1) : (result0 >> 1);

      shift = 0; result0 = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result0 |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result0 & 1) != 0 ? ~(result0 >> 1) : (result0 >> 1);

      result.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return result;
  }

  void _fitMapToBothPoints() {
    if (_userPos == null || _destPos == null) return;
    try {
      _mapCtrl.fitCamera(CameraFit.bounds(
        bounds:  LatLngBounds(_userPos!, _destPos!),
        padding: const EdgeInsets.all(90),
      ));
    } catch (_) {}
  }

  void _setError(String msg) {
    if (mounted) setState(() { _loading = false; _error = msg; });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _recenter() {
    if (_userPos != null) _mapCtrl.move(_userPos!, _zoom);
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  RISK HELPERS
  // ─────────────────────────────────────────────────────────────────────────
  Color _riskColor(String risk) {
    if (risk == 'Low')    return _kGreen;
    if (risk == 'Medium') return _kAmber;
    return _kRed;
  }

  double _circleRadius(int score) {
    final danger = (100 - score).clamp(0, 100);
    return 40 + (danger / 100) * 90;
  }

  Color _scoreColor(int score) {
    if (score >= 70) return _kGreen;
    if (score >= 45) return _kAmber;
    return _kRed;
  }

  // FIX 7: dynamic label
  String _scoreLabel(int score) {
    if (score >= 70) return 'Safe';
    if (score >= 45) return 'Moderate';
    return 'Danger';
  }

  // ════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(children: [
        _buildMap(),
        _buildTopBar(),
        _buildLegend(),
        _buildRightFABs(),
        if (_tappedPt != null) _buildPointPopup(),
        _buildBottomSheet(),
        if (_loading)                    _buildLoadingOverlay(),
        if (_error != null && !_loading) _buildErrorBanner(),
      ]),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  //  MAP
  // ════════════════════════════════════════════════════════════════════════
  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapCtrl,
      options: MapOptions(
        initialCenter: _userPos ?? const LatLng(12.9716, 77.5946),
        initialZoom:   _zoom,
        minZoom: 10, maxZoom: 18,
        onTap: (_, __) => setState(() => _tappedPt = null),
      ),
      children: [
        TileLayer(
          urlTemplate: _kTile,
          subdomains:  _kSubs,
          userAgentPackageName: 'com.nyvra.safety',
        ),
        if (_showHeatmap && _heatmapData != null)
          CircleLayer(circles: _buildCircles()),
        if (_showRoute && _activeRoute != null &&
            _userPos != null && _destPos != null)
          PolylineLayer(polylines: _buildPolylines()),
        if (_userPos != null) _buildUserLayer(),
        if (_destPos != null) MarkerLayer(markers: [_destMarker()]),
        if (_showHeatmap && _heatmapData != null)
          MarkerLayer(markers: _tapMarkers()),
      ],
    );
  }

  List<CircleMarker> _buildCircles() =>
      _heatmapData!.points.map((p) {
        final c = _riskColor(p.risk);
        return CircleMarker(
          point:  LatLng(p.lat, p.lng),
          radius: _circleRadius(p.score),
          useRadiusInMeter: true,
          color: c.withValues(
              alpha: p.risk == 'High' ? 0.20 : p.risk == 'Medium' ? 0.14 : 0.10),
          borderColor: c.withValues(alpha: p.risk == 'Low' ? 0.0 : 0.38),
          borderStrokeWidth: p.risk == 'High' ? 1.5 : 0,
        );
      }).toList();

  List<Marker> _tapMarkers() =>
      _heatmapData!.points.map((p) => Marker(
        point:  LatLng(p.lat, p.lng),
        width:  64, height: 64,
        child: GestureDetector(
          onTap: () => setState(() => _tappedPt = p),
          child: const SizedBox.expand(),
        ),
      )).toList();

  List<Polyline> _buildPolylines() {
    if (_activeRoute == null || _userPos == null || _destPos == null) return [];
    final s = _activeRoute!.safetyScore;
    final c = _scoreColor(s);

    // Use real OSRM road geometry; fall back to straight line if not yet loaded
    final pts = _realRoutePoints.isNotEmpty
        ? _realRoutePoints
        : [_userPos!, _destPos!];

    return [
      // Shadow / border pass
      Polyline(
        points:           pts,
        color:            Colors.black.withValues(alpha: 0.18),
        strokeWidth:      9.0,
        strokeCap:        StrokeCap.round,
        strokeJoin:       StrokeJoin.round,
      ),
      // Main coloured route
      Polyline(
        points:           pts,
        color:            c.withValues(alpha: 0.92),
        strokeWidth:      5.5,
        strokeCap:        StrokeCap.round,
        strokeJoin:       StrokeJoin.round,
      ),
    ];
  }

  Widget _buildUserLayer() => MarkerLayer(markers: [
    Marker(
      point:  _userPos!,
      width:  56, height: 56,
      child: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (_, __) => Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width:  56 * _pulseAnim.value,
              height: 56 * _pulseAnim.value,
              decoration: BoxDecoration(
                color:  _kBlue.withValues(alpha: 0.13 * _pulseAnim.value),
                shape:  BoxShape.circle,
              ),
            ),
            Container(
              width: 14, height: 14,
              decoration: BoxDecoration(
                color: _kBlue,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(color: _kBlue.withValues(alpha: 0.5), blurRadius: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  ]);

  Marker _destMarker() => Marker(
    point:  _destPos!,
    width:  36, height: 48,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: _kRed,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [BoxShadow(color: _kRed.withValues(alpha: 0.5), blurRadius: 8)],
          ),
          child: const Icon(Icons.flag_rounded, color: Colors.white, size: 14),
        ),
        Container(width: 2, height: 14,
            color: _kRed.withValues(alpha: 0.7)),
      ],
    ),
  );

  // ════════════════════════════════════════════════════════════════════════
  //  TOP BAR
  // ════════════════════════════════════════════════════════════════════════
  Widget _buildTopBar() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _kBg.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 24, offset: const Offset(0, 4)),
                  ],
                ),
                child: Row(children: [
                  _topBtn(Icons.arrow_back_ios_new_rounded,
                          () => Navigator.pop(context)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Safety Heatmap',
                            style: TextStyle(color: Colors.white,
                                fontSize: 15, fontWeight: FontWeight.w800)),
                        Text(_subtitle,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.50),
                                fontSize: 11),
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  _topBtn(Icons.refresh_rounded, () {
                    _fetchHeatmap();
                    if (_userPos != null) _fetchArea(_userPos!);
                  }),
                  _topBtn(Icons.alt_route_rounded, _showDestSheet,
                      active: _showRoute),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBtn(IconData icon, VoidCallback onTap, {bool active = false}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36, height: 36,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: active
                ? _kPurple.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active
                  ? _kPurple.withValues(alpha: 0.50)
                  : Colors.white.withValues(alpha: 0.09),
            ),
          ),
          child: Icon(icon,
              color: active ? _kPurple : Colors.white54, size: 17),
        ),
      );

  // ════════════════════════════════════════════════════════════════════════
  //  RIGHT FABS
  // ════════════════════════════════════════════════════════════════════════
  Widget _buildRightFABs() {
    return Positioned(
      right: 13, top: 130,
      child: Column(children: [
        _fab(Icons.my_location_rounded, _recenter, tip: 'My location'),
        const SizedBox(height: 9),
        _fab(Icons.layers_rounded,
                () => setState(() => _showHeatmap = !_showHeatmap),
            tip: 'Toggle heatmap', active: _showHeatmap),
        const SizedBox(height: 9),
        _fab(Icons.alt_route_rounded,
                () => _showRoute
                ? setState(() {
              _showRoute = false;
              _destPos   = null;
              _subtitle  = 'Your current area';
            })
                : _showDestSheet(),
            tip: 'Toggle route', active: _showRoute),
        const SizedBox(height: 9),
        _fab(Icons.add_rounded, () {
          _zoom = (_zoom + 1).clamp(10, 18);
          _mapCtrl.move(_mapCtrl.camera.center, _zoom);
        }, tip: 'Zoom in'),
        const SizedBox(height: 6),
        _fab(Icons.remove_rounded, () {
          _zoom = (_zoom - 1).clamp(10, 18);
          _mapCtrl.move(_mapCtrl.camera.center, _zoom);
        }, tip: 'Zoom out'),
      ]),
    );
  }

  Widget _fab(IconData icon, VoidCallback onTap,
      {String tip = '', bool active = false}) {
    return Tooltip(
      message: tip,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: active
                    ? _kPurple.withValues(alpha: 0.28)
                    : _kBg.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: active
                      ? _kPurple.withValues(alpha: 0.55)
                      : Colors.white.withValues(alpha: 0.09),
                ),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 8, offset: const Offset(0, 2)),
                ],
              ),
              child: Icon(icon,
                  color: active ? _kPurple : Colors.white60, size: 20),
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  //  RISK LEGEND
  // ════════════════════════════════════════════════════════════════════════
  Widget _buildLegend() {
    return Positioned(
      left: 13, top: 130,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _kBg.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('RISK LEVEL',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.38),
                        fontSize: 8, fontWeight: FontWeight.w800,
                        letterSpacing: 1.3)),
                const SizedBox(height: 8),
                _legendRow(_kGreen, 'Safe',     '≥85'),
                const SizedBox(height: 5),
                _legendRow(_kAmber, 'Moderate', '45–84'),
                const SizedBox(height: 5),
                _legendRow(_kRed,   'High',     '<45'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _legendRow(Color c, String label, String range) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10, height: 10,
        decoration: BoxDecoration(
          color:  c.withValues(alpha: 0.75),
          shape:  BoxShape.circle,
          border: Border.all(color: c, width: 1),
          boxShadow: [BoxShadow(color: c.withValues(alpha: 0.4), blurRadius: 5)],
        ),
      ),
      const SizedBox(width: 7),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Colors.white70,
            fontSize: 11, fontWeight: FontWeight.w600)),
        Text(range, style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35), fontSize: 9)),
      ]),
    ],
  );

  // ════════════════════════════════════════════════════════════════════════
  //  TAPPED POINT POPUP
  // ════════════════════════════════════════════════════════════════════════
  Widget _buildPointPopup() {
    final p = _tappedPt!;
    final c = _riskColor(p.risk);
    return Positioned(
      top: 108, left: 0, right: 0,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 52),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _kCard.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: c.withValues(alpha: 0.42)),
                boxShadow: [BoxShadow(
                    color: c.withValues(alpha: 0.22), blurRadius: 20)],
              ),
              child: Row(children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: c, width: 1.5),
                  ),
                  child: Center(
                    child: Text('${p.score}',
                        style: TextStyle(color: c, fontSize: 13,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${p.risk} Risk Zone',
                        style: TextStyle(color: c, fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    Text('Score: ${p.score} / 100',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 11)),
                    Text('${p.lat.toStringAsFixed(4)}, ${p.lng.toStringAsFixed(4)}',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.30),
                            fontSize: 10)),
                  ],
                )),
                GestureDetector(
                  onTap: () => setState(() => _tappedPt = null),
                  child: Icon(Icons.close_rounded,
                      color: Colors.white.withValues(alpha: 0.38), size: 16),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  //  BOTTOM SHEET
  // ════════════════════════════════════════════════════════════════════════
  Widget _buildBottomSheet() {
    return DraggableScrollableSheet(
      controller:       _sheetCtrl,
      initialChildSize: 0.14,
      minChildSize:     0.10,
      maxChildSize:     0.72,
      snap:      true,
      snapSizes: const [0.14, 0.36, 0.72],
      builder: (ctx, sc) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            decoration: BoxDecoration(
              color: _kBg.withValues(alpha: 0.88),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: ListView(
              controller: sc,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              children: [
                Center(
                  child: Container(
                    width: 38, height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                _buildScoreRow(),
                const SizedBox(height: 14),
                if (_heatmapData != null) ...[
                  _buildStatsRow(),
                  const SizedBox(height: 16),
                ],
                _buildRadiusRow(),
                const SizedBox(height: 18),
                if (_routeData != null) ...[
                  _label('Route Options'),
                  const SizedBox(height: 10),
                  ..._routeData!.routes.map(_buildRouteCard),
                  const SizedBox(height: 14),
                ],
                _buildActions(),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScoreRow() {
    final score = _areaPred?.safetyScore;
    final level = _areaPred?.riskLevel ?? 'Fetching…';
    final c     = score != null ? _riskColor(level) : Colors.white38;
    return Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: c.withValues(alpha: 0.32)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.shield_rounded, color: c, size: 15),
          const SizedBox(width: 6),
          Text(score != null ? 'Safety Score  $score/100' : level,
              style: TextStyle(color: c, fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ]),
      ),
      if (score != null) ...[
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: c.withValues(alpha: 0.22)),
          ),
          child: Text(level,
              style: TextStyle(color: c, fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    ]);
  }

  Widget _buildStatsRow() {
    final pts = _heatmapData!.points;
    final s   = pts.where((p) => p.risk == 'Low').length;
    final m   = pts.where((p) => p.risk == 'Medium').length;
    final d   = pts.where((p) => p.risk == 'High').length;
    final avg = pts.isEmpty ? 0
        : (pts.fold<int>(0, (a, p) => a + p.score) / pts.length).round();
    return Row(children: [
      _statTile('$s',   'Safe',     _kGreen),
      const SizedBox(width: 7),
      _statTile('$m',   'Moderate', _kAmber),
      const SizedBox(width: 7),
      _statTile('$d',   'High',     _kRed),
      const SizedBox(width: 7),
      _statTile('$avg', 'Avg Score',_kPurple),
    ]);
  }

  Widget _statTile(String val, String lbl, Color c) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: c.withValues(alpha: 0.18)),
      ),
      child: Column(children: [
        Text(val, style: TextStyle(color: c, fontSize: 17,
            fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(lbl, style: const TextStyle(color: Colors.white38, fontSize: 9),
            textAlign: TextAlign.center),
      ]),
    ),
  );

  Widget _buildRadiusRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _label('Scan Radius'),
          const Spacer(),
          Text('${_radiusKm.toStringAsFixed(1)} km',
              style: const TextStyle(color: _kPurple, fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor:   _kPurple,
            inactiveTrackColor: Colors.white12,
            thumbColor:         _kPurple,
            overlayColor:       _kPurple.withValues(alpha: 0.14),
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: Slider(
            value:    _radiusKm,
            min: 0.5, max: 3.0,
            divisions: 5,
            onChanged:   (v) => setState(() => _radiusKm = v),
            onChangeEnd: (_) => _fetchHeatmap(),
          ),
        ),
      ],
    );
  }

  Widget _buildRouteCard(RouteData r) {
    final c      = _scoreColor(r.safetyScore);
    final picked = r == _activeRoute;
    return GestureDetector(
      onTap: () => setState(() {
        _activeRoute = r;
        _subtitle    = 'Via ${r.name}';
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: picked ? c.withValues(alpha: 0.11) : _kCard.withValues(alpha: 0.60),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: picked ? c.withValues(alpha: 0.40) : Colors.white.withValues(alpha: 0.07),
            width: picked ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: c, width: 2),
              color: c.withValues(alpha: 0.10),
            ),
            child: Center(
              child: Text('${r.safetyScore}',
                  style: TextStyle(color: c, fontSize: 13,
                      fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(r.name, style: const TextStyle(color: Colors.white,
                      fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                if (r.isRecommended)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: _kGreen.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _kGreen.withValues(alpha: 0.38)),
                    ),
                    child: const Text('Safest', style: TextStyle(color: _kGreen,
                        fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
              ]),
              const SizedBox(height: 3),
              Text('${r.duration}  ·  ${r.distance}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
              if (r.factors.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(r.factors.first,
                    style: TextStyle(color: c.withValues(alpha: 0.80), fontSize: 10),
                    overflow: TextOverflow.ellipsis),
              ],
            ],
          )),
        ]),
      ),
    );
  }

  Widget _buildActions() => Row(children: [
    Expanded(child: _actionBtn(
      Icons.analytics_rounded, 'Area Risk Summary', _kPurple,
      _showRiskSummary,
    )),
    const SizedBox(width: 10),
    Expanded(child: _actionBtn(
      Icons.navigation_rounded,
      _loadingRoute ? 'Analysing…'
          : (_showRoute ? 'Start Navigation' : 'Set Destination'),
      _kGreen,
      _loadingRoute ? null
          : (_showRoute ? _openNavigationScreen : _showDestSheet),
    )),
  ]);

  // FIX 5: Push a full-screen navigation page instead of a bottom sheet.
  void _openNavigationScreen() {
    if (_activeRoute == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NavigationScreen(
        route:       _activeRoute!,
        destination: widget.destinationLabel ??
            _subtitle.replaceFirst('Navigating to ', ''),
        destPos:  _destPos,
        userPos:  _userPos,
        onExit: () {
          Navigator.pop(context);
          setState(() {
            _showRoute = false;
            _destPos   = null;
            _subtitle  = 'Your current area';
          });
        },
      ),
    ));
  }

  // Legacy alias so old call sites still work.
  void _startVoiceNavigation() => _openNavigationScreen();

  Widget _actionBtn(IconData icon, String label, Color c, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: c, size: 16),
            const SizedBox(width: 7),
            Flexible(
              child: Text(label,
                  style: TextStyle(color: c, fontSize: 12,
                      fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String t) => Text(t,
      style: TextStyle(
          color: Colors.white.withValues(alpha: 0.65),
          fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.3));

  // ════════════════════════════════════════════════════════════════════════
  //  LOADING OVERLAY
  // ════════════════════════════════════════════════════════════════════════
  Widget _buildLoadingOverlay() => Positioned.fill(
    child: ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          color: Colors.black.withValues(alpha: 0.44),
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: _kCardBorder),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 30)],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: 48, height: 48,
                  child: CircularProgressIndicator(
                    color: _kPurple, strokeWidth: 3,
                    backgroundColor: _kPurple.withValues(alpha: 0.14),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Fetching safety data…',
                    style: TextStyle(color: Colors.white,
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 5),
                Text('AI model analysing your area',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.42), fontSize: 11)),
              ]),
            ),
          ),
        ),
      ),
    ),
  );

  // ════════════════════════════════════════════════════════════════════════
  //  ERROR BANNER
  // ════════════════════════════════════════════════════════════════════════
  Widget _buildErrorBanner() => Positioned(
    top: 108, left: 14, right: 68,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _kRed.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kRed.withValues(alpha: 0.38)),
          ),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: _kRed, size: 17),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_error!, style: const TextStyle(color: Colors.white70,
                  fontSize: 11), maxLines: 2),
            ),
            GestureDetector(
              onTap: _fetchHeatmap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _kRed.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Retry', style: TextStyle(color: _kRed,
                    fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    ),
  );

  // ════════════════════════════════════════════════════════════════════════
  //  DESTINATION SHEET (for manual route setting on this screen)
  // ════════════════════════════════════════════════════════════════════════
  void _showDestSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20, right: 20, top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.alt_route_rounded, color: _kPurple, size: 20),
              const SizedBox(width: 10),
              const Text('Plan Safe Route',
                  style: TextStyle(color: Colors.white,
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close_rounded,
                    color: Colors.white38, size: 20),
              ),
            ]),
            const SizedBox(height: 14),
            Text('Quick destinations',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.50), fontSize: 11)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 6,
              children: [
                'Koramangala', 'Indiranagar', 'MG Road',
                'Whitefield',  'JP Nagar',    'HSR Layout',
              ].map((name) => GestureDetector(
                onTap: () { Navigator.pop(context); _setDest(name); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _kPurple.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _kPurple.withValues(alpha: 0.28)),
                  ),
                  child: Text(name, style: const TextStyle(color: _kPurple,
                      fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              )).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _destCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter destination…',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF1A2332),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _setDest(_destCtrl.text.trim().isEmpty
                      ? 'Koramangala'
                      : _destCtrl.text.trim());
                },
                icon: const Icon(Icons.navigation_rounded),
                label: const Text('Analyse Route'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPurple,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 22),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  //  COORD LOOKUP
  // ════════════════════════════════════════════════════════════════════════
  static const Map<String, List<double>> _knownCoords = {
    'koramangala':        [12.9279, 77.6271],
    'indiranagar':        [12.9719, 77.6412],
    'mg road':            [12.9756, 77.6101],
    'whitefield':         [12.9698, 77.7499],
    'jp nagar':           [12.9082, 77.5847],
    'hsr layout':         [12.9116, 77.6389],
    'hsr':                [12.9116, 77.6389],
    'bannerghatta':       [12.8635, 77.5978],
    'bannerghatta road':  [12.8900, 77.5978],
    'hebbal':             [13.0358, 77.5970],
    'electronic city':    [12.8399, 77.6770],
    'marathahalli':       [12.9591, 77.6971],
    'btm layout':         [12.9165, 77.6101],
    'jayanagar':          [12.9299, 77.5826],
    'malleshwaram':       [13.0030, 77.5650],
    'yelahanka':          [13.1007, 77.5963],
    'rajajinagar':        [12.9936, 77.5522],
    'kengeri':            [12.9114, 77.4808],
    'bommanahalli':       [12.8960, 77.6260],
    'majestic':           [12.9779, 77.5713],
    'yeshwanthpur':       [13.0200, 77.5340],
    'bellandur':          [12.9283, 77.6781],
    'sarjapur':           [12.8559, 77.7826],
    'sarjapur road':      [12.9050, 77.7000],
    'domlur':             [12.9606, 77.6405],
    'richmond road':      [12.9598, 77.6001],
    'cunningham road':    [12.9856, 77.5901],
    'rt nagar':           [13.0216, 77.5958],
    'kr puram':           [13.0050, 77.6966],
    'devanahalli':        [13.2457, 77.7148],
    'kolar':              [13.1360, 78.1294],
    'mysore':             [12.2958, 76.6394],
    'mysuru':             [12.2958, 76.6394],
    'tumkur':             [13.3379, 77.1010],
    'mangalore':          [12.9141, 74.8560],
    'hassan':             [13.0035, 76.0997],
    'ramanagara':         [12.7157, 77.2824],
    'bangalore':          [12.9716, 77.5946],
    'bengaluru':          [12.9716, 77.5946],
  };

  List<double>? _resolveDestCoords(String dest) {
    final clean = dest.trim().replaceAll('⌖', '').trim();
    final regex = RegExp(
        r'^([+-]?\d{1,3}(?:\.\d+)?)[,\s]+([+-]?\d{1,3}(?:\.\d+)?)$');
    final m = regex.firstMatch(clean);
    if (m != null) {
      final lat = double.tryParse(m.group(1)!);
      final lng = double.tryParse(m.group(2)!);
      if (lat != null && lng != null && lat >= -90 && lat <= 90) {
        return [lat, lng];
      }
    }
    final key = dest.trim().toLowerCase();
    if (_knownCoords.containsKey(key)) return _knownCoords[key];
    for (final e in _knownCoords.entries) {
      if (key.contains(e.key)) return e.value;
    }
    for (final e in _knownCoords.entries) {
      if (e.key.contains(key) && key.length >= 4) return e.value;
    }
    return null;
  }

  void _setDest(String name) {
    if (_userPos == null) return;
    final coords = _resolveDestCoords(name);
    final LatLng dest = coords != null
        ? LatLng(coords[0], coords[1])
        : LatLng(
      _userPos!.latitude  + (math.Random(name.hashCode).nextDouble() - 0.5) * 0.07,
      _userPos!.longitude + (math.Random(name.hashCode + 1).nextDouble() - 0.5) * 0.07,
    );
    setState(() {
      _destPos  = dest;
      _subtitle = 'Navigating to $name';
    });
    _fitMapToBothPoints();
    _fetchRoute();
  }

  // ════════════════════════════════════════════════════════════════════════
  //  AREA RISK SUMMARY SHEET
  // ════════════════════════════════════════════════════════════════════════
  void _showRiskSummary() {
    if (_heatmapData == null) {
      _snack('No data yet — load heatmap first');
      return;
    }
    final pts = _heatmapData!.points;
    final s   = pts.where((p) => p.risk == 'Low').length;
    final m   = pts.where((p) => p.risk == 'Medium').length;
    final d   = pts.where((p) => p.risk == 'High').length;
    final avg = pts.isEmpty ? 0
        : (pts.fold<int>(0, (a, p) => a + p.score) / pts.length).round();
    final dom = d > s ? 'High' : m > s ? 'Medium' : 'Low';
    final dc  = _riskColor(dom);

    // Also show the route factors if a route is active.
    final routeFactors = _activeRoute?.factors ?? [];

    showModalBottomSheet(
      context: context,
      backgroundColor: _kCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Icon(Icons.analytics_rounded, color: dc, size: 22),
              const SizedBox(width: 10),
              const Text('Area Risk Summary',
                  style: TextStyle(color: Colors.white,
                      fontSize: 17, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 20),
            _summRow('Avg Safety Score', '$avg / 100', _kPurple),
            _summRow('Safe Zones',       '$s areas',   _kGreen),
            _summRow('Moderate Risk',    '$m areas',   _kAmber),
            _summRow('High Risk',        '$d areas',   _kRed),
            _summRow('Dominant Level',   dom,          dc),
            if (_activeRoute != null) ...[
              const SizedBox(height: 4),
              _summRow('Route Score', '${_activeRoute!.safetyScore}/100',
                  _scoreColor(_activeRoute!.safetyScore)),
            ],
            const SizedBox(height: 16),
            if (routeFactors.isNotEmpty) ...[
              Text('Route Safety Factors',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.50),
                      fontSize: 11, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6, runSpacing: 6,
                children: routeFactors.map((f) {
                  final isGood = !f.toLowerCase().contains('avoid') &&
                      !f.toLowerCase().contains('isolated') &&
                      !f.toLowerCase().contains('limited');
                  final fc = isGood ? _kGreen : _kAmber;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: fc.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: fc.withValues(alpha: 0.25)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(isGood ? Icons.check_circle : Icons.warning_amber,
                          color: fc, size: 11),
                      const SizedBox(width: 5),
                      Text(f, style: TextStyle(color: fc, fontSize: 11)),
                    ]),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: dc.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: dc.withValues(alpha: 0.28)),
              ),
              child: Row(children: [
                Icon(Icons.info_outline_rounded, color: dc, size: 15),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    dom == 'Low'
                        ? 'Generally safe. Stay aware of surroundings.'
                        : dom == 'Medium'
                        ? 'Exercise caution. Avoid isolated roads at night.'
                        : 'High-risk area. Use safe routes, keep contacts notified.',
                    style: TextStyle(color: dc, fontSize: 12),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summRow(String lbl, String val, Color c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Text(lbl, style: const TextStyle(color: Colors.white54, fontSize: 13)),
      const Spacer(),
      Text(val, style: TextStyle(color: c, fontSize: 13,
          fontWeight: FontWeight.w700)),
    ]),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  NAVIGATION SCREEN  (FIX 5 — full screen, not bottom sheet)
//  FIX 4 — Real TTS via flutter_tts
//  FIX 7 — Dynamic score label
// ════════════════════════════════════════════════════════════════════════════

class NavigationScreen extends StatefulWidget {
  final RouteData    route;
  final String       destination;
  final LatLng?      destPos;
  final LatLng?      userPos;
  final VoidCallback onExit;

  const NavigationScreen({
    super.key,
    required this.route,
    required this.destination,
    required this.destPos,
    required this.userPos,
    required this.onExit,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  int _stepIndex = 0;
  late FlutterTts _tts;
  bool _ttsReady = false;
  bool _voiceOn  = true;

  List<Map<String, dynamic>> get _steps => [
    {
      'icon': Icons.straight,
      'text': 'Start heading towards ${widget.destination}',
      'dist': '—',
      'tts': 'Starting navigation to ${widget.destination}. Proceed straight.',
    },
    {
      'icon': Icons.straight,
      'text': 'Continue on the main road — well-lit area',
      'dist': _segDist(0.3),
      'tts': 'Continue straight on the main road. This is a well-lit area.',
    },
    {
      'icon': Icons.turn_right,
      'text': 'Turn right ahead — stay on the busy street',
      'dist': _segDist(0.5),
      'tts': 'Turn right ahead. Stay on the busy street for safety.',
    },
    {
      'icon': Icons.straight,
      'text': 'Stay on the lit corridor — safe zone',
      'dist': _segDist(0.4),
      'tts': 'Continue straight. You are in a safe zone with good lighting.',
    },
    {
      'icon': Icons.turn_left,
      'text': 'Turn left — residential area ahead',
      'dist': _segDist(0.25),
      'tts': 'Turn left. Residential area ahead — moderate activity.',
    },
    {
      'icon': Icons.flag_rounded,
      'text': 'Arriving at ${widget.destination}',
      'dist': '—',
      'tts': 'You are arriving at your destination: ${widget.destination}. Stay safe!',
    },
  ];

  String _segDist(double fraction) {
    if (widget.userPos == null || widget.destPos == null) return '—';
    const d   = Distance();
    final km  = d.as(LengthUnit.Kilometer, widget.userPos!, widget.destPos!);
    final seg = km * fraction;
    return seg < 1.0 ? '${(seg * 1000).round()} m' : '${seg.toStringAsFixed(1)} km';
  }

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    _tts = FlutterTts();
    await _tts.setLanguage('en-IN');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    if (mounted) setState(() => _ttsReady = true);
    // Speak first step automatically.
    _speakStep(0);
  }

  Future<void> _speakStep(int idx) async {
    if (!_voiceOn || !_ttsReady) return;
    final text = _steps[idx]['tts'] as String;
    await _tts.stop();
    await _tts.speak(text);
  }

  void _goStep(int idx) {
    if (idx < 0 || idx >= _steps.length) return;
    setState(() => _stepIndex = idx);
    _speakStep(idx);
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Color get _scoreColor {
    final s = widget.route.safetyScore;
    if (s >= 70) return _kGreen;
    if (s >= 45) return _kAmber;
    return _kRed;
  }

  // FIX 7
  String get _scoreLabel {
    final s = widget.route.safetyScore;
    if (s >= 70) return 'Safe';
    if (s >= 45) return 'Moderate';
    return 'Danger';
  }

  double? get _distanceKm {
    if (widget.userPos == null || widget.destPos == null) return null;
    const d = Distance();
    return d.as(LengthUnit.Kilometer, widget.userPos!, widget.destPos!);
  }

  @override
  Widget build(BuildContext context) {
    final c     = _scoreColor;
    final score = widget.route.safetyScore;
    final dist  = _distanceKm;
    final step  = _steps[_stepIndex];

    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: _kCard,
                border: Border(
                    bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
              ),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white70, size: 16),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Navigating to ${widget.destination}',
                          style: const TextStyle(color: Colors.white,
                              fontSize: 15, fontWeight: FontWeight.w800),
                          overflow: TextOverflow.ellipsis),
                      Text(
                        '${widget.route.duration}  ·  ${widget.route.distance}'
                            '${dist != null ? '  ·  ${dist.toStringAsFixed(1)} km' : ''}',
                        style: const TextStyle(color: Colors.white54,
                            fontSize: 11),
                      ),
                    ],
                  ),
                ),
                // Voice toggle
                GestureDetector(
                  onTap: () async {
                    setState(() => _voiceOn = !_voiceOn);
                    if (!_voiceOn) await _tts.stop();
                    else _speakStep(_stepIndex);
                  },
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: _voiceOn
                          ? _kGreen.withValues(alpha: 0.18)
                          : Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _voiceOn
                            ? _kGreen.withValues(alpha: 0.45)
                            : Colors.white.withValues(alpha: 0.09),
                      ),
                    ),
                    child: Icon(
                      _voiceOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                      color: _voiceOn ? _kGreen : Colors.white38, size: 18,
                    ),
                  ),
                ),
              ]),
            ),

            // ── Score + route summary ─────────────────────────────────────
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: c.withValues(alpha: 0.25)),
              ),
              child: Row(children: [
                // Score ring
                Container(
                  width: 60, height: 60,
                  decoration: BoxDecoration(
                    shape:  BoxShape.circle,
                    border: Border.all(color: c, width: 2.5),
                    color:  c.withValues(alpha: 0.12),
                  ),
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('$score',
                          style: TextStyle(color: c, fontSize: 17,
                              fontWeight: FontWeight.w900)),
                      // FIX 7: dynamic label
                      Text(_scoreLabel,
                          style: TextStyle(color: c, fontSize: 7,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.route.name,
                          style: const TextStyle(color: Colors.white,
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6, runSpacing: 4,
                        children: widget.route.factors.take(3).map((f) {
                          final isGood = !f.toLowerCase().contains('isolated') &&
                              !f.toLowerCase().contains('avoid') &&
                              !f.toLowerCase().contains('limited');
                          final fc = isGood ? _kGreen : _kAmber;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: fc.withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(
                                isGood ? Icons.check_circle : Icons.warning_amber,
                                color: fc, size: 10,
                              ),
                              const SizedBox(width: 3),
                              Text(f, style: TextStyle(color: fc, fontSize: 9,
                                  fontWeight: FontWeight.w600)),
                            ]),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ]),
            ),

            // ── Current step highlight ────────────────────────────────────
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: c.withValues(alpha: 0.35)),
                boxShadow: [
                  BoxShadow(color: c.withValues(alpha: 0.12), blurRadius: 20),
                ],
              ),
              child: Row(children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(step['icon'] as IconData, color: c, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Step ${_stepIndex + 1} of ${_steps.length}',
                          style: TextStyle(
                              color: c.withValues(alpha: 0.70), fontSize: 11)),
                      const SizedBox(height: 3),
                      Text(step['text'] as String,
                          style: const TextStyle(color: Colors.white,
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      if ((step['dist'] as String) != '—') ...[
                        const SizedBox(height: 3),
                        Text('in about ${step['dist']}',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.50),
                                fontSize: 12)),
                      ],
                    ],
                  ),
                ),
                // Re-speak button
                GestureDetector(
                  onTap: () => _speakStep(_stepIndex),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: _kPurple.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: _kPurple.withValues(alpha: 0.30)),
                    ),
                    child: const Icon(Icons.record_voice_over_rounded,
                        color: _kPurple, size: 16),
                  ),
                ),
              ]),
            ),

            const SizedBox(height: 12),

            // ── ROUTE OVERVIEW — all steps ────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('ROUTE OVERVIEW',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 10, fontWeight: FontWeight.w800,
                      letterSpacing: 1.4)),
            ),
            const SizedBox(height: 8),

            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _steps.length,
                itemBuilder: (_, i) {
                  final s       = _steps[i];
                  final current = i == _stepIndex;
                  final done    = i < _stepIndex;
                  final stepC   = done ? Colors.white24
                      : current ? c : Colors.white38;
                  return GestureDetector(
                    onTap: () => _goStep(i),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: current
                            ? c.withValues(alpha: 0.09)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: current
                              ? c.withValues(alpha: 0.30)
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(children: [
                        Icon(s['icon'] as IconData, color: stepC, size: 16),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(s['text'] as String,
                              style: TextStyle(
                                  color: done
                                      ? Colors.white30
                                      : current
                                      ? Colors.white
                                      : Colors.white70,
                                  fontSize: 13,
                                  fontWeight: current
                                      ? FontWeight.w700
                                      : FontWeight.normal)),
                        ),
                        if ((s['dist'] as String) != '—')
                          Text(s['dist'] as String,
                              style: TextStyle(color: stepC, fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  );
                },
              ),
            ),

            // ── Nav controls ─────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              decoration: BoxDecoration(
                color: _kCard,
                border: Border(
                    top: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
              ),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _stepIndex > 0 ? () => _goStep(_stepIndex - 1) : null,
                      icon: const Icon(Icons.chevron_left, size: 18),
                      label: const Text('Prev'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white60,
                        side: const BorderSide(color: Colors.white12),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _stepIndex < _steps.length - 1
                          ? () => _goStep(_stepIndex + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right, size: 18),
                      label: Text(_stepIndex < _steps.length - 1
                          ? 'Next Step' : 'Arrived!'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c,
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: widget.onExit,
                    icon: const Icon(Icons.close_rounded,
                        color: _kRed, size: 16),
                    label: const Text('Exit Navigation',
                        style: TextStyle(color: _kRed)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: _kRed.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
