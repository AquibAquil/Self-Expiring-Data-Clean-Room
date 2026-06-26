import 'package:flutter/material.dart';

import 'gate_screen.dart';
import 'theme.dart';

void main() {
  runApp(const SelfExpiringDataCleanRoomApp());
}

class SelfExpiringDataCleanRoomApp extends StatelessWidget {
  const SelfExpiringDataCleanRoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Self-Expiring Data Clean Room',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const AtsignGateScreen(),
    );
  }
}
