import 'package:drift/drift.dart';
import 'package:flexdesk/core/db/app_database.dart';

import 'tables.dart';
import '../utils/money.dart';

/// Maps a `/plans/` JSON object into an insertable row.
///
/// [gymId] is stamped from the logged-in user's `gym.id` — the serializer
/// never returns `gym`, since it's implicit from tenant scoping.
MembershipPlansCompanion membershipPlanFromJson(
  Map<String, dynamic> json,
  String gymId,
) {
  return MembershipPlansCompanion.insert(
    id: json['id'] as String,
    gymId: gymId,
    name: json['name'] as String,
    category: Value(json['category'] as String? ?? ''),
    durationValue: json['duration_value'] as int,
    durationUnit: json['duration_unit'] as String,
    priceCentavos: parseCentavos(json['price'] as String),
    isDayPass: json['is_day_pass'] as bool,
    isActive: json['is_active'] as bool,
    sortOrder: json['sort_order'] as int,
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );
}

/// Maps a `/members/` JSON object into an insertable row.
MembersCompanion memberFromJson(Map<String, dynamic> json, String gymId) {
  return MembersCompanion.insert(
    id: json['id'] as String,
    gymId: gymId,
    homeLocationId: json['home_location'] as String,
    memberCode: Value(json['member_code'] as String? ?? ''),
    firstName: json['first_name'] as String,
    lastName: Value(json['last_name'] as String? ?? ''),
    phone: Value(json['phone'] as String? ?? ''),
    email: Value(json['email'] as String? ?? ''),
    dateOfBirth: Value(
      json['date_of_birth'] != null
          ? DateTime.parse(json['date_of_birth'] as String)
          : null,
    ),
    memberType: json['member_type'] as String,
    notes: Value(json['notes'] as String? ?? ''),
    currentEndDate: Value(
      json['current_end_date'] != null
          ? DateTime.parse(json['current_end_date'] as String)
          : null,
    ),
    // Empty string from the backend means "has a membership but no
    // category set" — kept distinct from null ("no membership at all")
    // rather than collapsing both to null, so the list tile can tell
    // "no badge because no plan" apart from "no badge because this plan
    // has no category".
    currentPlanCategory: Value(json['current_plan_category'] as String?),
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    archivedAt: Value(
      json['archived_at'] != null
          ? DateTime.parse(json['archived_at'] as String)
          : null,
    ),
  );
}

/// Maps a `/check-ins/` JSON object into an insertable row.
CheckInsCompanion checkInFromJson(Map<String, dynamic> json, String gymId) {
  return CheckInsCompanion.insert(
    id: json['id'] as String,
    gymId: gymId,
    visitType: json['visit_type'] as String,
    memberId: Value(json['member'] as String?),
    locationId: json['location'] as String,
    checkedInAt: DateTime.parse(json['checked_in_at'] as String),
    membershipStatus: Value(json['membership_status'] as String? ?? ''),
    membershipEndDate: Value(
      json['membership_end_date'] != null
          ? DateTime.parse(json['membership_end_date'] as String)
          : null,
    ),
    visitorName: Value(json['visitor_name'] as String? ?? ''),
    category: Value(json['category'] as String? ?? ''),
    amountChargedCentavos: Value(
      json['amount_charged'] != null
          ? parseCentavos(json['amount_charged'] as String)
          : null,
    ),
    voidedAt: Value(
      json['voided_at'] != null
          ? DateTime.parse(json['voided_at'] as String)
          : null,
    ),
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );
}
