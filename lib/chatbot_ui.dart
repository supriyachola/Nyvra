import 'dart:ui';
import 'package:flutter/material.dart';

class ChatBotUI extends StatefulWidget {
  const ChatBotUI({super.key});

  @override
  State<ChatBotUI> createState() => _ChatBotUIState();
}

class _ChatBotUIState extends State<ChatBotUI> {
  final TextEditingController controller = TextEditingController();

  List<Map<String, String>> messages = [
    {
      "role": "bot",
      "text": "Hi I'm your Nyvra AI Safety Assistant.\nAsk me anything!"
    }
  ];

  //////////////////////////////////////////////////////
  // 🔥 FAQ QUICK BUTTONS
  //////////////////////////////////////////////////////
  final List<String> faqs = [
    "What to do in danger?",
    "Is this area safe?",
    "Nearest police station",
    "Safe route at night",
  ];

  //////////////////////////////////////////////////////
  // SEND MESSAGE
  //////////////////////////////////////////////////////
  void sendMessage(String text) {
    if (text.isEmpty) return;

    setState(() {
      messages.add({"role": "user", "text": text});
    });

    controller.clear();

    Future.delayed(const Duration(milliseconds: 400), () async {
      String reply = await getBotResponse(text);

      setState(() {
        messages.add({"role": "bot", "text": reply});
      });
    });
  }

  //////////////////////////////////////////////////////
  // 🤖 SMART RESPONSE (LLM READY)
  //////////////////////////////////////////////////////
  String? lastIntent;

  Future<String> getBotResponse(String msg) async {
    msg = msg.toLowerCase();

    await Future.delayed(const Duration(milliseconds: 500)); // 🤖 thinking

    String intent = "unknown";

    if (msg.contains("safe")) {
      intent = "safe";
    } else if (msg.contains("police")) {
      intent = "police";
    } else if (msg.contains("danger")) {
      intent = "danger";
    } else if (msg.contains("route")) {
      intent = "route";
    }

    lastIntent = intent;

    switch (intent) {
      case "safe":
        return _random([
          "This area looks moderately safe. Stay alert.",
          "Seems safe, but avoid isolated roads.",
          "You're relatively safe, but stay aware."
        ]);

      case "police":
        return _random([
          "Nearest police station is within ~2km.",
          "Police help is nearby. Use SOS if urgent.",
          "Call 112 if immediate assistance is needed."
        ]);

      case "danger":
        return _random([
          " Stay calm. Move to a crowded place.",
          "Avoid confrontation and call 112.",
          "Share your live location immediately."
        ]);

      case "route":
        return _random([
          "Use well-lit main roads.",
          "Avoid shortcuts at night.",
          "Stick to populated routes."
        ]);

      default:
        return "I'm here to help you!! ";
    }
  }

//////////////////////////////////////////////////////
// 🔥 RANDOM RESPONSE
//////////////////////////////////////////////////////
  String _random(List<String> list) {
    list.shuffle();
    return list.first;
  }

  //////////////////////////////////////////////////////
  // UI
  //////////////////////////////////////////////////////
  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.8,
          color: Colors.black.withOpacity(0.6),
          child: Column(
            children: [

              //////////////////////////////////////////////////////
              // HEADER
              //////////////////////////////////////////////////////
              const SizedBox(height: 10),

              Container(
                height: 5,
                width: 50,
                decoration: BoxDecoration(
                  color: Colors.white30,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              const SizedBox(height: 15),

              const Text(
                "Nyvra Assistant ",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const Divider(color: Colors.white24),

              //////////////////////////////////////////////////////
              // 🔥 FAQ BUTTONS
              //////////////////////////////////////////////////////
              SizedBox(
                height: 45,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: faqs.length,
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () => sendMessage(faqs[index]),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 15, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          faqs[index],
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 10),

              //////////////////////////////////////////////////////
              // MESSAGES
              //////////////////////////////////////////////////////
              Expanded(
                child: ListView.builder(
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    bool isUser = msg["role"] == "user";

                    return Container(
                      alignment: isUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      padding: const EdgeInsets.all(10),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isUser
                              ? Colors.blueAccent.withOpacity(0.7)
                              : Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Text(
                          msg["text"]!,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    );
                  },
                ),
              ),

              //////////////////////////////////////////////////////
              // INPUT
              //////////////////////////////////////////////////////
              Container(
                padding: const EdgeInsets.all(10),
                color: Colors.black.withOpacity(0.6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: "Ask about safety...",
                          hintStyle: TextStyle(color: Colors.white54),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send,
                          color: Colors.blueAccent),
                      onPressed: () => sendMessage(controller.text),
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
        ));
  }
}