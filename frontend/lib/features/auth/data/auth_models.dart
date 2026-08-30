enum UserRole { owner, staff, unknown }

UserRole _parseRole(String? value) {
  switch (value?.toLowerCase()) {
    case 'owner':
      return UserRole.owner;
    case 'staff':
      return UserRole.staff;
    default:
      return UserRole.unknown; // never throw on an unexpected role string
  }
}

class AuthTokens {
  final String access;
  final String refresh;

  const AuthTokens({required this.access, required this.refresh});

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
    access: json['access'] as String,
    refresh: json['refresh'] as String,
  );
}

class Gym {
  final String id;
  final String name;
  final String timezone;
  final String currency;
  final bool needsSetup;

  const Gym({
    required this.id,
    required this.name,
    required this.timezone,
    required this.currency,
    required this.needsSetup,
  });

  factory Gym.fromJson(Map<String, dynamic> json) => Gym(
    id: json['id'].toString(),
    name: json['name'] as String? ?? '',
    // Defaults, not hard casts: a cache written by the pre-fix toJson()
    // has no timezone/currency key and must still parse on next launch.
    timezone: json['timezone'] as String? ?? 'Asia/Manila',
    currency: json['currency'] as String? ?? 'PHP',
    needsSetup: json['needs_setup'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'timezone': timezone,
    'currency': currency,
    'needs_setup': needsSetup,
  };
}

class AuthUser {
  final String id;
  final String email;
  final String fullName;
  final String? defaultLocationId;
  final UserRole role;
  final Gym gym;
  final bool mustChangePassword;

  const AuthUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.defaultLocationId,
    required this.role,
    required this.gym,
    required this.mustChangePassword,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['id'].toString(),
    email: json['email'] as String? ?? '',
    fullName: json['full_name'] as String? ?? '',
    defaultLocationId: json['default_location_id']?.toString(),
    role: _parseRole(json['role'] as String?),
    gym: Gym.fromJson(json['gym'] as Map<String, dynamic>),
    mustChangePassword: json['must_change_password'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'full_name': fullName,
    'default_location_id': defaultLocationId,
    'role': role.name,
    'gym': gym.toJson(),
    'must_change_password': mustChangePassword,
  };

  AuthUser copyWith({bool? mustChangePassword}) => AuthUser(
    id: id,
    email: email,
    fullName: fullName,
    defaultLocationId: defaultLocationId,
    role: role,
    gym: gym,
    mustChangePassword: mustChangePassword ?? this.mustChangePassword,
  );
}
