import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_cli_commons/at_cli_commons.dart';
import 'package:at_client/at_client.dart';

/// Retirement Policy.
///
/// Listens for `confirm_a.<id>` from the A stakeholder and `confirm_b.<id>`
/// from the B stakeholder. Once BOTH arrive, deletes:
///   - submission_a.<id>, submission_b.<id>
///   - result.<id> shared with @company_a
///   - result.<id> shared with @company_b
///   - mutex.<id>
/// One-way: the analysis cannot be reopened from the existing identity.
Future<void> main(List<String> args) async {
  final parser = CLIBase.argsParser
    ..addOption('analysis-id', mandatory: true)
    ..addOption('a-stake', mandatory: true, help: 'Company A stakeholder Atsign')
    ..addOption('b-stake', mandatory: true, help: 'Company B stakeholder Atsign')
    ..addOption('company-a', mandatory: true, help: 'Company A Atsign')
    ..addOption('company-b', mandatory: true, help: 'Company B Atsign');

  final effectiveArgs = _ensureStorageDir(args, 'retire_');
  final cli = await CLIBase.fromCommandLineArgs(effectiveArgs, parser: parser);
  final atClient = cli.atClient;
  final me = atClient.getCurrentAtSign()!;

  final parsed = parser.parse(effectiveArgs);
  final analysisId = parsed['analysis-id'] as String;
  final aStake = parsed['a-stake'] as String;
  final bStake = parsed['b-stake'] as String;
  final aSign = parsed['company-a'] as String;
  final bSign = parsed['company-b'] as String;

  stdout.writeln('[$me] retirement policy armed for analysisId=$analysisId');

  final confirmed = <String>{};
  final ready = Completer<void>();

  final regex = 'confirm_[ab]\\.$analysisId\\.${cli.nameSpace}';
  final sub = atClient.notificationService
      .subscribe(regex: regex, shouldDecrypt: true)
      .listen((n) {
    final from = n.from;
    if (n.key.contains('confirm_a.') && from == aStake) confirmed.add('a');
    if (n.key.contains('confirm_b.') && from == bStake) confirmed.add('b');
    stdout.writeln('[$me] confirmation from $from — set=$confirmed');
    if (confirmed.length == 2 && !ready.isCompleted) ready.complete();
  });

  await ready.future;
  await sub.cancel();

  stdout.writeln('[$me] both confirmed — revoking analysis $analysisId');

  // Write the IMMUTABLE retirement receipt FIRST, before any destruction.
  // - Immutable: nobody (not even @cleanroom) can rewrite it afterwards.
  // - Shared with both stakeholders so they can prove the engagement closed.
  // - This is the audit trail that survives retirement.
  final retiredAt = DateTime.now().toUtc().toIso8601String();
  final receiptPayload = jsonEncode({
    'analysisId': analysisId,
    'retiredAt': retiredAt,
    'confirmedBy': [aStake, bStake],
    'destroyedKeys': [
      'result.$analysisId@$aSign',
      'result.$analysisId@$bSign',
      'result.$analysisId@$aStake',
      'result.$analysisId@$bStake',
      'submission_a.$analysisId@$me',
      'submission_b.$analysisId@$me',
      'mutex.$analysisId@$me',
    ],
    'cleanRoom': me,
  });

  for (final recipient in [aStake, bStake]) {
    final receiptKey = AtKey()
      ..key = 'receipt.$analysisId'
      ..namespace = cli.nameSpace
      ..sharedBy = me
      ..sharedWith = recipient
      ..metadata = (Metadata()..immutable = true);
    try {
      await atClient.put(
        receiptKey,
        receiptPayload,
        putRequestOptions: PutRequestOptions()..useRemoteAtServer = true,
      );
      stdout.writeln('[$me] wrote immutable retirement receipt for $recipient');
    } on Exception catch (e) {
      stderr.writeln('[$me] failed to write receipt for $recipient: $e');
    }
  }

  // result.<id> shares for all four recipients the clean room may have written to.
  AtKey resultShare(String target) => AtKey()
    ..key = 'result.$analysisId'
    ..namespace = cli.nameSpace
    ..sharedBy = me
    ..sharedWith = target;

  final keysToDelete = <AtKey>[
    resultShare(aSign),
    resultShare(bSign),
    resultShare(aStake), // stakeholder share if it exists; delete is idempotent
    resultShare(bStake),
    AtKey()
      ..key = 'mutex.$analysisId'
      ..namespace = cli.nameSpace
      ..sharedBy = me,
    AtKey()
      ..key = 'submission_a.$analysisId'
      ..namespace = cli.nameSpace
      ..sharedBy = aSign
      ..sharedWith = me,
    AtKey()
      ..key = 'submission_b.$analysisId'
      ..namespace = cli.nameSpace
      ..sharedBy = bSign
      ..sharedWith = me,
  ];

  for (final k in keysToDelete) {
    try {
      await atClient.delete(k);
      stdout.writeln('[$me] deleted $k');
    } on Exception catch (e) {
      stderr.writeln('[$me] delete $k failed: $e');
    }
  }

  stdout.writeln('[$me] retirement complete');
}

List<String> _ensureStorageDir(List<String> args, String prefix) {
  for (final a in args) {
    if (a == '-s' || a == '--storage-dir' || a.startsWith('--storage-dir=')) {
      return args;
    }
  }
  final tmp = Directory.systemTemp.createTempSync(prefix).path;
  return [...args, '--storage-dir', tmp];
}
