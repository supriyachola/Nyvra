import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

class SOSService {
  final List<String> trustedContacts = [
    "9876543210",
    "9123456780",
  ];

  final String policeNumber = "112";

  Future<void> triggerSOS() async {
    // ── Step 1: Check location permission ──
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      // Still try to send SOS without location
      await _sendSOSAlerts("Location unavailable");
      return;
    }

    // ── Step 2: Get position ──
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final locationLink =
          "https://maps.google.com/?q=${position.latitude},${position.longitude}";
      await _sendSOSAlerts(locationLink);
    } catch (_) {
      await _sendSOSAlerts("Location unavailable");
    }
  }

  Future<void> _sendSOSAlerts(String locationInfo) async {
    final message =
        "🚨 EMERGENCY!\nI need help.\nMy location:\n$locationInfo";
    final encodedMsg = Uri.encodeComponent(message);

    // ── SMS to trusted contacts ──
    final numbers = trustedContacts.join(",");
    final smsUri = Uri.parse("smsto:$numbers?body=$encodedMsg");
    if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri, mode: LaunchMode.externalApplication);
    }

    // ── Call police ──
    final callUri = Uri.parse("tel:$policeNumber");
    if (await canLaunchUrl(callUri)) {
      await launchUrl(callUri, mode: LaunchMode.externalApplication);
    }

    // ── WhatsApp broadcast ──
    final waUri = Uri.parse("whatsapp://send?text=$encodedMsg");
    if (await canLaunchUrl(waUri)) {
      await launchUrl(waUri, mode: LaunchMode.externalApplication);
    } else {
      // Fallback: wa.me share link
      final waFallback =
      Uri.parse("https://wa.me/?text=$encodedMsg");
      if (await canLaunchUrl(waFallback)) {
        await launchUrl(waFallback, mode: LaunchMode.externalApplication);
      }
    }
  }
}
