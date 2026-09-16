class SubscriptionStatus {
  final String status;
  final DateTime trialEndsAt;
  final DateTime? currentPeriodEnd;
  final bool isBlocked;
  final int? daysRemaining;
  final String billingState;

  const SubscriptionStatus({
    required this.status,
    required this.trialEndsAt,
    required this.currentPeriodEnd,
    required this.isBlocked,
    required this.daysRemaining,
    required this.billingState,
  });

  bool get isTrialing => status == 'trialing';

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) =>
      SubscriptionStatus(
        status: json['status'] as String,
        trialEndsAt: DateTime.parse(json['trial_ends_at'] as String),
        currentPeriodEnd: json['current_period_end'] != null
            ? DateTime.parse(json['current_period_end'] as String)
            : null,
        isBlocked: json['is_blocked'] as bool,
        daysRemaining: json['days_remaining'] as int?,
        billingState: json['billing_state'] as String,
      );
}

/// How to pay and how to reach the operator — fetched from the backend
/// so a GCash number or price change never needs a new APK build.
class PaymentInfo {
  final int priceMonthlyCentavos;
  final int priceYearlyCentavos;
  final String paymentInstructions;
  final String contactInfo;

  const PaymentInfo({
    required this.priceMonthlyCentavos,
    required this.priceYearlyCentavos,
    required this.paymentInstructions,
    required this.contactInfo,
  });

  factory PaymentInfo.fromJson(Map<String, dynamic> json) => PaymentInfo(
    priceMonthlyCentavos: json['price_monthly_centavos'] as int,
    priceYearlyCentavos: json['price_yearly_centavos'] as int,
    paymentInstructions: json['payment_instructions'] as String,
    contactInfo: json['contact_info'] as String,
  );
}
