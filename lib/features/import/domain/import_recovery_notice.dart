import 'dart:convert';

class ImportRecoveryNotice {
  const ImportRecoveryNotice({
    required this.raw,
    required this.generation,
    required this.interruptedJobs,
    required this.cleanupFailures,
  });

  static const settingKey = 'importRecoveryNotice';
  final String raw;
  final int generation;
  final int interruptedJobs;
  final int cleanupFailures;

  factory ImportRecoveryNotice.parse(String raw) {
    try {
      final value = jsonDecode(raw) as Map;
      final generation = value['generation'] as int;
      final jobs = value['interruptedJobs'] as int;
      final failures = value['cleanupFailures'] as int;
      if (value['version'] != 1 || generation < 0 || jobs < 0 || failures < 0) {
        throw const FormatException('Invalid recovery notice');
      }
      return ImportRecoveryNotice(
        raw: raw,
        generation: generation,
        interruptedJobs: jobs,
        cleanupFailures: failures,
      );
    } catch (_) {
      // A damaged setting must not prevent access to saved learning data.
      return ImportRecoveryNotice(
        raw: raw,
        generation: 0,
        interruptedJobs: 0,
        cleanupFailures: 1,
      );
    }
  }
}
