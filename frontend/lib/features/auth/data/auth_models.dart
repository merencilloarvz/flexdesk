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
  final bool classesEnabled;
  final String? subscriptionStatus;
  final bool subscriptionBlocked;
  final DateTime? trialEndsAt;

  const Gym({
    required this.id,
    required this.name,
    required this.timezone,
    required this.currency,
    required this.needsSetup,
    required this.classesEnabled,
    required this.subscriptionStatus,
    required this.subscriptionBlocked,
    required this.trialEndsAt,
  });

  factory Gym.fromJson(Map<String, dynamic> json) => Gym(
    id: json['id'].toString(),
    name: json['name'] as String? ?? '',
    timezone: json['timezone'] as String? ?? 'Asia/Manila',
    currency: json['currency'] as String? ?? 'PHP',
    needsSetup: json['needs_setup'] as bool? ?? false,
    // A cached session from before this field existed has no such key —
    // defaults to false so an old session never shows a Schedule tab
    // that then 403s.
    classesEnabled: json['classes_enabled'] as bool? ?? false,
    subscriptionStatus: json['subscription_status'] as String?,
    // Same reasoning as classesEnabled above — a cached session from
    // before Stage 10 has no such key, and must never suddenly lock a
    // signed-in owner out of their own app until the next real refresh.
    subscriptionBlocked: json['subscription_blocked'] as bool? ?? false,
    trialEndsAt: json['trial_ends_at'] != null
        ? DateTime.tryParse(json['trial_ends_at'] as String)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'timezone': timezone,
    'currency': currency,
    'needs_setup': needsSetup,
    'classes_enabled': classesEnabled,
    'subscription_status': subscriptionStatus,
    'subscription_blocked': subscriptionBlocked,
    'trial_ends_at': trialEndsAt?.toIso8601String(),
  };

  Gym copyWith({bool? classesEnabled}) => Gym(
    id: id,
    name: name,
    timezone: timezone,
    currency: currency,
    needsSetup: needsSetup,
    classesEnabled: classesEnabled ?? this.classesEnabled,
    subscriptionStatus: subscriptionStatus,
    subscriptionBlocked: subscriptionBlocked,
    trialEndsAt: trialEndsAt,
  );
}

class AuthUser {
  final String id;
  final String email;
  final String fullName;
  final String? defaultLocationId;
  final UserRole role;
  final String? accountType;
  // Null for an account with neither a StaffProfile nor a member_profile
  // — a Django superuser, or a profile that got removed. Never assume
  // this is set; the router sends anyone with gym == null to
  // NoGymScreen before any gym-dependent screen gets a chance to build.
  final Gym? gym;
  final bool mustChangePassword;

  const AuthUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.defaultLocationId,
    required this.role,
    required this.accountType,
    required this.gym,
    required this.mustChangePassword,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    // Sessions cached before account_type existed have no such field. A
    // staff user always has a non-null role; a member never does. Deriving
    // here means an existing logged-in owner survives the upgrade without
    // a forced re-login — which they might not be able to complete if
    // they're offline. Do NOT tighten this to a hard field requirement.
    final accountType =
        json['account_type'] as String? ??
        (json['role'] != null ? 'staff' : null);

    return AuthUser(
      id: json['id'].toString(),
      email: json['email'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      defaultLocationId: json['default_location_id']?.toString(),
      role: _parseRole(json['role'] as String?),
      accountType: accountType,
      gym: json['gym'] is Map<String, dynamic>
          ? Gym.fromJson(json['gym'] as Map<String, dynamic>)
          : null,
      mustChangePassword: json['must_change_password'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'full_name': fullName,
    'default_location_id': defaultLocationId,
    'role': role.name,
    'account_type': accountType,
    'gym': gym?.toJson(),
    'must_change_password': mustChangePassword,
  };

  bool get isMember => accountType == 'member';

  AuthUser copyWith({bool? mustChangePassword, Gym? gym}) => AuthUser(
    id: id,
    email: email,
    fullName: fullName,
    defaultLocationId: defaultLocationId,
    role: role,
    accountType: accountType,
    gym: gym ?? this.gym,
    mustChangePassword: mustChangePassword ?? this.mustChangePassword,
  );
}
