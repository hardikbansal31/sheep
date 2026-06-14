/// Configuration constants for Supabase and PowerSync.
///
/// Replace placeholder values with your actual project credentials.
/// In production, inject these via --dart-define or env files.
abstract final class SyncConfig {
  /// Supabase project URL — found in Supabase Settings → API.
  static const String supabaseUrl = 'https://hsfybyztczopuygupbzy.supabase.co';

  /// Supabase publishable (anon) key — found in Supabase Settings → API.
  static const String supabasePublishableKey = 'sb_publishable_JdQpzTW_iQiS8a599AK8xw_X_LsbVtj';

  /// PowerSync instance URL — found in the PowerSync dashboard.
  static const String powerSyncUrl = 'https://6a2e83a30ef84ed671a19193.powersync.journeyapps.com';
}
