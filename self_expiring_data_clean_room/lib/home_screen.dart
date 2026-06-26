import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'theme.dart';
import 'widgets/app_toast.dart';
import 'widgets/confirm_dialog.dart';
import 'widgets/donut.dart';
import 'widgets/identity_card.dart';
import 'widgets/lifecycle_chip.dart';
import 'widgets/section_card.dart';

const String kNamespace = 'cleanroom';

/// Stakeholder home screen — engagement entry, result viewing, retirement
/// receipt viewing, and (advanced) key export.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.atSign});
  final String atSign;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _analysisIdCtrl = TextEditingController();
  final _cleanRoomCtrl = TextEditingController();
  String _role = 'a';

  // Action states
  bool _sending = false;
  bool _viewingResult = false;
  bool _viewingReceipt = false;
  bool _exporting = false;
  bool _hasConfirmed = false;

  // Result/receipt cached data
  Map<String, dynamic>? _result;
  Map<String, dynamic>? _receipt;
  bool _resultRetired = false;

  // ---- friendly-name + role helpers --------------------------------------

  String get _friendlyName {
    // For the demo: derive a friendly name from the atSign last segment.
    // In a real deployment this would come from a directory service.
    final segment = widget.atSign.replaceFirst('@', '').split('_').first;
    return segment.isEmpty
        ? widget.atSign
        : '${segment[0].toUpperCase()}${segment.substring(1)}';
  }

  String get _roleLabel => _role == 'a' ? 'Stakeholder · Company A' : 'Stakeholder · Company B';

  LifecyclePhase get _phase {
    if (_receipt != null || _resultRetired) return LifecyclePhase.retired;
    if (_hasConfirmed) return LifecyclePhase.awaiting;
    return LifecyclePhase.active;
  }

  String? get _retiredSubtitle {
    if (_receipt == null) return null;
    final retiredAt = _receipt!['retiredAt'] as String?;
    if (retiredAt == null) return null;
    try {
      final dt = DateTime.parse(retiredAt).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return null;
    }
  }

  // ---- handlers -----------------------------------------------------------

  Future<void> _confirm() async {
    final analysisId = _analysisIdCtrl.text.trim();
    if (analysisId.isEmpty) {
      showAppToast(context, kind: ToastKind.error, message: 'Analysis ID is required');
      return;
    }
    final cleanRoomRaw = _cleanRoomCtrl.text.trim();
    if (cleanRoomRaw.isEmpty) {
      showAppToast(context, kind: ToastKind.error, message: 'Clean Room atSign is required');
      return;
    }

    final companyLabel = _role == 'a' ? 'Company A' : 'Company B';
    final ok = await showConfirmDialog(
      context,
      title: 'Confirm as $companyLabel?',
      body:
          'This will signal the clean room that you consider this analysis complete. '
          'Once both companies confirm, all analysis data will be cryptographically '
          'destroyed. This cannot be undone.',
      confirmLabel: 'Confirm',
    );
    if (ok != true) return;

    setState(() => _sending = true);
    try {
      final cleanRoom = cleanRoomRaw.toAtsign();
      final atClient = AtClientManager.getInstance().atClient;
      final key = AtKey()
        ..key = 'confirm_${_role}.$analysisId'
        ..namespace = kNamespace
        ..sharedBy = widget.atSign
        ..sharedWith = cleanRoom;
      final payload = jsonEncode({
        'analysisId': analysisId,
        'at': DateTime.now().toUtc().toIso8601String(),
      });
      final res = await atClient.notificationService.notify(
        NotificationParams.forUpdate(key, value: payload),
        waitForFinalDeliveryStatus: true,
      );
      if (!mounted) return;
      if (res.notificationStatusEnum == NotificationStatusEnum.delivered) {
        setState(() => _hasConfirmed = true);
        showAppToast(
          context,
          kind: ToastKind.success,
          message: 'Confirmation sent. Awaiting the other side.',
        );
      } else {
        showAppToast(
          context,
          kind: ToastKind.error,
          message: 'Delivery status: ${res.notificationStatusEnum.name}',
          onRetry: _confirm,
        );
      }
    } catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        kind: ToastKind.error,
        message: 'Couldn\'t reach the clean room. Check your connection.',
        onRetry: _confirm,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _viewResult() async {
    setState(() {
      _viewingResult = true;
      _result = null;
      _resultRetired = false;
    });
    showAppToast(context, kind: ToastKind.info, message: 'Fetching result from clean room…');
    try {
      final analysisId = _analysisIdCtrl.text.trim();
      if (analysisId.isEmpty) throw 'Analysis ID is required';
      final cleanRoom = _cleanRoomCtrl.text.trim().toAtsign();
      final atClient = AtClientManager.getInstance().atClient;
      final key = AtKey()
        ..key = 'result.$analysisId'
        ..namespace = kNamespace
        ..sharedBy = cleanRoom
        ..sharedWith = widget.atSign;
      final value = await atClient.get(
        key,
        getRequestOptions: GetRequestOptions()
          ..bypassCache = true
          ..useRemoteAtServer = true,
      );
      final raw = value.value;
      if (raw == null || (raw is String && raw.isEmpty)) {
        await _checkReceiptToDistinguishRetiredVsMissing();
        return;
      }
      setState(() => _result = jsonDecode(raw as String) as Map<String, dynamic>);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('does not exist') ||
          msg.contains('not found') ||
          msg.contains('AT0015') ||
          msg.contains('key_not_found')) {
        await _checkReceiptToDistinguishRetiredVsMissing();
      } else {
        if (mounted) {
          showAppToast(
            context,
            kind: ToastKind.error,
            message: 'Couldn\'t read the result. Check your connection.',
            onRetry: _viewResult,
          );
        }
      }
    } finally {
      if (mounted) setState(() => _viewingResult = false);
    }
  }

  /// Result was missing. Distinguish "engagement retired" from "never delivered"
  /// by checking whether the receipt exists.
  Future<void> _checkReceiptToDistinguishRetiredVsMissing() async {
    try {
      final analysisId = _analysisIdCtrl.text.trim();
      final cleanRoom = _cleanRoomCtrl.text.trim().toAtsign();
      final atClient = AtClientManager.getInstance().atClient;
      final receiptKey = AtKey()
        ..key = 'receipt.$analysisId'
        ..namespace = kNamespace
        ..sharedBy = cleanRoom
        ..sharedWith = widget.atSign;
      final r = await atClient.get(
        receiptKey,
        getRequestOptions: GetRequestOptions()
          ..bypassCache = true
          ..useRemoteAtServer = true,
      );
      if (r.value != null && (r.value is! String || (r.value as String).isNotEmpty)) {
        setState(() {
          _resultRetired = true;
          _receipt = jsonDecode(r.value as String) as Map<String, dynamic>;
        });
        return;
      }
    } catch (_) {/* fall through */}
    if (mounted) {
      showAppToast(
        context,
        kind: ToastKind.info,
        message: 'No result delivered yet. Wait for the clean room to compute.',
      );
    }
  }

  Future<void> _viewReceipt() async {
    setState(() {
      _viewingReceipt = true;
      _receipt = null;
    });
    try {
      final analysisId = _analysisIdCtrl.text.trim();
      if (analysisId.isEmpty) throw 'Analysis ID is required';
      final cleanRoom = _cleanRoomCtrl.text.trim().toAtsign();
      final atClient = AtClientManager.getInstance().atClient;
      final key = AtKey()
        ..key = 'receipt.$analysisId'
        ..namespace = kNamespace
        ..sharedBy = cleanRoom
        ..sharedWith = widget.atSign;
      final v = await atClient.get(
        key,
        getRequestOptions: GetRequestOptions()
          ..bypassCache = true
          ..useRemoteAtServer = true,
      );
      final raw = v.value;
      if (raw == null || (raw is String && raw.isEmpty)) {
        if (mounted) {
          showAppToast(
            context,
            kind: ToastKind.info,
            message: 'No receipt yet — engagement is still active.',
          );
        }
        return;
      }
      setState(() => _receipt = jsonDecode(raw as String) as Map<String, dynamic>);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('does not exist') ||
          msg.contains('not found') ||
          msg.contains('AT0015') ||
          msg.contains('key_not_found')) {
        if (mounted) {
          showAppToast(
            context,
            kind: ToastKind.info,
            message: 'No receipt yet — engagement is still active.',
          );
        }
      } else {
        if (mounted) {
          showAppToast(
            context,
            kind: ToastKind.error,
            message: 'Couldn\'t read the receipt. Check your connection.',
            onRetry: _viewReceipt,
          );
        }
      }
    } finally {
      if (mounted) setState(() => _viewingReceipt = false);
    }
  }

  Future<void> _exportKeys() async {
    setState(() => _exporting = true);
    try {
      final filePath = await FilePicker.saveFile(
        dialogTitle: 'Save .atKeys file',
        fileName: '${widget.atSign}_key.atKeys',
        type: FileType.custom,
        allowedExtensions: const ['atKeys'],
      );
      if (filePath == null) return;
      final finalPath = filePath.endsWith('.atKeys') ? filePath : '$filePath.atKeys';
      final atKeys = await KeychainStorage().getAtsign(widget.atSign);
      if (atKeys == null) throw 'No keys found in keychain for ${widget.atSign}';
      final io = FileAtKeysIo(filePath: (_) => finalPath);
      io.write(widget.atSign, atKeys);
      if (mounted) {
        showAppToast(context, kind: ToastKind.success, message: 'Keys exported to $finalPath');
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, kind: ToastKind.error, message: 'Export failed: $e');
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ---- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Engagement'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.primary,
              child: Text(
                _friendlyName.characters.first.toUpperCase(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Breakpoint: under 700 px is treated as mobile (one column),
            // 700+ is desktop / tablet (sidebar + main). Phones are well
            // below 700 so the mobile codepath is bit-identical to before
            // this responsive layout existed.
            if (constraints.maxWidth < 700) {
              return _mobileLayout();
            }
            return _desktopLayout();
          },
        ),
      ),
    );
  }

  /// Mobile-first single-column layout — the original layout, preserved.
  Widget _mobileLayout() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IdentityCard(
                friendlyName: _friendlyName,
                atSign: widget.atSign,
                roleLabel: _roleLabel,
              ),
              const SizedBox(height: 12),
              LifecycleStatusChip(phase: _phase, subtitle: _retiredSubtitle),
              const SizedBox(height: 16),
              _engagementDetailsSection(),
              const SizedBox(height: 16),
              _aggregateResultSection(),
              const SizedBox(height: 16),
              _retirementReceiptSection(),
              const SizedBox(height: 16),
              _advancedSection(),
            ],
          ),
        ),
      ),
    );
  }

  /// Desktop / tablet layout: fixed-width sidebar (identity + lifecycle) on the
  /// left, scrollable main column with all section cards on the right.
  /// Capped at 1200 px total so it doesn't stretch across ultra-wide monitors.
  Widget _desktopLayout() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sidebar
              SizedBox(
                width: 320,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    IdentityCard(
                      friendlyName: _friendlyName,
                      atSign: widget.atSign,
                      roleLabel: _roleLabel,
                    ),
                    const SizedBox(height: 12),
                    LifecycleStatusChip(
                        phase: _phase, subtitle: _retiredSubtitle),
                  ],
                ),
              ),
              const SizedBox(width: 28),
              // Main content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _engagementDetailsSection(),
                    const SizedBox(height: 16),
                    _aggregateResultSection(),
                    const SizedBox(height: 16),
                    _retirementReceiptSection(),
                    const SizedBox(height: 16),
                    _advancedSection(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _engagementDetailsSection() {
    return SectionCard(
      icon: Icons.assignment_outlined,
      title: 'Engagement Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Analysis ID', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _analysisIdCtrl,
            decoration: const InputDecoration(hintText: 'e.g. demo-008'),
            style: monoStyle(size: 14, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          const Text(
            'ID of the clean room analysis',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 16),
          const Text('Clean Room atSign', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _cleanRoomCtrl,
            decoration: const InputDecoration(hintText: '@cleanroom_atsign'),
            style: monoStyle(size: 14, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 16),
          const Text('Role', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'a', label: Text('Company A')),
              ButtonSegment(value: 'b', label: Text('Company B')),
            ],
            selected: {_role},
            onSelectionChanged: (s) => setState(() => _role = s.first),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : Colors.transparent,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Auto-detected from your identity',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _sending ? null : _confirm,
            icon: _sending
                ? const SizedBox(
                    height: 16, width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_circle_outline, size: 18),
            label: Text(_sending ? 'Sending…' : 'Confirm Analysis Complete'),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text(
              'This action cannot be undone.',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _aggregateResultSection() {
    return SectionCard(
      icon: Icons.visibility_outlined,
      title: 'Aggregate Result',
      subtitle: 'The overlap computed by the clean room',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: _viewingResult ? null : _viewResult,
            icon: _viewingResult
                ? const SizedBox(
                    height: 14, width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.visibility, size: 18),
            label: Text(_viewingResult ? 'Reading…' : 'View Result'),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: _resultRetired
                ? _resultRetiredCard()
                : _result != null
                    ? _resultLoadedCard(_result!)
                    : _resultEmptyCard(),
          ),
        ],
      ),
    );
  }

  Widget _resultEmptyCard() {
    return Container(
      key: const ValueKey('result-empty'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        children: [
          Icon(Icons.visibility_off_outlined, color: AppColors.textTertiary, size: 22),
          SizedBox(height: 6),
          Text(
            'Tap View Result to fetch the aggregate',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _resultLoadedCard(Map<String, dynamic> r) {
    final overlap = r['overlapCount'];
    final pct = r['overlapPercent'];
    final aSize = r['aSize'];
    final bSize = r['bSize'];
    final union = (aSize is int && bSize is int && overlap is int)
        ? aSize + bSize - overlap
        : null;
    return Container(
      key: const ValueKey('result-loaded'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        border: Border.all(color: AppColors.successBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$overlap',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      union != null
                          ? 'matching records out of $union total'
                          : 'matching records',
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (pct is num) Donut(percent: pct.toDouble(), size: 64, strokeWidth: 7),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 12),
          Row(
            children: [
              _statColumn('$aSize', 'A submitted'),
              _statColumn('$bSize', 'B submitted'),
              _statColumn(
                pct is num ? '${pct.toStringAsFixed(1)}%' : '?',
                'Overlap',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statColumn(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _resultRetiredCard() {
    return Container(
      key: const ValueKey('result-retired'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        border: Border.all(color: AppColors.dangerBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outlined, color: AppColors.danger, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _retiredSubtitle == null
                  ? 'Result no longer available — engagement retired.'
                  : 'Result no longer available — engagement retired at $_retiredSubtitle.',
              style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w500, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _retirementReceiptSection() {
    return SectionCard(
      icon: Icons.receipt_long_outlined,
      title: 'Retirement Receipt',
      subtitle: 'Immutable audit trail. Survives retirement.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: _viewingReceipt ? null : _viewReceipt,
            icon: _viewingReceipt
                ? const SizedBox(
                    height: 14, width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.receipt_long, size: 18),
            label: Text(_viewingReceipt ? 'Reading…' : 'View Receipt'),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: _receipt != null ? _receiptLoadedCard(_receipt!) : _receiptEmptyCard(),
          ),
        ],
      ),
    );
  }

  Widget _receiptEmptyCard() {
    return Container(
      key: const ValueKey('receipt-empty'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        children: [
          Icon(Icons.receipt_long_outlined, color: AppColors.textTertiary, size: 22),
          SizedBox(height: 6),
          Text(
            'No receipt yet — engagement is still active',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _receiptLoadedCard(Map<String, dynamic> r) {
    final analysisId = r['analysisId'];
    final retiredAt = r['retiredAt'];
    final confirmedBy = (r['confirmedBy'] as List?)?.cast<String>() ?? const [];
    final destroyed = (r['destroyedKeys'] as List?)?.cast<String>() ?? const [];
    return Container(
      key: const ValueKey('receipt-loaded'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        border: Border.all(color: AppColors.infoBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.verified_outlined, color: AppColors.info, size: 18),
              SizedBox(width: 6),
              Text(
                'Engagement Retired',
                style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.info, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _receiptRow('Analysis ID', '$analysisId'),
          _receiptRow('Retired at', '$retiredAt'),
          _receiptRow('Confirmed by', confirmedBy.join(' + ')),
          const SizedBox(height: 8),
          Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
              listTileTheme: const ListTileThemeData(
                contentPadding: EdgeInsets.zero,
                minVerticalPadding: 0,
              ),
            ),
            child: ExpansionTile(
              title: Text(
                '${destroyed.length} keys destroyed',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              tilePadding: EdgeInsets.zero,
              children: [
                for (final k in destroyed)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: Row(
                      children: [
                        const Text('• ', style: TextStyle(color: AppColors.info)),
                        Expanded(child: Text(k, style: monoStyle(size: 11))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _receiptRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value, style: monoStyle(size: 12, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _advancedSection() {
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          leading: const Icon(Icons.settings_outlined, color: AppColors.textSecondary),
          title: const Text(
            'Advanced',
            style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textPrimary),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Export this atSign\'s keys to a .atKeys file so the CLI agents '
                    '(clean_room, retirement_policy, company_agent) can authenticate as '
                    'the same identity.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _exporting ? null : _exportKeys,
                    icon: _exporting
                        ? const SizedBox(
                            height: 14, width: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined, size: 18),
                    label: Text(_exporting ? 'Exporting…' : 'Export Atsign Keys'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
