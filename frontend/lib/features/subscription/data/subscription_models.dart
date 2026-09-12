class SubscriptionStatus {
  final String status;
  final DateTime trialEndsAt;
  final bool isBlocked;
  final int? daysRemaining;

  const SubscriptionStatus({
    required this.status,
    required this.trialEndsAt,
    required this.isBlocked,
    required this.daysRemaining,
  });

  bool get isTrialing => status == 'trialing';

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) =>
      SubscriptionStatus(
        status: json['status'] as String,
        trialEndsAt: DateTime.parse(json['trial_ends_at'] as String),
        isBlocked: json['is_blocked'] as bool,
        daysRemaining: json['days_remaining'] as int?,
      );
}
