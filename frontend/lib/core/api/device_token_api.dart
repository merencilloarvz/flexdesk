import 'package:dio/dio.dart';

/// Thin wrapper around POST/DELETE /devices/ (Phase 4 Part A, backend
/// already merged). Not gym-scoped — see backend core.models.DeviceToken.
class DeviceTokenApi {
  final Dio _dio;
  DeviceTokenApi(this._dio);

  /// Idempotent — the same token registered twice is one row on the
  /// server, reassigned to whoever is calling now.
  Future<void> register({required String token, required String platform}) {
    return _dio.post('/devices/', data: {'token': token, 'platform': platform});
  }

  Future<void> delete(String token) {
    return _dio.delete('/devices/', data: {'token': token});
  }

  /// Sends a push to the logged-in user's own devices — lets someone
  /// confirm delivery end-to-end with only the one phone they're
  /// holding, from the Settings screen.
  Future<void> sendTest() {
    return _dio.post('/devices/test/');
  }
}
