import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';

import 'powersync_schema.dart';

/// Initializes and returns the [PowerSyncDatabase] instance for synced tables.
///
/// This database manages only sections and pages.
/// Local-only tables (preferences, dictionary, FTS) remain on Drift.
Future<PowerSyncDatabase> openPowerSyncDatabase() async {
  final dir = await getApplicationSupportDirectory();
  final path = join(dir.path, 'sheep-powersync.db');

  final db = PowerSyncDatabase(
    schema: syncSchema,
    path: path,
  );
  await db.initialize();
  return db;
}
