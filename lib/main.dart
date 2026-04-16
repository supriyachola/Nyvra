import 'dart:async';
import 'sos_service.dart' show SOSService;
import 'sos_screen.dart';
import 'chatbot_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:ui';
import 'trip_planning_screen.dart';
void main() {
  runApp(const SafetyApp());
}

class SafetyApp extends StatelessWidget {
  const SafetyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const MainScreen(),
    );
  }
}

//////////////////////////////////////////////////////
// MAIN SCREEN
//////////////////////////////////////////////////////

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int selectedIndex = 0;

  final List<Widget> pages = [
    const HomePage(),
    const MapPage(),
    const ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: (index) {
          setState(() => selectedIndex = index);
        },
        selectedItemColor: Colors.purple,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: "Map"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }
}


//////////////////////////////////////////////////////
// 🔵 GRADIENT WIDGET (REUSABLE)
//////////////////////////////////////////////////////

Widget gradientBackground({required Widget child}) {
  return Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Color(0xFF0F2027),
          Color(0xFF203A43),
          Color(0xFF2C5364),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: child,
  );
}

//////////////////////////////////////////////////////
// HOME PAGE
//////////////////////////////////////////////////////

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String result = "";
  final sosService = SOSService();

  int countdown = 5;
  bool isCounting = false;
  bool cancelSOS = false;

  void predictSafety() {
    setState(() {
      result = " Safe Area";
    });
  }


  //////////////////////////////////////////////////////
  // 🔥 FIXED COUNTDOWN
  //////////////////////////////////////////////////////

  Future<void> startCountdown() async {
    setState(() {
      isCounting = true;
      countdown = 5;
      cancelSOS = false;
    });

    for (int i = 5; i > 0; i--) {
      await Future.delayed(const Duration(seconds: 1));

      if (cancelSOS) {
        setState(() => isCounting = false);
        return;
      }

      setState(() => countdown = i - 1);
    }

    setState(() => isCounting = false);

    // 🚨 OPEN SOS SCREEN AFTER COUNTDOWN
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SOSScreen()),
      );
    }
  }

  //////////////////////////////////////////////////////
  // UI
  //////////////////////////////////////////////////////

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          //////////////////////////////////////////////////////
          // 🔵 MAIN UI
          //////////////////////////////////////////////////////
          gradientBackground(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),

                    //////////////////////////////////////////////////////
                    // HEADER
                    //////////////////////////////////////////////////////
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Column( //  FIXED
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [

                          // HEADER
                          Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.asset(
                                  "assets/images/logo.png",
                                  height: 32,
                                  width: 32,
                                  fit: BoxFit.cover,
                                ),
                              ),

                              const SizedBox(width: 10),

                              const Text(
                                "Nyvra",
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 6),

                          // SUBTITLE
                          const Text(
                            "Your safety companion",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),

                          const SizedBox(height: 25),
                        ],
                      ),
                    ),
                    const SizedBox(height: 25),
                    //////////////////////////////////////////////////////
                    // INPUT BOX
                    //////////////////////////////////////////////////////
                    //////////////////////////////////////////////////////
// INPUT BOX
//////////////////////////////////////////////////////
                    ClipRRect(
                      borderRadius: BorderRadius.circular(25),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(25),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                            ),
                          ),
                          child: Column(
                            children: [

                              const Text(
                                "Plan your trip safely",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),

                              const SizedBox(height: 20),

                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const TripPlanningScreen(),
                                      ),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white24,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 30, vertical: 15),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.directions, color: Colors.white),
                                      SizedBox(width: 10),
                                      Text(
                                        "Plan Safe Trip",
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),


                    const SizedBox(height: 20), // 🔥 VERY IMPORTANT

                    //////////////////////////////////////////////////////
                    // RESULT
                    //////////////////////////////////////////////////////
                        // RESULT
                        if (result.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text(result),
                    ),

