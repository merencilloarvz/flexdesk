import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_interceptor.dart';
import 'api_config.dart';
import 'token_storage.dart';
import '../../features/auth/providers/auth_providers.dart';

Dio _buildDio(
  TokenStorage tokenStorage, {
  required void Function() onSessionExpired,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
      sendTimeout: ApiConfig.sendTimeout,
    ),
  );

  if (kDebugMode) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          debugPrint('→ ${options.method} ${options.path}');
          handler.next(options);
        },
        onResponse: (response, handler) {
          debugPrint(
            '← ${response.statusCode} ${response.requestOptions.path}',
          );
          handler.next(response);
        },
        onError: (err, handler) {
          debugPrint(
            '✗ ${err.response?.statusCode} ${err.requestOptions.path} — ${err.message}',
          );
          handler.next(err);
        },
      ),
    );
  }

  dio.interceptors.add(
    AuthInterceptor(
      tokenStorage: tokenStorage,
      baseUrl: ApiConfig.baseUrl,
      onSessionExpired: onSessionExpired,
    ),
  );

  return dio;
}

final dioProvider = Provider<Dio>((ref) {
  return _buildDio(
    ref.watch(tokenStorageProvider),
    onSessionExpired: () =>
        ref.read(authControllerProvider.notifier).handleSessionExpired(),
  );
});
