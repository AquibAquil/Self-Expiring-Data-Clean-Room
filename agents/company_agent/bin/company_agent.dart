import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_cli_commons/at_cli_commons.dart';
import 'package:at_client/at_client.dart';
import 'package:crypto/crypto.dart';

/// Company-side agent for the clean room joint analysis.
///
/// 1. Reads raw identifiers from --input file.
/// 2. Hashes them locally (SHA-256 + per-analysis salt) so raw IDs never leave.
/// 3. Notifies the clean room Atsign with the hash list as
///    `submission_<role>.<analysisId>.<namespace>`.
/// 4. Subscribes for the aggregate result and prints it on arrival.
///
/// The two agents share this binary; --role a|b picks which key it writes.
Future<void> main(List<String> args) async {
  final parser = CLIBase.argsParser
    ..addOption('role', allowed: ['a', 'b'], help: 'Which side of the analysis this agent represents.')
    ..addOption('analysis-id', mandatory: true, help: 'Per-analysis UUID picked by the operator.')
    ..addOption('peer', mandatory: true, help: 'The clean room Atsign (e.g. @cleanroom).')
    ..addOption('input', mandatory: true, help: 'Path to a newline-separated file of raw identifiers.');

  // Default the storage-dir to a fresh temp dir if the caller didn't pass one,
  // so two agents on the same box never collide on Hive boxes.
  final effectiveArgs = _ensureStorageDir(args, 'company_agent_');

  final cli = await CLIBase.fromCommandLineArgs(effectiveArgs, parser: parser);
  final atClient = cli.atClient;
  final me = atClient.getCurrentAtSign()!;

  final parsed = parser.parse(effectiveArgs);
  final role = parsed['role'] as String? ?? 'a';
  final analysisId = parsed['analysis-id'] as String;
  final peer = parsed['peer'] as String;
  final inputPath = parsed['input'] as String;

  stdout.writeln('[$me] company_agent role=$role analysisId=$analysisId peer=$peer');

  // Per-analysis salt MUST be agreed between A and B so hashes are comparable.
  // We derive it deterministically from the analysisId for demo simplicity.
  final salt = analysisId;
  final rawIds = await File(inputPath).readAsLines();
  final hashes = <String>[
    for (final id in rawIds.where((l) => l.trim().isNotEmpty))
      sha256.convert(utf8.encode('$salt|${id.trim().toLowerCase()}')).toString(),
  ];

  // Subscribe BEFORE submitting so we never miss the result.
  final resultRegex = 'result\\.$analysisId\\.${cli.nameSpace}';
  final resultReceived = Completer<void>();
  final sub = atClient.notificationService
      .subscribe(regex: resultRegex, shouldDecrypt: true)
      .listen((n) {
    try {
      final payload = jsonDecode(n.value ?? '{}') as Map<String, dynamic>;
      stdout.writeln('[$me] RESULT received: $payload');
    } catch (_) {
      stdout.writeln('[$me] RESULT received (raw): ${n.value}');
    }
    if (!resultReceived.isCompleted) resultReceived.complete();
  });

  final submissionKey = AtKey()
    ..key = 'submission_$role.$analysisId'
    ..namespace = cli.nameSpace
    ..sharedBy = me
    ..sharedWith = peer
    ..metadata = (Metadata()..ttr = -1);

  final body = jsonEncode({
    'analysisId': analysisId,
    'hashScheme': 'sha256_v1',
    'hashes': hashes,
  });

  try {
    final res = await atClient.notificationService.notify(
      NotificationParams.forUpdate(submissionKey, value: body),
      waitForFinalDeliveryStatus: true,
    );
    stdout.writeln('[$me] submission status=${res.notificationStatusEnum}');
  } on Exception catch (e) {
    stderr.writeln('[$me] notify failed: $e');
    await sub.cancel();
    exit(1);
  }

  await resultReceived.future.timeout(const Duration(minutes: 10), onTimeout: () {
    stderr.writeln('[$me] timed out waiting for result');
  });
  await sub.cancel();
}

/// If the caller didn't pass `-s/--storage-dir`, inject a fresh temp dir so
/// multiple agents on the same machine never share a Hive box.
List<String> _ensureStorageDir(List<String> args, String prefix) {
  for (final a in args) {
    if (a == '-s' || a == '--storage-dir' || a.startsWith('--storage-dir=')) {
      return args;
    }
  }
  final tmp = Directory.systemTemp.createTempSync(prefix).path;
  return [...args, '--storage-dir', tmp];
}
