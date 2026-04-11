import 'package:flutter/material.dart';
import 'sos_controller.dart';

class SOSScreen extends StatefulWidget {
  const SOSScreen({super.key});

  @override
  State<SOSScreen> createState() => _SOSScreenState();
}

class _SOSScreenState extends State<SOSScreen> {
  final controller = SOSController();

  @override
  void initState() {
    super.initState();
    controller.startSOS();
  }

  @override
  void dispose() {
    controller.disposeController();
    super.dispose();
  }

  Widget statusItem(String text, bool done) {
    return ListTile(
      leading: const Icon(Icons.circle, color: Colors.white),
      title: Text(text, style: const TextStyle(color: Colors.white)),
      trailing: Icon(
        done ? Icons.check_circle : Icons.radio_button_unchecked,
        color: done ? Colors.greenAccent : Colors.white,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Colors.red.shade700,
          body: SafeArea(
            child: Column(
              children: [

                const SizedBox(height: 20),

                const Text(
                  "SOS",
                  style: TextStyle(
                    fontSize: 28,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 20),

                statusItem("Contacting control center", controller.contacted),
                statusItem("Sending alert to contacts", controller.sent),
                statusItem("Live location tracking", controller.tracking),
                statusItem("Audio & Video recording", controller.recording),

                const SizedBox(height: 30),

                Container(
                  padding: const EdgeInsets.all(15),
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.red.shade400,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Text(
                    "Help is on the way!",
                    style: TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),

                const SizedBox(height: 20),

                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.red.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    controller.locationText,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),

                const Spacer(),

                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: Colors.white)),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}