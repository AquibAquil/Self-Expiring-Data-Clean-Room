import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_cli_commons/at_cli_commons.dart';
import 'package:at_client/at_client.dart';
import 'package:crypto/crypto.dart';

/// Company-side agent for the clean room joint analysis.
///
/// 1. Reads raw identifiers from --input file.
/// 2. Hashes them locally (HMAC-SHA-256 keyed with a shared secret salt from
///    --salt-file) so raw IDs never leave and the clean room cannot
///    dictionary-attack the hashes.
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
    ..addOption('input', mandatory: true, help: 'Path to a newline-separated file of raw identifiers.')
    ..addOption('salt-file', mandatory: true, help:
        'Path to a file containing the shared secret salt for this analysis. '
        'Both A and B must be given the same file, distributed out-of-band '
        '(e.g. NoPorts tunnel, sealed envelope). Must be at least 32 bytes.');

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
  final saltPath = parsed['salt-file'] as String;

  stdout.writeln('[$me] company_agent role=$role analysisId=$analysisId peer=$peer');

  // Per-analysis salt MUST be agreed between A and B so hashes are comparable
  // AND kept secret from the clean-room operator — otherwise a curious operator
  // with a candidate list (common emails, phone-number ranges) can brute-force
  // which raw identifiers were in a submission. The salt is loaded from a file
  // distributed out-of-band between A and B; the clean room never sees it.
  final salt = (await File(saltPath).readAsBytes());
  if (salt.length < 32) {
    stderr.writeln('[$me] salt-file must be at least 32 bytes (generate with a CSPRNG, e.g. openssl rand -out salt.bin 32)');
    exit(2);
  }
  final rawIds = await File(inputPath).readAsLines();
  final hashes = <String>[
    for (final id in rawIds.where((l) => l.trim().isNotEmpty))
      Hmac(sha256, salt).convert(utf8.encode(id.trim().toLowerCase())).toString(),
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
    'hashScheme': 'hmac_sha256_v1',
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
