import 'staff_api.dart';
import 'staff_models.dart';

/// Thin wrapper around StaffApi — converts raw JSON into StaffMember
/// objects. No caching, no Drift: staff management is a rare, owner-only
/// admin action, so every call goes straight to the network, same as the
/// plan doc calls for.
class StaffRepository {
  StaffRepository(this._api);

  final StaffApi _api;

  Future<List<StaffMember>> fetchStaff() async {
    final raw = await _api.fetchAllStaff();
    return raw.map(StaffMember.fromJson).toList();
  }

  Future<StaffMember> createStaff({
    required String fullName,
    required String email,
    required String password,
    required String role, // 'owner' or 'staff'
  }) async {
    final body = {
      'full_name': fullName,
      // Lowercase/trim here too, even though the server also does it in
      // validate_email — keeps the duplicate-email check predictable.
      'email': email.trim().toLowerCase(),
      'password': password,
      'role': role,
      // default_location deliberately omitted — there's no /locations/
      // endpoint to populate a picker with, so we let the server fall
      // back to the owner's own default_location.
    };
    final json = await _api.createStaff(body);
    return StaffMember.fromJson(json);
  }

  Future<void> deactivateStaff(String staffProfileId) {
    return _api.deactivateStaff(staffProfileId);
  }
}
