import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/ingest.dart';
import 'plans_api.dart';

/// Fetch-and-cache for membership plans: hits the API, writes into Drift,
/// and lets the UI read from Drift only.
class PlansRepository {
  PlansRepository(this._api, this._db);

  final PlansApi _api;
  final AppDatabase _db;

  /// Fetches every plan for [gymId] and syncs the local cache to match.
  ///
  /// Plans use real replace-set delete (unlike members' archive-based
  /// approach) because MembershipPlanViewSet is a plain ModelViewSet — an
  /// owner can genuinely DELETE a plan row, confirmed by the backend
  /// having no destroy() override.
  Future<void> refreshPlans(String gymId) async {
    final rawPlans = await _api.fetchAllPlans();

    final rows = rawPlans
        .map((json) => membershipPlanFromJson(json, gymId))
        .toList();
    final fetchedIds = rawPlans.map((json) => json['id'] as String).toSet();

    await _db.transaction(() async {
      await _db.batch(
        (b) => b.insertAllOnConflictUpdate(_db.membershipPlans, rows),
      );

      await (_db.delete(_db.membershipPlans)..where(
            (p) =>
                p.gymId.equals(gymId) &
                p.isDirty.equals(false) &
                p.id.isNotIn(fetchedIds),
          ))
          .go();
    });
  }

  /// Streams active plans for [gymId] — what the member-create and renew
  /// pickers watch.
  Stream<List<MembershipPlan>> watchActivePlans(String gymId) =>
      (_db.select(_db.membershipPlans)
            ..where((p) => p.gymId.equals(gymId) & p.isActive.equals(true))
            ..orderBy([
              (p) => OrderingTerm(expression: p.sortOrder),
              (p) => OrderingTerm(expression: p.category),
              (p) => OrderingTerm(expression: p.name),
            ]))
          .watch();

  /// Streams every plan for [gymId], active or not — what the manage-plans
  /// screen watches, since an owner needs to see (and reactivate) an
  /// inactive plan too.
  Stream<List<MembershipPlan>> watchAllPlans(String gymId) =>
      (_db.select(_db.membershipPlans)
            ..where((p) => p.gymId.equals(gymId))
            ..orderBy([
              (p) => OrderingTerm(expression: p.sortOrder),
              (p) => OrderingTerm(expression: p.category),
              (p) => OrderingTerm(expression: p.name),
            ]))
          .watch();

  /// Creates a plan and inserts the server's canonical response locally.
  /// No offline queueing here — see the doc comment on PlansApi.createPlan
  /// for why that's an intentional gap for v1, not an oversight.
  Future<void> createPlan({
    required String gymId,
    required String name,
    required String category,
    required int durationValue,
    required String durationUnit,
    required double price,
    required bool isDayPass,
    bool isActive = true,
    int sortOrder = 0,
  }) async {
    final body = {
      'name': name,
      'category': category,
      'duration_value': durationValue,
      'duration_unit': durationUnit,
      'price': price.toStringAsFixed(2),
      'is_day_pass': isDayPass,
      'is_active': isActive,
      'sort_order': sortOrder,
    };
    final json = await _api.createPlan(body);
    await _db
        .into(_db.membershipPlans)
        .insertOnConflictUpdate(membershipPlanFromJson(json, gymId));
  }

  /// Updates a plan by [id]. Only pass the fields that changed — this
  /// sends a PATCH, not a full PUT.
  Future<void> updatePlan({
    required String id,
    required String gymId,
    String? name,
    String? category,
    int? durationValue,
    String? durationUnit,
    double? price,
    bool? isDayPass,
    bool? isActive,
    int? sortOrder,
  }) async {
    final body = <String, dynamic>{
      if (name != null) 'name': name,
      if (category != null) 'category': category,
      if (durationValue != null) 'duration_value': durationValue,
      if (durationUnit != null) 'duration_unit': durationUnit,
      if (price != null) 'price': price.toStringAsFixed(2),
      if (isDayPass != null) 'is_day_pass': isDayPass,
      if (isActive != null) 'is_active': isActive,
      if (sortOrder != null) 'sort_order': sortOrder,
    };
    final json = await _api.updatePlan(id, body);
    await _db
        .into(_db.membershipPlans)
        .insertOnConflictUpdate(membershipPlanFromJson(json, gymId));
  }

  /// Deletes a plan on the server, then removes the local row. This is a
  /// real, irreversible delete — the screen is responsible for confirming
  /// with the user and steering them toward deactivating instead when a
  /// plan has membership history attached.
  Future<void> deletePlan(String id) async {
    await _api.deletePlan(id);
    await (_db.delete(_db.membershipPlans)..where((p) => p.id.equals(id))).go();
  }
}
