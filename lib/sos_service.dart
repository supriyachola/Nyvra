import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

class SOSService {
  final List<String> trustedContacts = [
    "9876543210",
    "9123456780",
  ];

  final String policeNumber = "112";

  Future<void> triggerSOS() async {
    // Permission
    LocationPermission permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    // Location
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    String locationLink =
        "https://maps.google.com/?q=${position.latitude},${position.longitude}";

    String message =
        "🚨 EMERGENCY!\nI need help.\nMy location:\n$locationLink";

    // SMS
    String numbers = trustedContacts.join(",");
    await launchUrl(Uri.parse("smsto:$numbers?body=${Uri.encodeComponent(message)}"));

    // Call police
    await launchUrl(Uri.parse("tel:$policeNumber"));

    // WhatsApp
    await launchUrl(
      Uri.parse("https://wa.me/?text=${Uri.encodeComponent(message)}"),
      mode: LaunchMode.externalApplication,
    );
  }
}