import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'sos_service.dart';

class SOSController extends ChangeNotifier {
  final SOSService service = SOSService();

  bool contacted = false;
  bool sent = false;
  bool tracking = false;
  bool recording = false;

  String locationText = "Fetching location...";

  StreamSubscription<Position>? _positionStream;

  //////////////////////////////////////////////////////
  // 🚀 START SOS FLOW
  //////////////////////////////////////////////////////
  Future<void> startSOS() async {
    await _step(() => contacted = true);
    await _step(() => sent = true);
    await _step(() => tracking = true);
    await _step(() => recording = true);

    await service.triggerSOS();

    _startLiveTracking();
  }

  //////////////////////////////////////////////////////
  // 🔁 STEP HELPER
  //////////////////////////////////////////////////////
  Future<void> _step(VoidCallback update) async {
    await Future.delayed(const Duration(seconds: 1));
    update();
    notifyListeners();
  }

  //////////////////////////////////////////////////////
  // 📍 LIVE TRACKING
  //////////////////////////////////////////////////////
  void _startLiveTracking() {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
      ),
    ).listen((pos) {
      locationText =
      "Location: ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}";
      notifyListeners();
    });
  }

  //////////////////////////////////////////////////////
  // 🧹 CLEANUP
  //////////////////////////////////////////////////////
  void disposeController() {
    _positionStream?.cancel();
  }
}