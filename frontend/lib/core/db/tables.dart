import 'package:drift/drift.dart';

/// Mirrors `MembershipPlan` in `backend/core/models.py`.
///
/// - `priceCentavos` is parsed from the wire's decimal string (`"1500.00"`)
///   via `parseCentavos` in `core/utils/money.dart` — never through `double`.
/// - `durationValue` + `durationUnit` are stored verbatim; there is no
///   `durationDays`. Unit choices are DAY / WEEK / MONTH / YEAR.
/// - No `deletedAt` — plans use `isActive` as their soft-delete flag,
///   there is no archive timestamp on the backend model.
class MembershipPlans extends Table {
  TextColumn get id => text()();
  TextColumn get gymId => text()(); // not in the serializer — stamp on ingest
  TextColumn get name => text()();
  TextColumn get category => text().withDefault(const Constant(''))();
  IntColumn get durationValue => integer()();
  TextColumn get durationUnit => text()(); // DAY | WEEK | MONTH | YEAR
  IntColumn get priceCentavos => integer()();
  BoolColumn get isDayPass => boolean()();
  BoolColumn get isActive => boolean()();
  IntColumn get sortOrder => integer()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isDirty => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};

  // Mirrors uniq_plan_name_per_gym.
  @override
  List<Set<Column>> get uniqueKeys => [
    {gymId, name, category},
  ];
}

/// Mirrors `Member` in `backend/core/models.py`.
///
/// - `phone` / `email` are `blank=True` (not `null=True`) on the backend,
///   so they're non-nullable here with `''` defaults — never null.
/// - `dateOfBirth` is the one genuinely nullable text-ish field.
/// - Soft delete is `archivedAt`, matching `MemberQuerySet.visible()`
///   (`archived_at__isnull=True`) — every read query must filter on it.
/// - `currentPlanCategory` mirrors `MemberQuerySet.with_status()`'s
///   `current_plan_category` annotation — the category of whichever
///   Membership row is currently active/latest, via a Subquery, not a
///   stored FK on Member itself. Null when the member has no membership
///   yet, same as currentEndDate.
/// - The partial unique index on (gymId, memberCode) WHERE memberCode != ''
///   can't be expressed with `uniqueKeys` (no WHERE support), so it's
///   declared as raw SQL in the migration in app_database.dart instead.
class Members extends Table {
  TextColumn get id => text()();
  TextColumn get gymId => text()(); // not in the serializer — stamp on ingest
  TextColumn get homeLocationId => text()(); // FK UUID, not null
  TextColumn get memberCode => text().withDefault(const Constant(''))();
  TextColumn get firstName => text()();
  TextColumn get lastName => text().withDefault(const Constant(''))();
  TextColumn get phone => text().withDefault(const Constant(''))();
  TextColumn get email => text().withDefault(const Constant(''))();
  DateTimeColumn get dateOfBirth => dateTime().nullable()();
  TextColumn get memberType => text()(); // MEMBER | PROSPECT
  TextColumn get notes => text().withDefault(const Constant(''))();
  DateTimeColumn get currentEndDate =>
      dateTime().nullable()(); // derived server-side
  TextColumn get currentPlanCategory => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  BoolColumn get isDirty => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
