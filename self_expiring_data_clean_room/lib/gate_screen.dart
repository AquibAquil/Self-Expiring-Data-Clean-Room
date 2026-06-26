import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'welcome_screen.dart';

/// MANDATORY First-Run Atsign Gate.
///
/// Shown on first launch if KeychainStorage().getAllAtsigns() returns empty.
/// Blocks all auth/onboarding/main UI until the user confirms they have an
/// Atsign (or opens the Starter Pack page and gets one).
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
        // Already have at least one Atsign on this device — skip the gate.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        );
        return;
      }
    } catch (_) {
      // Fall through to the gate UI on any keychain error.
    }
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
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Using this app requires an Atsign.',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'If you already have an Atsign, click "Continue."',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Or, get free, temporary Atsigns via the Starter Pack:',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 12),
                  const _StepLine('1.', 'Click "Get My Starter Pack" below or visit https://my.atsign.com/starterpack_app in your browser.'),
                  const _StepLine('2.', 'Enter your email address.'),
                  const _StepLine('3.', 'Verify your email with a one-time passcode.'),
                  const _StepLine('4.', 'Come back to the app and click "Continue."'),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _openStarterPack,
                          icon: const Icon(Icons.open_in_new),
                          label: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Text('Get My Starter Pack'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _continue,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Text('Continue'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine(this.num, this.text);
  final String num;
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 24, child: Text(num, style: Theme.of(context).textTheme.bodyLarge)),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
