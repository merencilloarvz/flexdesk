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
  // Holds the full JSON body for an offline-created member that hasn't
  // reached the server yet — null once synced. Lets syncPendingMembers()
  // replay the exact request (including the chosen plan) later.
  TextColumn get pendingPayload => text().nullable()();

  // Set when syncPendingMembers() gets a rejection it can't recover from
  // on its own (not a network failure, not an idempotent duplicate) — e.g.
  // the plan this member was created against got deleted before the
  // tablet reconnected. isDirty stays true (still unsynced) but syncError
  // being non-null means "already judged" — it's excluded from automatic
  // retries until the user taps Retry, which clears both fields.
  TextColumn get syncError => text().nullable()();
  DateTimeColumn get syncFailedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Mirrors `CheckIn` in `backend/core/models.py`.
///
/// - `visitType` splits MEMBER vs WALKIN rows, same split as the backend
///   model — see its own comments for why they share one table.
/// - `memberId` is null for walk-ins, matching the backend's nullable FK.
/// - `amountChargedCentavos` is parsed from the wire's decimal string via
///   `parseCentavos`, same convention as MembershipPlans.priceCentavos —
///   never through double. Null for member check-ins, and for walk-ins
///   where staff skipped entering a price.
/// - `isDirty` / `pendingPayload` / `syncError` / `syncFailedAt` mirror the
///   offline-write pattern added to Members in 3.10b.
class CheckIns extends Table {
  TextColumn get id => text()();
  TextColumn get gymId => text()(); // not in the serializer — stamp on ingest
  TextColumn get visitType => text()(); // MEMBER | WALKIN
  TextColumn get memberId => text().nullable()();
  TextColumn get locationId => text()();
  DateTimeColumn get checkedInAt => dateTime()();
  TextColumn get membershipStatus => text().withDefault(const Constant(''))();
  DateTimeColumn get membershipEndDate => dateTime().nullable()();
  TextColumn get visitorName => text().withDefault(const Constant(''))();
  TextColumn get category =>
      text().withDefault(const Constant(''))(); // regular | student
  IntColumn get amountChargedCentavos => integer().nullable()();
  DateTimeColumn get voidedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isDirty => boolean().withDefault(const Constant(false))();
  TextColumn get pendingPayload => text().nullable()();
  TextColumn get syncError => text().nullable()();
  DateTimeColumn get syncFailedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
