import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_client_flutter/extensions.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart' show getApplicationSupportDirectory;

import 'home_screen.dart';
import 'theme.dart';

const String kNamespace = 'cleanroom';
const String kAppName = 'SelfExpiringDataCleanRoom';
const String kDeviceName = 'flutter';
const String kRegistrarUrl = String.fromEnvironment(
  'REGISTRAR_URL',
  defaultValue: 'my.atsign.com',
);

// Injected at build time: pass --dart-define=REGISTRAR_API_KEY=... for a real
// deployment. Default is Atsign's public sample key from the at_client_flutter
// walkthrough — fine for local demos, not for anything you ship.
const String kRegistrarApiKey = String.fromEnvironment(
  'REGISTRAR_API_KEY',
  defaultValue: '5f93a2fa-2e3b-4332-9924-c29cc6e164ba',
);

/// Welcome / Auth screen — supports all four standard workflows.
/// Modeled on the at_client_flutter 1.1.3 example walkthrough.dart.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _busy = false;
  String? _error;

  final KeychainStorage _keychain = KeychainStorage();
  final RegistrarService _registrar = RegistrarService(
    registrarUrl: kRegistrarUrl,
    apiKey: kRegistrarApiKey,
  );

  Future<void> _setupAtClient(AtAuthRequest authRequest, AuthResponse response) async {
    final dir = await getApplicationSupportDirectory();
    final acp = AtClientPreference()
      ..rootDomain = authRequest.rootDomain.rootDomain
      ..rootPort = authRequest.rootDomain.rootPort
      ..namespace = kNamespace
      ..commitLogPath = dir.path
      ..hiveStoragePath = dir.path;

    await AtClientManager.getInstance().setCurrentAtSign(
      response.atSign,
      kNamespace,
      acp,
      enrollmentId: response.enrollmentId,
      atChops: response.atChops,
      atLookUp: response.atLookUp,
    );

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomeScreen(atSign: response.atSign)),
    );
  }

  Future<void> _loginKeychain() async {
    setState(() { _busy = true; _error = null; });
    try {
      final atSigns = await _keychain.getAllAtsigns();
      if (atSigns.isEmpty) {
        setState(() => _error = 'No atSigns in keychain. Onboard first.');
        return;
      }
      if (!mounted) return;
      final request = await AtSignSelectionDialog.show(context, existingAtSigns: atSigns);
      if (request == null) return;
      final authRequest = AtAuthRequest(
        request.atSign,
        atKeysIo: KeychainAtKeysIo(),
        rootDomain: request.rootDomain,
      );
      if (!mounted) return;
      final response = await PkamDialog.show(
        context,
        request: authRequest,
        backupKeys: [KeychainAtKeysIo()],
      );
      if (response == null || !response.isSuccessful) return;
      await _setupAtClient(authRequest, response);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onboardRegistrar() async {
    setState(() { _busy = true; _error = null; });
    try {
      final request = await AtSignSelectionDialog.show(context);
      if (request == null) return;
      if (!mounted) return;
      final cramKey = await RegistrarCramDialog.show(
        context,
        request as AtOnboardingRequest,
        registrar: _registrar,
      );
      if (cramKey == null) return;
      if (!mounted) return;
      final response = await CramDialog.show(context, request: request, cramKey: cramKey);
      if (response == null || !response.isSuccessful) return;

      final authRequest = AtAuthRequest(
        request.atSign,
        rootDomain: request.rootDomain,
        atKeysIo: KeychainAtKeysIo(),
      );
      await _setupAtClient(authRequest, response);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apkamEnroll() async {
    setState(() { _busy = true; _error = null; });
    try {
      final request = await AtSignSelectionDialog.show(context);
      if (request == null) return;
      if (!mounted) return;
      final enrollResp = await ApkamActivationDialog.show(
        context,
        atSign: request.atSign,
        rootDomain: request.rootDomain,
        appName: kAppName,
        deviceName: kDeviceName,
        namespaces: const {kNamespace: 'rw'},
      );
      if (enrollResp == null || enrollResp.atAuthKeys == null) {
        throw AtAuthenticationException('Enrollment failed');
      }
      final authRequest = AtAuthRequest(
        request.atSign,
        atAuthKeys: enrollResp.atAuthKeys!,
        rootDomain: request.rootDomain,
      );
      if (!mounted) return;
      final response = await PkamDialog.show(
        context,
        request: authRequest,
        backupKeys: [KeychainAtKeysIo()],
      );
      if (response == null || !response.isSuccessful) return;
      await _setupAtClient(authRequest, response);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loginAtKeysFile() async {
    setState(() { _busy = true; _error = null; });
    try {
      final FileAtKeysIo? atKeysIo = await AtKeysFileDialog.show(context);
      if (atKeysIo == null) return;
      final atSign = atKeysIo.getAtsign();
      final authRequest = AtAuthRequest(
        atSign,
        atKeysIo: atKeysIo,
        rootDomain: AtRootDomain.atsignDomain,
      );
      if (!mounted) return;
      final response = await PkamDialog.show(
        context,
        request: authRequest,
        backupKeys: [KeychainAtKeysIo()],
      );
      if (response == null || !response.isSuccessful) return;
      await _setupAtClient(authRequest, response);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _busy,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand mark
                    Center(
                      child: Container(
                        width: 64, height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.shield_outlined, color: AppColors.primary, size: 30),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Center(
                      child: Text(
                        'Sign in',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.dangerBg,
                          border: Border.all(color: AppColors.dangerBorder),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _AuthMethodCard(
                      icon: Icons.fingerprint,
                      title: 'Login from Keychain',
                      subtitle: 'Use an atSign saved on this device',
                      onTap: _loginKeychain,
                    ),
                    const SizedBox(height: 10),
                    _AuthMethodCard(
                      icon: Icons.auto_awesome,
                      title: 'Onboard a New Atsign',
                      subtitle: 'Activate a fresh atSign via email',
                      onTap: _onboardRegistrar,
                    ),
                    const SizedBox(height: 10),
                    _AuthMethodCard(
                      icon: Icons.phone_iphone,
                      title: 'Activate This Device (APKAM)',
                      subtitle: 'Add this device to an existing atSign',
                      onTap: _apkamEnroll,
                    ),
                    const SizedBox(height: 10),
                    _AuthMethodCard(
                      icon: Icons.vpn_key_outlined,
                      title: 'Login with .atKeys File',
                      subtitle: 'Import keys from another device',
                      onTap: _loginAtKeysFile,
                    ),
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tappable card showing one of the four auth method options.
class _AuthMethodCard extends StatelessWidget {
  const _AuthMethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

