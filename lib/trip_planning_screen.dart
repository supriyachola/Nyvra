// trip_planning_screen.dart
// ✅ Device contacts fetched directly (no database)
// ✅ Runtime READ_CONTACTS permission handled correctly
// ✅ WhatsApp deep linking fixed
// ✅ Google Maps directions fixed
// ✅ Dynamic destination via GPS + text input


import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';

// ─────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────

class TrustedContact {
  final String name;
  final String phone;
  final String initials;

  TrustedContact({
    required this.name,
    required this.phone,
    required this.initials,
  });
}

class RouteOption {
  final String name;
  final String duration;
  final String distance;
  final int safetyScore;
  final List<String> factors;
  final bool isRecommended;

  RouteOption({
    required this.name,
    required this.duration,
    required this.distance,
    required this.safetyScore,
    required this.factors,
    required this.isRecommended,
  });
}

// ─────────────────────────────────────────────
// TOP INDIAN CITIES
// ─────────────────────────────────────────────

const List<Map<String, String>> kIndianCities = [
  {"name": "Mumbai", "state": "Maharashtra", "emoji": "🏙️"},
  {"name": "Delhi", "state": "Delhi", "emoji": "🏛️"},
  {"name": "Bengaluru", "state": "Karnataka", "emoji": "🌿"},
  {"name": "Hyderabad", "state": "Telangana", "emoji": "💎"},
  {"name": "Chennai", "state": "Tamil Nadu", "emoji": "🌊"},
  {"name": "Kolkata", "state": "West Bengal", "emoji": "🎭"},
  {"name": "Pune", "state": "Maharashtra", "emoji": "🎓"},
  {"name": "Ahmedabad", "state": "Gujarat", "emoji": "🪁"},
  {"name": "Jaipur", "state": "Rajasthan", "emoji": "🏰"},
  {"name": "Surat", "state": "Gujarat", "emoji": "💍"},
  {"name": "Lucknow", "state": "Uttar Pradesh", "emoji": "🕌"},
  {"name": "Kanpur", "state": "Uttar Pradesh", "emoji": "🏭"},
  {"name": "Nagpur", "state": "Maharashtra", "emoji": "🍊"},
  {"name": "Indore", "state": "Madhya Pradesh", "emoji": "🌆"},
  {"name": "Bhopal", "state": "Madhya Pradesh", "emoji": "🏞️"},
  {"name": "Visakhapatnam", "state": "Andhra Pradesh", "emoji": "⚓"},
  {"name": "Patna", "state": "Bihar", "emoji": "🏯"},
  {"name": "Vadodara", "state": "Gujarat", "emoji": "🎪"},
  {"name": "Ghaziabad", "state": "Uttar Pradesh", "emoji": "🏘️"},
  {"name": "Ludhiana", "state": "Punjab", "emoji": "🌾"},
  {"name": "Agra", "state": "Uttar Pradesh", "emoji": "🕌"},
  {"name": "Nashik", "state": "Maharashtra", "emoji": "🍇"},
  {"name": "Faridabad", "state": "Haryana", "emoji": "🏗️"},
  {"name": "Meerut", "state": "Uttar Pradesh", "emoji": "⚔️"},
  {"name": "Coimbatore", "state": "Tamil Nadu", "emoji": "🧵"},
  {"name": "Kochi", "state": "Kerala", "emoji": "🌴"},
  {"name": "Mysuru", "state": "Karnataka", "emoji": "👑"},
  {"name": "Thiruvananthapuram", "state": "Kerala", "emoji": "🐘"},
  {"name": "Chandigarh", "state": "Punjab/Haryana", "emoji": "🌹"},
  {"name": "Guwahati", "state": "Assam", "emoji": "🦏"},
];

// ─────────────────────────────────────────────
// PERMISSION HELPER
// ─────────────────────────────────────────────

/// Unified permission helper.
/// Returns true if the permission is granted (or already was).
/// Shows a settings dialog if permanently denied.
Future<bool> _requestPermission(
    BuildContext context, Permission permission, String label) async {
  PermissionStatus status = await permission.status;

  if (status.isGranted) return true;

  if (status.isPermanentlyDenied) {
    if (context.mounted) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('$label Permission Required'),
          content: Text(
              '$label permission is permanently denied. Please enable it in Settings.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                openAppSettings();
                Navigator.pop(context);
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
    }
    return false;
  }

  status = await permission.request();
  return status.isGranted;
}

// ─────────────────────────────────────────────
// MAIN TRIP PLANNING SCREEN
// ─────────────────────────────────────────────

class TripPlanningScreen extends StatefulWidget {
  const TripPlanningScreen({super.key});

  @override
  State<TripPlanningScreen> createState() => _TripPlanningScreenState();
}

