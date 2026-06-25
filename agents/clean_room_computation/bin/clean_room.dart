import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_cli_commons/at_cli_commons.dart';
import 'package:at_client/at_client.dart';

/// Clean Room Computation process.
///
/// - Receives hashed submissions from @company_a and @company_b.
/// - Computes overlap (set intersection on hash strings) — never sees raw IDs.
/// - Publishes the aggregate result to BOTH companies as separate AtKeys.
///
/// Multi-instance safe via an immutable mutex key (`mutex.<analysisId>`).
Future<void> main(List<String> args) async {
  final parser = CLIBase.argsParser
    ..addOption('analysis-id', mandatory: true)
    ..addOption('company-a', mandatory: true, help: 'Company A Atsign')
    ..addOption('company-b', mandatory: true, help: 'Company B Atsign')
    ..addOption('a-stake', help: 'Optional: also share the result with Stakeholder A so they can view it from the app')
    ..addOption('b-stake', help: 'Optional: also share the result with Stakeholder B so they can view it from the app');

  final effectiveArgs = _ensureStorageDir(args, 'cleanroom_');
  final cli = await CLIBase.fromCommandLineArgs(effectiveArgs, parser: parser);
  final atClient = cli.atClient;
  final me = atClient.getCurrentAtSign()!;

  final parsed = parser.parse(effectiveArgs);
  final analysisId = parsed['analysis-id'] as String;
  final aSign = parsed['company-a'] as String;
  final bSign = parsed['company-b'] as String;
  final aStake = parsed['a-stake'] as String?;
  final bStake = parsed['b-stake'] as String?;

  stdout.writeln('[$me] clean room ready analysisId=$analysisId a=$aSign b=$bSign'
      '${aStake != null ? ' a-stake=$aStake' : ''}'
      '${bStake != null ? ' b-stake=$bStake' : ''}');

  if (!await _claimMutex(atClient, me, analysisId, cli.nameSpace)) {
    stdout.writeln('[$me] another instance holds mutex.$analysisId — exiting');
    return;
  }

  final submissions = <String, List<String>>{};
  final done = Completer<void>();

  final subRegex = 'submission_[ab]\\.$analysisId\\.${cli.nameSpace}';
  final sub = atClient.notificationService
      .subscribe(regex: subRegex, shouldDecrypt: true)
      .listen((n) {
    try {
      final role = n.key.contains('submission_a.') ? 'a' : 'b';
      final from = n.from;
      if ((role == 'a' && from != aSign) || (role == 'b' && from != bSign)) {
        stderr.writeln('[$me] rejecting unexpected sender $from for role=$role');
        return;
      }
      final payload = jsonDecode(n.value ?? '{}') as Map<String, dynamic>;
      final hashes = (payload['hashes'] as List).cast<String>();
      submissions[role] = hashes;
      stdout.writeln('[$me] got submission $role: ${hashes.length} hashes');
      if (submissions.length == 2 && !done.isCompleted) done.complete();
    } catch (e) {
      stderr.writeln('[$me] error processing notification: $e');
    }
  });

  await done.future.timeout(const Duration(hours: 1), onTimeout: () {
    stderr.writeln('[$me] timed out waiting for both submissions');
  });
  await sub.cancel();

  if (submissions.length < 2) exit(2);

  final aSet = submissions['a']!.toSet();
  final bSet = submissions['b']!.toSet();
  final overlap = aSet.intersection(bSet);
  final unionSize = aSet.union(bSet).length;
  final pct = unionSize == 0 ? 0.0 : (overlap.length * 100.0 / unionSize);

  final resultJson = jsonEncode({
    'analysisId': analysisId,
    'overlapCount': overlap.length,
    'overlapPercent': pct,
    'aSize': aSet.length,
    'bSize': bSet.length,
  });

  final resultRecipients = <String>[
    aSign,
    bSign,
    if (aStake != null) aStake,
    if (bStake != null) bStake,
  ];
  for (final target in resultRecipients) {
    final resKey = AtKey()
      ..key = 'result.$analysisId'
      ..namespace = cli.nameSpace
      ..sharedBy = me
      ..sharedWith = target
      ..metadata = (Metadata()..ttr = -1);
    try {
      // 1. Persistent put on the sender's atServer so recipients can later
      //    atClient.get() the value (the Flutter app uses this path).
      await atClient.put(
        resKey,
        resultJson,
        putRequestOptions: PutRequestOptions()..useRemoteAtServer = true,
      );
      // 2. Notify for real-time delivery to any subscriber (CLI agents).
      final res = await atClient.notificationService.notify(
        NotificationParams.forUpdate(resKey, value: resultJson),
        waitForFinalDeliveryStatus: true,
      );
      stdout.writeln('[$me] delivered result to $target: ${res.notificationStatusEnum}');
    } on Exception catch (e) {
      stderr.writeln('[$me] put/notify $target failed: $e');
    }
  }
}

Future<bool> _claimMutex(AtClient atClient, String me, String analysisId, String namespace) async {
  final key = AtKey()
    ..key = 'mutex.$analysisId'
    ..namespace = namespace
    ..sharedBy = me
    ..metadata = (Metadata()
      ..immutable = true
      ..ttl = 1000 * 60 * 60);
  try {
    return await atClient.put(
      key,
      jsonEncode({'holder': pid}),
      putRequestOptions: PutRequestOptions()..useRemoteAtServer = true,
    );
  } on Exception {
    return false;
  }
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
