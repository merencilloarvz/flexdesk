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

  /// Returns the PayMongo checkout URL to open. Throws ApiException with
  /// the backend's placeholder message while PayMongo isn't configured
  /// yet — see SubscriptionCheckoutView on the backend.
  Future<String> createCheckoutSession() async {
    try {
      final response = await _dio.post('/subscription/checkout/');
      final data = response.data as Map<String, dynamic>;
      return data['checkout_url'] as String;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }
}
