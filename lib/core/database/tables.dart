import 'package:drift/drift.dart';

/// Sections table — top-level organizational unit.
class Sections extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  IntColumn get orderIndex => integer()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Pages table — each page belongs to one section.
class Pages extends Table {
  TextColumn get id => text()();
  TextColumn get sectionId =>
      text().references(Sections, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()();
  TextColumn get contentJson => text()();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Key-value store for user preferences (theme, font defaults, etc.).
class UserPreferences extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Custom dictionary words added by the user for spell check.
class CustomDictionary extends Table {
  TextColumn get word => text()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {word};
}
