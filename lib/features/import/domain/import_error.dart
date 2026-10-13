enum ImportErrorCode {
  invalidArchive,
  damagedArchive,
  unsupportedCollectionVersion,
  missingCollection,
  invalidMediaManifest,
  transactionFailed,
}

class ApkgImportException implements Exception {
  const ApkgImportException(this.code, this.message);
  final ImportErrorCode code;
  final String message;
  @override
  String toString() => message;
}
