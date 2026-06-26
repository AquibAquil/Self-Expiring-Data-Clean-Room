import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';
import 'welcome_screen.dart';

/// MANDATORY first-run Atsign gate. Blocks every other screen until the user
/// confirms they have (or will get) an Atsign.
class AtsignGateScreen extends StatefulWidget {
  const AtsignGateScreen({super.key});

  @override
  State<AtsignGateScreen> createState() => _AtsignGateScreenState();
}

class _AtsignGateScreenState extends State<AtsignGateScreen> {
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkExistingAtsigns();
  }

  Future<void> _checkExistingAtsigns() async {
    try {
      final existing = await KeychainStorage().getAllAtsigns();
      if (existing.isNotEmpty) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        );
        return;
      }
    } catch (_) {/* fall through to the gate UI on any keychain error */}
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _openStarterPack() async {
    final uri = Uri.parse('https://my.atsign.com/starterpack_app');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open browser. Visit my.atsign.com/starterpack_app manually.')),
        );
      }
    }
  }

  void _continue() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.shield_outlined, color: AppColors.primary, size: 38),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Using this app requires an Atsign',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'An Atsign is your private cryptographic identity. We use it to prove '
                    'who you are when you confirm or read analysis results. No personal '
                    'data is sent — your private key never leaves your device.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const _Step(num: '1', text: 'Click "Get My Starter Pack" below'),
                  const _Step(num: '2', text: 'Enter your email address'),
                  const _Step(num: '3', text: 'Verify your email with a one-time passcode'),
                  const _Step(num: '4', text: 'Come back here and click "Continue"'),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: _openStarterPack,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Get My Starter Pack'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(onPressed: _continue, child: const Text('Continue')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.num, required this.text});
  final String num;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              num,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14.5, color: AppColors.textPrimary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
