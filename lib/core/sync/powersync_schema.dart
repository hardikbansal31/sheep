import 'package:powersync/powersync.dart';

/// PowerSync client-side schema — mirrors the Supabase Postgres tables
/// for synced data only (sections and pages).
///
/// Local-only tables (UserPreferences, CustomDictionary, PagesSearch)
/// remain on Drift and are NOT defined here.
///
/// Note: The `id` column is implicit in PowerSync — do not declare it.
/// Note: `user_id` is server-side only and excluded from sync columns.
const syncSchema = Schema([
  Table('sections', [
    Column.text('title'),
    Column.integer('order_index'),
    Column.text('created_at'),
    Column.integer('is_deleted'),
  ]),
  Table('pages', [
    Column.text('section_id'),
    Column.text('title'),
    Column.text('content_json'),
    Column.text('updated_at'),
    Column.integer('is_deleted'),
  ]),
]);