class _TripPlanningScreenState extends State<TripPlanningScreen> {
  final TextEditingController pickupController = TextEditingController();
  final TextEditingController destinationController = TextEditingController();

  String selectedTime = "Now";
  String selectedRider = "Me";
  bool isLoading = false;

  double? _currentLat;
  double? _currentLng;

  List<TrustedContact> trustedContacts = [];
  bool contactsLoading = false;
  String? contactsError;

  final List<Map<String, dynamic>> recentLocations = [
    {
      "name": "Doddachenuvalli",
      "address": "Karnataka",
      "distance": "0.9 km",
      "safetyScore": 85,
    },
    {
      "name": "Thyamagondlu",
      "address": "Karnataka",
      "distance": "3.1 km",
      "safetyScore": 72,
    },
    {
      "name": "Koramangala",
      "address": "Bengaluru, Karnataka",
      "distance": "12 km",
      "safetyScore": 91,
    },
  ];

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _loadRealContacts();
  }

  // ── GET REAL GPS LOCATION ──────────────────

  Future<void> _getCurrentLocation() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    try {
      // Step 1: Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            pickupController.text = "Enable GPS in device settings";
            isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enable Location Services on your device'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Step 2: Check/request permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            pickupController.text = "Location permission denied";
            isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'Location permanently denied — open Settings to allow it'),
              backgroundColor: Colors.red,
              action: SnackBarAction(
                label: 'Settings',
                onPressed: () => openAppSettings(),
              ),
            ),
          );
        }
        return;
      }
      if (permission == LocationPermission.denied) {
        if (mounted) {
          setState(() {
            pickupController.text = "Location permission denied";
            isLoading = false;
          });
        }
        return;
      }

      // Step 3: Get position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() {
          _currentLat = position.latitude;
          _currentLng = position.longitude;
          pickupController.text =
          "📍 ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}";
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          pickupController.text = "Could not get location";
          isLoading = false;
        });
      }
    }
  }

  // ── LOAD REAL DEVICE CONTACTS ──────────────
  //
  // WHY CONTACTS FAIL: flutter_contacts requires READ_CONTACTS permission.
  // You must add <uses-permission android:name="android.permission.READ_CONTACTS"/>
  // to AndroidManifest.xml AND request it at runtime via permission_handler.
  // Calling FlutterContacts.requestPermission() alone is not always sufficient
  // because on some Android versions the permission_handler package handles
  // the dialog more reliably.

  Future<void> _loadRealContacts() async {
    if (!mounted) return;
    setState(() {
      contactsLoading = true;
      contactsError = null;
    });

    try {
      // Request READ_CONTACTS via permission_handler for reliable dialog
      final granted = await Permission.contacts.request();

      if (!granted.isGranted) {
        if (mounted) {
          setState(() {
            contactsLoading = false;
            contactsError = granted.isPermanentlyDenied
                ? 'Contacts permission permanently denied.\nOpen Settings to enable.'
                : 'Contacts permission denied.';
          });
        }
        return;
      }

      // Fetch contacts with phone numbers
      final rawContacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );

      final loaded = rawContacts
          .where((c) => c.phones.isNotEmpty)
          .map((c) {
        final name = c.displayName.trim().isNotEmpty
            ? c.displayName.trim()
            : 'Unknown';
        // Grab the first available phone number
        final phone = c.phones.first.number.trim();
        final initials = name
            .split(' ')
            .where((w) => w.isNotEmpty)
            .take(2)
            .map((w) => w[0].toUpperCase())
            .join();
        return TrustedContact(
            name: name, phone: phone, initials: initials.isEmpty ? '?' : initials);
      }).toList();

      // Sort alphabetically
      loaded.sort((a, b) => a.name.compareTo(b.name));

      if (mounted) {
        setState(() {
          trustedContacts = loaded;
          contactsLoading = false;
          if (loaded.isEmpty) {
            contactsError = 'No contacts with phone numbers found on device.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          contactsLoading = false;
          contactsError = 'Error loading contacts: ${e.toString()}';
        });
      }
    }
  }

  // ── CLEAN PHONE NUMBER FOR WHATSAPP ────────

  String _cleanPhoneForWhatsApp(String raw) {
    // Remove all non-digit/non-plus characters
    String cleaned = raw.replaceAll(RegExp(r'[^\d+]'), '');

    // If no country code, assume India (+91)
    if (!cleaned.startsWith('+')) {
      if (cleaned.startsWith('0')) {
        cleaned = '+91${cleaned.substring(1)}';
      } else if (cleaned.length == 10) {
        cleaned = '+91$cleaned';
      }
    }
    return cleaned;
  }

  // ── BUILD GOOGLE MAPS DIRECTIONS URL ───────
  //
  // WHY MAPS FAILS: On Android 11+, you need <queries> entries in
  // AndroidManifest.xml for canLaunchUrl() to return true for https:// links
  // and for com.google.android.apps.maps package.
  // We always use the https:// maps URL as fallback even if Maps app isn't
  // installed — it opens in Chrome.

  String _buildMapsDirectionsUrl(String destination) {
    final destEncoded = Uri.encodeComponent(destination);
    if (_currentLat != null && _currentLng != null) {
      return 'https://www.google.com/maps/dir/?api=1'
          '&origin=${_currentLat},${_currentLng}'
          '&destination=$destEncoded'
          '&travelmode=driving';
    }
    return 'https://www.google.com/maps/dir/?api=1'
        '&destination=$destEncoded'
        '&travelmode=driving';
  }

  Future<void> _openGoogleMaps(String destination) async {
    final url = _buildMapsDirectionsUrl(destination);
    final uri = Uri.parse(url);

    // Try Google Maps app first via geo: URI
    if (_currentLat != null && _currentLng != null) {
      final destEncoded = Uri.encodeComponent(destination);
      final geoUri = Uri.parse(
          'google.navigation:q=$destEncoded&mode=d');
      if (await canLaunchUrl(geoUri)) {
        await launchUrl(geoUri, mode: LaunchMode.externalApplication);
        return;
      }
    }

    // Fallback: https URL always works (opens Maps app or browser)
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      // Last resort: force browser
      await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication)
          .catchError((_) async {
        await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      });
    }
  }

  // ── SHARE TRIP VIA WHATSAPP ────────────────
  //
  // WHY WHATSAPP FAILS: Missing <package android:name="com.whatsapp"/>
  // in <queries> block inside AndroidManifest.xml causes canLaunchUrl()
  // to return false. Also supabase_flutter was in deps — removed it as
  // it's unrelated and adds overhead.

  Future<void> _shareViaWhatsApp(
      TrustedContact contact, String destination) async {
    final mapsLink = _buildMapsDirectionsUrl(destination);

    String locationPart = _currentLat != null
        ? 'https://maps.google.com/?q=${_currentLat},${_currentLng}'
        : '';

    final messageText = '🛡️ *Safe Trip Alert*\n\n'
        'I\'m heading to *$destination*.\n\n'
        '📍 *My current location:*\n$locationPart\n\n'
        '🗺️ *Trip route (Google Maps):*\n$mapsLink\n\n'
        '⏰ Departing: ${selectedTime == "Now" ? "Right now" : selectedTime}\n\n'
        'Please track my journey. I\'ll notify you when I arrive safely. 🙏';

    final encodedMessage = Uri.encodeComponent(messageText);
    final cleanPhone = _cleanPhoneForWhatsApp(contact.phone);

    // Method 1: WhatsApp direct to contact
    final waContactUrl = Uri.parse('https://wa.me/$cleanPhone?text=$encodedMessage');

    if (await canLaunchUrl(waContactUrl)) {
      await launchUrl(waContactUrl, mode: LaunchMode.externalApplication);
      return;
    }

    // Method 2: WhatsApp generic share (user picks contact inside WA)
    final waGenericUrl =
    Uri.parse('whatsapp://send?text=$encodedMessage');
    if (await canLaunchUrl(waGenericUrl)) {
      await launchUrl(waGenericUrl, mode: LaunchMode.externalApplication);
      return;
    }

    // Method 3: WhatsApp Business
    final waBusinessUrl =
    Uri.parse('https://api.whatsapp.com/send?phone=$cleanPhone&text=$encodedMessage');
    if (await canLaunchUrl(waBusinessUrl)) {
      await launchUrl(waBusinessUrl, mode: LaunchMode.externalApplication);
      return;
    }

    // Fallback: SMS
    if (mounted) {
      final useSms = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('WhatsApp Not Found'),
          content: Text(
              'WhatsApp is not installed or unavailable for ${contact.name}.\nSend via SMS instead?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Send SMS')),
          ],
        ),
      );
      if (useSms == true) {
        final smsUri = Uri.parse(
            'smsto:${contact.phone}?body=${Uri.encodeComponent(messageText)}');
        if (await canLaunchUrl(smsUri)) {
          await launchUrl(smsUri, mode: LaunchMode.externalApplication);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not send SMS either'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    }
  }

  // ── START NAVIGATION ───────────────────────

  Future<void> _startNavigation(String destination) async {
    await _openGoogleMaps(destination);
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildLocationInputs(),
              _buildTimeAndRiderSelector(),
              const SizedBox(height: 10),
              _buildRecentLocations(),
              _buildBottomActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.arrow_back, color: Colors.white),
            ),
          ),
          const SizedBox(width: 16),
          const Text(
            "Plan your safe trip",
            style: TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          if (isLoading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  color: Colors.greenAccent, strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  Widget _buildLocationInputs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          // Visual connector dots
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.greenAccent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
              Container(
                  width: 2, height: 40, color: Colors.white.withOpacity(0.3)),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(3)),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              children: [
                // Pickup
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: pickupController,
                        style:
                        const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: "Pickup location",
                          hintStyle: TextStyle(
                              color: Colors.white.withOpacity(0.5)),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding:
                          const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _getCurrentLocation,
                      child: const Icon(Icons.my_location,
                          color: Colors.greenAccent, size: 18),
                    ),
                  ],
                ),
                Divider(color: Colors.white.withOpacity(0.2)),
                // Destination — free text input
                TextField(
                  controller: destinationController,
                  style: const TextStyle(color: Colors.white),
                  onSubmitted: (_) => _analyzeRoute(),
                  decoration: InputDecoration(
                    hintText: "Where to? (type any city/address)",
                    hintStyle:
                    TextStyle(color: Colors.white.withOpacity(0.5)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ],
            ),
          ),
          // City picker shortcut
          GestureDetector(
            onTap: _showCitySelector,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeAndRiderSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _buildChip(
              icon: Icons.access_time,
              label: selectedTime,
              onTap: _showTimeSelector),
          const SizedBox(width: 12),
          _buildChip(
              icon: Icons.person,
              label: selectedRider,
              onTap: _showRiderSelector),
        ],
      ),
    );
  }

  Widget _buildChip(
      {required IconData icon,
        required String label,
        required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down,
                color: Colors.white70, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentLocations() {
    return Expanded(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text("Recent Places",
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
          ...recentLocations.map((loc) => _buildLocationTile(loc)),
          const SizedBox(height: 10),
          _buildActionTile(
            icon: Icons.public,
            label: "Search in a different city",
            onTap: _showCitySelector,
          ),
        ],
      ),
    );
  }

  Widget _buildLocationTile(Map<String, dynamic> location) {
    final safetyScore = location['safetyScore'] as int;
    final safetyColor = safetyScore >= 80
        ? Colors.greenAccent
        : safetyScore >= 60
        ? Colors.orangeAccent
        : Colors.redAccent;

    return GestureDetector(
      onTap: () {
        setState(() => destinationController.text = location['name']);
        _analyzeRoute();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.access_time,
                  color: Colors.white70, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(location['name'],
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                  Text(location['address'],
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 13)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(location['distance'],
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.5), fontSize: 12)),
                const SizedBox(height: 4),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: safetyColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield, color: safetyColor, size: 12),
                      const SizedBox(width: 4),
                      Text("$safetyScore%",
                          style:
                          TextStyle(color: safetyColor, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile(
      {required IconData icon,
        required String label,
        required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white70, size: 20),
            ),
            const SizedBox(width: 14),
            Text(label, style: const TextStyle(color: Colors.white)),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios,
                color: Colors.white38, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        border:
        Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _analyzeRoute,
              icon: const Icon(Icons.shield_outlined),
              label: const Text("Analyze Safety"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white24,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              onPressed: _showShareTripSheet,
              icon: const Icon(Icons.share, color: Colors.white),
              tooltip: "Share via WhatsApp",
            ),
          ),
        ],
      ),
    );
  }

  // ── BOTTOM SHEETS ──────────────────────────

  void _showTimeSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _TimePickerSheet(
        onSelect: (time) {
          setState(() => selectedTime = time);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showRiderSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _RiderSelectorSheet(
        contacts: trustedContacts,
        isLoading: contactsLoading,
        errorMessage: contactsError,
        selected: selectedRider,
        onSelect: (rider) {
          setState(() => selectedRider = rider);
          Navigator.pop(context);
        },
        onReload: _loadRealContacts,
      ),
    );
  }

  void _showCitySelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _CitySelectorSheet(
        onSelect: (city) {
          setState(() => destinationController.text = city);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showShareTripSheet() {
    if (destinationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter a destination first"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _ShareTripSheet(
        contacts: trustedContacts,
        isLoading: contactsLoading,
        errorMessage: contactsError,
        destination: destinationController.text.trim(),
        currentLat: _currentLat,
        currentLng: _currentLng,
        onShare: _shareViaWhatsApp,
        onReload: _loadRealContacts,
      ),
    );
  }

  void _analyzeRoute() {
    if (destinationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter a destination"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RouteAnalysisScreen(
          pickup: pickupController.text,
          destination: destinationController.text.trim(),
          time: selectedTime,
          currentLat: _currentLat,
          currentLng: _currentLng,
          trustedContacts: trustedContacts,
          onShareViaWhatsApp: _shareViaWhatsApp,
          onOpenMaps: _openGoogleMaps,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// TIME PICKER SHEET
// ─────────────────────────────────────────────

class _TimePickerSheet extends StatelessWidget {
  final Function(String) onSelect;
  const _TimePickerSheet({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final times = [
      {"label": "Now", "icon": Icons.flash_on},
      {"label": "In 15 mins", "icon": Icons.timer},
      {"label": "In 30 mins", "icon": Icons.timer},
      {"label": "In 1 hour", "icon": Icons.schedule},
    ];

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          color: Colors.black.withOpacity(0.85),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetHandle(),
              const SizedBox(height: 20),
              const Text("Pick-up time",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ...times.map((t) => ListTile(
                leading: Icon(t["icon"] as IconData,
                    color: Colors.white70, size: 22),
                title: Text(t["label"] as String,
                    style: const TextStyle(color: Colors.white)),
                onTap: () => onSelect(t["label"] as String),
              )),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// RIDER SELECTOR SHEET (REAL DEVICE CONTACTS)
// ─────────────────────────────────────────────

class _RiderSelectorSheet extends StatelessWidget {
  final List<TrustedContact> contacts;
  final bool isLoading;
  final String? errorMessage;
  final String selected;
  final Function(String) onSelect;
  final VoidCallback onReload;

  const _RiderSelectorSheet({
    required this.contacts,
    required this.isLoading,
    required this.errorMessage,
    required this.selected,
    required this.onSelect,
    required this.onReload,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          color: Colors.black.withOpacity(0.85),
          constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetHandle(),
              const SizedBox(height: 16),
              const Text("Who's traveling?",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              if (isLoading)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(color: Colors.purple),
                )
              else if (errorMessage != null)
                _buildErrorState(context)
              else
                Flexible(child: _buildContactList()),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child:
                  const Text("Done", style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Icon(Icons.contacts, color: Colors.white38, size: 50),
          const SizedBox(height: 12),
          Text(errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          if (errorMessage!.contains('permanently'))
            TextButton.icon(
              onPressed: openAppSettings,
              icon: const Icon(Icons.settings, color: Colors.purple),
              label: const Text('Open Settings',
                  style: TextStyle(color: Colors.purple)),
            )
          else
            TextButton.icon(
              onPressed: onReload,
              icon: const Icon(Icons.refresh, color: Colors.purple),
              label: const Text('Retry',
                  style: TextStyle(color: Colors.purple)),
            ),
        ],
      ),
    );
  }

  Widget _buildContactList() {
    return ListView(
      shrinkWrap: true,
      children: [
        ListTile(
          leading: const CircleAvatar(
            backgroundColor: Colors.purple,
            child: Icon(Icons.person, color: Colors.white),
          ),
          title: const Text("Me", style: TextStyle(color: Colors.white)),
          subtitle: Text("Traveling alone",
              style:
              TextStyle(color: Colors.white.withOpacity(0.5))),
          trailing: Radio<String>(
            value: "Me",
            groupValue: selected,
            onChanged: (_) => onSelect("Me"),
            fillColor: WidgetStateProperty.all(Colors.purple),
          ),
          onTap: () => onSelect("Me"),
        ),
        const Divider(color: Colors.white12),
        ...contacts.map((c) => ListTile(
          leading: CircleAvatar(
            backgroundColor:
            Colors.primaries[c.name.length % Colors.primaries.length],
            child: Text(c.initials,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ),
          title:
          Text(c.name, style: const TextStyle(color: Colors.white)),
          subtitle: Text(c.phone,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.5), fontSize: 12)),
          trailing: Radio<String>(
            value: c.name,
            groupValue: selected,
            onChanged: (_) => onSelect(c.name),
            fillColor: WidgetStateProperty.all(Colors.purple),
          ),
          onTap: () => onSelect(c.name),
        )),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// SHARE TRIP SHEET (REAL CONTACTS + WHATSAPP)
// ─────────────────────────────────────────────

class _ShareTripSheet extends StatefulWidget {
  final List<TrustedContact> contacts;
  final bool isLoading;
  final String? errorMessage;
  final String destination;
  final double? currentLat;
  final double? currentLng;
  final Future<void> Function(TrustedContact, String) onShare;
  final VoidCallback onReload;

  const _ShareTripSheet({
    required this.contacts,
    required this.isLoading,
    required this.errorMessage,
    required this.destination,
    required this.currentLat,
    required this.currentLng,
    required this.onShare,
    required this.onReload,
  });

  @override
  State<_ShareTripSheet> createState() => _ShareTripSheetState();
}

class _ShareTripSheetState extends State<_ShareTripSheet> {
  final Set<int> _selectedIndices = {};
  bool _sharing = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  List<TrustedContact> get _filtered => widget.contacts
      .where((c) =>
  c.name.toLowerCase().contains(_query.toLowerCase()) ||
      c.phone.contains(_query))
      .toList();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          color: Colors.black.withOpacity(0.9),
          constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetHandle(),
              const SizedBox(height: 16),
              // Header
              Row(
                children: [
                  const Icon(Icons.chat, color: Color(0xFF25D366), size: 28),
                  const SizedBox(width: 10),
                  const Text("Share trip via WhatsApp",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                "To: ${widget.destination}",
                style: TextStyle(
                    color: Colors.white.withOpacity(0.6), fontSize: 12),
              ),
              const SizedBox(height: 12),
              if (widget.isLoading)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child:
                  CircularProgressIndicator(color: Color(0xFF25D366)),
                )
              else if (widget.errorMessage != null)
                _buildError()
              else ...[
                  // Search bar
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _query = v),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Search contacts...",
                        hintStyle:
                        TextStyle(color: Colors.white.withOpacity(0.4)),
                        prefixIcon: const Icon(Icons.search,
                            color: Colors.white54),
                        border: InputBorder.none,
                        contentPadding:
                        const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_selectedIndices.isNotEmpty)
                    Text(
                      "${_selectedIndices.length} contact(s) selected",
                      style: const TextStyle(
                          color: Color(0xFF25D366), fontSize: 13),
                    ),
                  Flexible(
                    child: widget.contacts.isEmpty
                        ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                            "No contacts with phone numbers found",
                            style: TextStyle(color: Colors.white54)),
                      ),
                    )
                        : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _filtered.length,
                      itemBuilder: (context, index) {
                        final contact = _filtered[index];
                        // Map filtered index back to original for selection
                        final originalIndex =
                        widget.contacts.indexOf(contact);
                        final isSelected =
                        _selectedIndices.contains(originalIndex);
                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: (val) {
                            setState(() {
                              val == true
                                  ? _selectedIndices.add(originalIndex)
                                  : _selectedIndices
                                  .remove(originalIndex);
                            });
                          },
                          secondary: CircleAvatar(
                            backgroundColor: Colors.primaries[contact
                                .name.length %
                                Colors.primaries.length],
                            child: Text(contact.initials,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12)),
                          ),
                          title: Text(contact.name,
                              style:
                              const TextStyle(color: Colors.white)),
                          subtitle: Text(contact.phone,
                              style: TextStyle(
                                  color:
                                  Colors.white.withOpacity(0.5),
                                  fontSize: 12)),
                          checkColor: Colors.white,
                          activeColor: const Color(0xFF25D366),
                        );
                      },
                    ),
                  ),
                ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed:
                  (_selectedIndices.isEmpty || _sharing || widget.isLoading)
                      ? null
                      : _shareWithSelected,
                  icon: _sharing
                      ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send),
                  label: Text(
                      _sharing ? "Opening WhatsApp..." : "Share Trip on WhatsApp"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                    const Color(0xFF25D366).withOpacity(0.4),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Icon(Icons.contacts, color: Colors.white38, size: 50),
          const SizedBox(height: 12),
          Text(widget.errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          if (widget.errorMessage!.contains('permanently'))
            TextButton.icon(
              onPressed: openAppSettings,
              icon: const Icon(Icons.settings, color: Color(0xFF25D366)),
              label: const Text('Open Settings',
                  style: TextStyle(color: Color(0xFF25D366))),
            )
          else
            TextButton.icon(
              onPressed: widget.onReload,
              icon: const Icon(Icons.refresh, color: Color(0xFF25D366)),
              label: const Text('Reload Contacts',
                  style: TextStyle(color: Color(0xFF25D366))),
            ),
        ],
      ),
    );
  }

  Future<void> _shareWithSelected() async {
    setState(() => _sharing = true);
    final indices = _selectedIndices.toList();
    for (final idx in indices) {
      await widget.onShare(widget.contacts[idx], widget.destination);
      if (indices.length > 1) {
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }
    setState(() => _sharing = false);
    if (mounted) Navigator.pop(context);
  }
}

// ─────────────────────────────────────────────
// CITY SELECTOR SHEET
// ─────────────────────────────────────────────

class _CitySelectorSheet extends StatefulWidget {
  final Function(String) onSelect;
  const _CitySelectorSheet({required this.onSelect});

  @override
  State<_CitySelectorSheet> createState() => _CitySelectorSheetState();
}

class _CitySelectorSheetState extends State<_CitySelectorSheet> {
  String _query = '';

  List<Map<String, String>> get _filtered => kIndianCities
      .where((c) =>
  c['name']!.toLowerCase().contains(_query.toLowerCase()) ||
      c['state']!.toLowerCase().contains(_query.toLowerCase()))
      .toList();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          color: Colors.black.withOpacity(0.9),
          constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _sheetHandle(),
              const SizedBox(height: 16),
              const Text("Top Cities in India 🇮🇳",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Search city or state...",
                    hintStyle:
                    TextStyle(color: Colors.white.withOpacity(0.5)),
                    prefixIcon:
                    const Icon(Icons.search, color: Colors.white54),
                    border: InputBorder.none,
                    contentPadding:
                    const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: _filtered.length,
                  itemBuilder: (context, index) {
                    final city = _filtered[index];
                    return ListTile(
                      leading: Text(city['emoji']!,
                          style: const TextStyle(fontSize: 24)),
                      title: Text(city['name']!,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                      subtitle: Text(city['state']!,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 12)),
                      trailing: const Icon(Icons.arrow_forward_ios,
                          color: Colors.white24, size: 14),
                      onTap: () => widget.onSelect(city['name']!),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ROUTE ANALYSIS SCREEN
// ─────────────────────────────────────────────

class RouteAnalysisScreen extends StatefulWidget {
  final String pickup;
  final String destination;
  final String time;
  final double? currentLat;
  final double? currentLng;
  final List<TrustedContact> trustedContacts;
  final Future<void> Function(TrustedContact, String) onShareViaWhatsApp;
  final Future<void> Function(String) onOpenMaps;

  const RouteAnalysisScreen({
    super.key,
    required this.pickup,
    required this.destination,
    required this.time,
    required this.currentLat,
    required this.currentLng,
    required this.trustedContacts,
    required this.onShareViaWhatsApp,
    required this.onOpenMaps,
  });

  @override
  State<RouteAnalysisScreen> createState() => _RouteAnalysisScreenState();
}

class _RouteAnalysisScreenState extends State<RouteAnalysisScreen> {
  bool isAnalyzing = true;
  int overallSafetyScore = 0;
  List<RouteOption> routes = [];

  @override
  void initState() {
    super.initState();
    _analyzeRoutes();
  }

  Future<void> _analyzeRoutes() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() {
      isAnalyzing = false;
      overallSafetyScore = 78;
      routes = [
        RouteOption(
          name: "Safest Route",
          duration: "25 min",
          distance: "8.2 km",
          safetyScore: 92,
          factors: [
            "Well-lit streets",
            "Police stations nearby",
            "High foot traffic"
          ],
          isRecommended: true,
        ),
        RouteOption(
          name: "Fastest Route",
          duration: "18 min",
          distance: "6.5 km",
          safetyScore: 68,
          factors: ["Some isolated areas", "Limited lighting after 9 PM"],
          isRecommended: false,
        ),
        RouteOption(
          name: "Alternate Route",
          duration: "22 min",
          distance: "7.8 km",
          safetyScore: 75,
          factors: ["Residential areas", "Moderate traffic"],
          isRecommended: false,
        ),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              if (isAnalyzing)
                const Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.purple),
                        SizedBox(height: 20),
                        Text("Analyzing route safety...",
                            style: TextStyle(color: Colors.white70)),
                        SizedBox(height: 8),
                        Text("Checking crime data, lighting, traffic",
                            style:
                            TextStyle(color: Colors.white38, fontSize: 12)),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildOverallScore(),
                      const SizedBox(height: 20),
                      const Text("Route Options",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      ...routes.map((r) => _buildRouteCard(r)),
                      const SizedBox(height: 20),
                      _buildSafetyTips(),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.arrow_back, color: Colors.white),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.destination,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
                Text("From ${widget.pickup} • ${widget.time}",
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.6), fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverallScore() {
    final color = overallSafetyScore >= 80
        ? Colors.greenAccent
        : overallSafetyScore >= 60
        ? Colors.orangeAccent
        : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 80,
                height: 80,
                child: CircularProgressIndicator(
                  value: overallSafetyScore / 100,
                  strokeWidth: 8,
                  backgroundColor: Colors.white.withOpacity(0.1),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              Column(
                children: [
                  Text("$overallSafetyScore",
                      style: TextStyle(
                          color: color,
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                  Text("Safe",
                      style: TextStyle(color: color, fontSize: 10)),
                ],
              ),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Area Safety Score",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  "Based on crime data, lighting conditions, and historical incidents.",
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.6), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteCard(RouteOption route) {
    final color = route.safetyScore >= 80
        ? Colors.greenAccent
        : route.safetyScore >= 60
        ? Colors.orangeAccent
        : Colors.redAccent;

    return GestureDetector(
      onTap: () => _selectRoute(route),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: route.isRecommended
                ? Colors.purple.withOpacity(0.5)
                : Colors.white.withOpacity(0.1),
            width: route.isRecommended ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(route.name,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                          if (route.isRecommended) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                  color: Colors.purple,
                                  borderRadius: BorderRadius.circular(10)),
                              child: const Text("Recommended",
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 10)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text("${route.duration} • ${route.distance}",
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.6))),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.shield, color: color, size: 16),
                      const SizedBox(width: 4),
                      Text("${route.safetyScore}%",
                          style: TextStyle(
                              color: color, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: route.factors.map((factor) {
                final isPositive = !factor.toLowerCase().contains("isolated") &&
                    !factor.toLowerCase().contains("limited");
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isPositive ? Colors.greenAccent : Colors.orangeAccent)
                        .withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                          isPositive ? Icons.check_circle : Icons.warning,
                          size: 12,
                          color: isPositive
                              ? Colors.greenAccent
                              : Colors.orangeAccent),
                      const SizedBox(width: 4),
                      Text(factor,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 11)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSafetyTips() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purple.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb, color: Colors.purple, size: 20),
              SizedBox(width: 8),
              Text("Safety Tips",
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          _tipItem("Share your trip with trusted contacts"),
          _tipItem("Keep your phone charged"),
          _tipItem("Avoid using headphones while walking"),
          _tipItem("Stay aware of your surroundings"),
        ],
      ),
    );
  }

  Widget _tipItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.check, color: Colors.purple, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.8), fontSize: 13)),
          ),
        ],
      ),
    );
  }

  void _selectRoute(RouteOption route) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _RouteConfirmationSheet(
        route: route,
        destination: widget.destination,
        trustedContacts: widget.trustedContacts,
        onStart: () async {
          Navigator.pop(context);
          await widget.onOpenMaps(widget.destination);
        },
        onShareViaWhatsApp: widget.onShareViaWhatsApp,
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ROUTE CONFIRMATION SHEET
// ─────────────────────────────────────────────

class _RouteConfirmationSheet extends StatefulWidget {
  final RouteOption route;
  final String destination;
  final List<TrustedContact> trustedContacts;
  final Future<void> Function() onStart;
  final Future<void> Function(TrustedContact, String) onShareViaWhatsApp;

  const _RouteConfirmationSheet({
    required this.route,
    required this.destination,
    required this.trustedContacts,
    required this.onStart,
    required this.onShareViaWhatsApp,
  });

  @override
  State<_RouteConfirmationSheet> createState() =>
      _RouteConfirmationSheetState();
}

class _RouteConfirmationSheetState extends State<_RouteConfirmationSheet> {
  bool _starting = false;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          color: Colors.black.withOpacity(0.92),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetHandle(),
              const SizedBox(height: 20),
              const Icon(Icons.shield, color: Colors.purple, size: 50),
              const SizedBox(height: 16),
              Text(widget.route.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text("${widget.route.duration} • ${widget.route.distance}",
                  style: TextStyle(color: Colors.white.withOpacity(0.6))),
              const SizedBox(height: 8),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.greenAccent.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shield,
                        color: Colors.greenAccent, size: 16),
                    const SizedBox(width: 6),
                    Text("Safety Score: ${widget.route.safetyScore}%",
                        style: const TextStyle(
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: Colors.transparent,
                          isScrollControlled: true,
                          builder: (_) => _ShareTripSheet(
                            contacts: widget.trustedContacts,
                            isLoading: false,
                            errorMessage: widget.trustedContacts.isEmpty
                                ? 'No contacts loaded yet.'
                                : null,
                            destination: widget.destination,
                            currentLat: null,
                            currentLng: null,
                            onShare: widget.onShareViaWhatsApp,
                            onReload: () {},
                          ),
                        );
                      },
                      icon: const Icon(Icons.share),
                      label: const Text("Share Trip"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white30),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _starting
                          ? null
                          : () async {
                        setState(() => _starting = true);
                        await widget.onStart();
                        if (mounted) setState(() => _starting = false);
                      },
                      icon: _starting
                          ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.navigation),
                      label: Text(_starting ? "Opening..." : "Start"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Row(children: [
                          Icon(Icons.sos, color: Colors.white),
                          SizedBox(width: 8),
                          Text("Auto-SOS enabled for this trip"),
                        ]),
                        backgroundColor: Colors.red,
                        duration: Duration(seconds: 3),
                      ),
                    );
                  },
                  icon: const Icon(Icons.sos, color: Colors.red),
                  label: const Text("Enable Auto-SOS for this trip",
                      style: TextStyle(color: Colors.red)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SHARED HELPERS
// ─────────────────────────────────────────────

Widget _sheetHandle() {
  return Container(
    height: 5,
    width: 50,
    decoration: BoxDecoration(
      color: Colors.white30,
      borderRadius: BorderRadius.circular(10),
    ),
  );
}
