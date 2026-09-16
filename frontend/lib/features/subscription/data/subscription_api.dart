import 'package:dio/dio.dart';
import '../../../core/api/api_exception.dart';
import 'subscription_models.dart';

class SubscriptionApi {
  final Dio _dio;
  SubscriptionApi(this._dio);

  Future<SubscriptionStatus> fetchStatus() async {
    try {
      final response = await _dio.get('/subscription/');
      return SubscriptionStatus.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  /// Price and contact details for the manual-payment flow — the owner
  /// pays outside the app and messages the operator, so this is
  /// informational only, never a checkout call.
  Future<PaymentInfo> fetchPaymentInfo() async {
    try {
      final response = await _dio.get('/subscription/payment-info/');
      return PaymentInfo.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }
}
