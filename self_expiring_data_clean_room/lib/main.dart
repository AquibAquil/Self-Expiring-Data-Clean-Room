import 'package:flutter/material.dart';

import 'gate_screen.dart';

void main() {
  runApp(const SelfExpiringDataCleanRoomApp());
}

class SelfExpiringDataCleanRoomApp extends StatelessWidget {
  const SelfExpiringDataCleanRoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Self-Expiring Data Clean Room',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const AtsignGateScreen(),
    );
  }
}
