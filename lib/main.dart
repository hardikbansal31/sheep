import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/providers.dart';
import 'core/sync/powersync_db.dart';
import 'core/sync/supabase_connector.dart';
import 'core/sync/sync_config.dart';
import 'core/sync/sync_providers.dart';
import 'features/settings/providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1200, 800),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: 'Sheep',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // ── Initialize Supabase ────────────────────────────────────
  await Supabase.initialize(
    url: SyncConfig.supabaseUrl,
    publishableKey: SyncConfig.supabasePublishableKey,
  );

  // ── Initialize PowerSync ───────────────────────────────────
  final powerSyncDb = await openPowerSyncDatabase();

  // ── Build provider container with overrides ────────────────
  final container = ProviderContainer(
    overrides: [
      powerSyncProvider.overrideWithValue(powerSyncDb),
    ],
  );

  // Ensure local-only tables are ready (preferences, FTS, etc.)

  // ── Initialize synced data ─────────────────────────────────
  final syncRepo = container.read(syncRepoProvider);
  await syncRepo.ensureInitialState();

  // Load settings into memory before showing UI
  await container.read(settingsProvider.future);

  // ── Connect PowerSync if user is already authenticated ─────
  final supabase = Supabase.instance.client;
  if (supabase.auth.currentSession != null) {
    powerSyncDb.connect(connector: SupabaseConnector(supabase));
  }

  // Listen for auth changes to connect/disconnect PowerSync.
  supabase.auth.onAuthStateChange.listen((data) {
    if (data.event == AuthChangeEvent.signedIn) {
      powerSyncDb.connect(connector: SupabaseConnector(supabase));
    } else if (data.event == AuthChangeEvent.signedOut) {
      powerSyncDb.disconnect();
    }
  });

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const SheepApp(),
    ),
  );
}
