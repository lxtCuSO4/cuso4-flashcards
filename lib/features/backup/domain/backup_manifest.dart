enum BackupErrorCode {
  invalidArchive,
  unsupportedVersion,
  checksumMismatch,
  insufficientSpace,
  canceled,
}

class BackupException implements Exception {
  const BackupException(this.code, this.message);
  final BackupErrorCode code;
  final String message;
  @override
  String toString() => message;
}

const invalidBackup = BackupException(
  BackupErrorCode.invalidArchive,
  '备份损坏或不是 Lunar Memory 备份，请重新选择文件。',
);
final backupHash = RegExp(r'^[a-f0-9]{64}$');
const maxBackupBytes = 2 * 1024 * 1024 * 1024;
const backupSpaceReserve = 16 * 1024 * 1024;

class BackupEntry {
  const BackupEntry({required this.hash, required this.bytes});
  final String hash;
  final int bytes;
  Map<String, Object> toJson() => {'sha256': hash, 'bytes': bytes};
  factory BackupEntry.fromJson(dynamic value) {
    if (value is! Map ||
        value['sha256'] is! String ||
        !backupHash.hasMatch(value['sha256'] as String) ||
        value['bytes'] is! int ||
        value['bytes'] < 0 ||
        value['bytes'] > maxBackupBytes) {
      throw invalidBackup;
    }
    return BackupEntry(
      hash: value['sha256'] as String,
      bytes: value['bytes'] as int,
    );
  }
}

class BackupManifest {
  BackupManifest({
    required this.createdAtUtc,
    required this.database,
    required this.media,
    this.appVersion = '1.0.0+1',
    this.formatVersion = 2,
  });
  final DateTime createdAtUtc;
  final BackupEntry database;
  final Map<String, BackupEntry> media;
  final String appVersion;
  final int formatVersion;
  Map<String, Object> toJson() => {
    'format': 'cuso4-backup',
    'formatVersion': formatVersion,
    'databaseSchemaVersion': 1,
    'appVersion': appVersion,
    'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
    'includesSettings': true,
    'database': database.toJson(),
    'media': media.map((key, value) => MapEntry(key, value.toJson())),
  };
  factory BackupManifest.fromJson(dynamic value) {
    if (value is! Map || value['format'] != 'cuso4-backup') throw invalidBackup;
    if (value['formatVersion'] is int && value['formatVersion'] > 2 ||
        value['databaseSchemaVersion'] is int &&
            value['databaseSchemaVersion'] > 1) {
      throw const BackupException(
        BackupErrorCode.unsupportedVersion,
        '该备份来自较新版应用，请更新 Lunar Memory 后恢复。',
      );
    }
    if (![1, 2].contains(value['formatVersion']) ||
        value['databaseSchemaVersion'] != 1 ||
        value['includesSettings'] != true ||
        value['appVersion'] is! String ||
        (value['appVersion'] as String).isEmpty ||
        value['createdAtUtc'] is! String ||
        value['media'] is! Map ||
        (value['media'] as Map).length > 49998) {
      throw invalidBackup;
    }
    final time = DateTime.tryParse(value['createdAtUtc'] as String);
    if (time == null || !time.isUtc) throw invalidBackup;
    final media = <String, BackupEntry>{};
    for (final entry in (value['media'] as Map).entries) {
      if (entry.key is! String || !backupHash.hasMatch(entry.key as String)) {
        throw invalidBackup;
      }
      final item = BackupEntry.fromJson(entry.value);
      if (item.hash != entry.key) throw invalidBackup;
      media[entry.key as String] = item;
    }
    final database = BackupEntry.fromJson(value['database']);
    if (database.bytes <= 0 ||
        database.bytes + media.values.fold<int>(0, (sum, e) => sum + e.bytes) >
            maxBackupBytes) {
      throw invalidBackup;
    }
    return BackupManifest(
      createdAtUtc: time,
      database: database,
      media: media,
      appVersion: value['appVersion'] as String,
      formatVersion: value['formatVersion'] as int,
    );
  }
}

typedef AvailableBytes = Future<int?> Function();

Future<void> requireBackupSpace(AvailableBytes? available, int needed) async {
  final free = await available?.call();
  if (free != null && free < needed + backupSpaceReserve) {
    throw const BackupException(
      BackupErrorCode.insufficientSpace,
      '本机可用空间不足，请释放空间后重试。现有数据未被覆盖。',
    );
  }
}

void checkBackupCanceled(bool Function()? isCancelled) {
  if (isCancelled?.call() ?? false) {
    throw const BackupException(BackupErrorCode.canceled, '已取消，现有数据未改变。');
  }
}
