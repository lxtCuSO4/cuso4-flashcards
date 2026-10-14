import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app/cuso4_app.dart';
import 'features/backup/data/restore_service.dart';
import 'features/backup/domain/backup_manifest.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final root = await getApplicationSupportDirectory();
    RestoreService.recoverInterrupted(root);
    try {
      RestoreService.cleanAbandonedJobs(root);
    } catch (_) {
      /* Retry temporary cleanup next launch. */
    }
  } catch (error) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  error is BackupException
                      ? error.message
                      : '本机数据暂时无法打开。请保留应用和数据，重新启动后重试；请勿卸载。',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }
  runApp(const ProviderScope(child: Cuso4App()));
}
