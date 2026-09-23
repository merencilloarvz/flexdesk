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

  /// The notification types relevant to the caller's own role — owners
  /// get owner-facing types, members get member-facing types (the
  /// backend filters by TYPE_CATALOG's audience, not the client).
  Future<List<NotificationTestType>> fetchTestTypes() async {
    final response = await _dio.get('/devices/test/');
    final types = response.data['types'] as List;
    return types
        .map((t) => NotificationTestType(
              type: t['type'] as String,
              label: t['label'] as String,
            ))
        .toList();
  }

  /// Sends one sample of `type` to the logged-in user's own devices —
  /// lets someone confirm delivery end-to-end with only the one phone
  /// they're holding, from the Settings screen.
  Future<void> sendTest(String type) {
    return _dio.post('/devices/test/', data: {'type': type});
  }
}

class NotificationTestType {
  const NotificationTestType({required this.type, required this.label});
  final String type;
  final String label;
}