// COUNTDOWN
                    if (isCounting)
                      Center(
                        child: Column(
                          children: [
                            const SizedBox(height: 20),
                            Text(
                              "Sending SOS in $countdown...",
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  cancelSOS = true;
                                });
                              },
                              child: const Text("Cancel SOS"),
                            ),
                          ],
                        ),
                      ),

                    const Spacer(),

// SOS BUTTON
                    Center(
                      child: ElevatedButton(
                        onPressed: () async {
                          bool confirm = await showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text("Emergency SOS"),
                              content: const Text("SOS will be sent in 5 seconds"),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text("Cancel"),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text("Start"),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            startCountdown();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 40, vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        child: const Text(
                          "SOS",
                          style: TextStyle(fontSize: 18, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          //////////////////////////////////////////////////////
          // 💬 FLOATING CHAT BOT (FINAL FIX)
          //////////////////////////////////////////////////////
          Positioned(
            bottom: 20,
            right: 20,
            child: _FloatingChatBot(),
          ),
        ],
      ),
    );
  }
}

class _FloatingChatBot extends StatefulWidget {
  @override
  State<_FloatingChatBot> createState() => _FloatingChatBotState();
}

class _FloatingChatBotState extends State<_FloatingChatBot>
    with SingleTickerProviderStateMixin {

  late AnimationController controller;
  late Animation<double> animation;

  @override
  void initState() {
    super.initState();

    controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    animation = Tween<double>(begin: 0, end: -10).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, animation.value),
          child: GestureDetector(
            onTap: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const ChatBotUI(),
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.purple.withOpacity(0.3),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.chat_bubble_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}


//////////////////////////////////////////////////////
// 🔥 ADD THIS BELOW (OUTSIDE ALL CLASSES)
//////////////////////////////////////////////////////

Widget _glassField(IconData icon, String hint) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.08),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Row(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white54),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    ),
  );
}

//////////////////////////////////////////////////////
// MAP PAGE
//////////////////////////////////////////////////////

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  LatLng currentLocation = LatLng(12.9716, 77.5946);
  StreamSubscription<Position>? positionStream;

  @override
  void initState() {
    super.initState();
    startTracking();
  }

  void startTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }

    LocationPermission permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      print("Location permission denied");
      return;
    }

    positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
      ),
    ).listen((Position position) {
      print("Lat: ${position.latitude}, Lng: ${position.longitude}");

      if (!mounted) return;

      setState(() {
        currentLocation =
            LatLng(position.latitude, position.longitude);
      });
    });
  }

  @override
  void dispose() {
    positionStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FlutterMap(
        options: MapOptions(
          initialCenter: currentLocation,
          initialZoom: 15,
        ),
        children: [
          TileLayer(
            urlTemplate:
            "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
            userAgentPackageName: 'com.example.my_acp',
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: currentLocation,
                width: 50,
                height: 50,
                child: const Icon(Icons.location_on,
                    size: 40, color: Colors.red),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

//////////////////////////////////////////////////////
// PROFILE PAGE
//////////////////////////////////////////////////////

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: gradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: const [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.white,
                        child: Icon(Icons.person, size: 30),
                      ),
                      SizedBox(width: 15),
                      Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Text("Supriya",
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                          Text("@email.com",
                              style:
                              TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 25),
                Row(
                  children: [
                    Expanded(child: _infoCard("Trips", "12")),
                    const SizedBox(width: 10),
                    Expanded(child: _infoCard("Safe Checks", "45")),
                  ],
                ),
                const SizedBox(height: 25),
                _menuItem(Icons.history, "Travel History"),
                _menuItem(Icons.group, "Trusted Contacts"),
                _menuItem(Icons.notifications, "Notifications"),
                _menuItem(Icons.settings, "Settings"),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.logout),
                    label: const Text("Logout"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding:
                      const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                          BorderRadius.circular(15)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoCard(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          Text(title,
              style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _menuItem(IconData icon, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.purple),
          const SizedBox(width: 15),
          Text(text),
          const Spacer(),
          const Icon(Icons.arrow_forward_ios, size: 16),
        ],
      ),
    );
  }
}