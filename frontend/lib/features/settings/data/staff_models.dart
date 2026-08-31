import '../../auth/data/auth_models.dart' show UserRole;

UserRole _parseStaffRole(String? value) {
  switch (value?.toLowerCase()) {
    case 'owner':
      return UserRole.owner;
    case 'staff':
      return UserRole.staff;
    default:
      return UserRole.unknown; // never throw on an unexpected role string
  }
}

/// One staffer, as returned by StaffMemberSerializer.
///
/// IMPORTANT: `id` here is the StaffProfile id, NOT the User id.
/// The serializer pulls email/fullName/isActive from the nested user,
/// but exposes the profile's own id — and every /staff/ endpoint path
/// uses that profile id. Mixing this up produces 404s that look like
/// permission errors.
class StaffMember {
  final String id;
  final String email;
  final String fullName;
  final UserRole role;
  final bool isActive;
  final String? defaultLocationId;
  final DateTime createdAt;

  const StaffMember({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.isActive,
    required this.defaultLocationId,
    required this.createdAt,
  });

  factory StaffMember.fromJson(Map<String, dynamic> json) => StaffMember(
    id: json['id'].toString(),
    email: json['email'] as String? ?? '',
    fullName: json['full_name'] as String? ?? '',
    role: _parseStaffRole(json['role'] as String?),
    isActive: json['is_active'] as bool? ?? true,
    defaultLocationId: json['default_location']?.toString(),
    createdAt: DateTime.parse(json['created_at'] as String),
  );
}
