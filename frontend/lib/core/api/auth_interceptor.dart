import 'dart:async';
import 'package:dio/dio.dart';
import 'token_storage.dart';
import 'api_config.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

class AuthInterceptor extends Interceptor {
  final TokenStorage _tokenStorage;
  final void Function() onSessionExpired;

  static const _skipPaths = {'/auth/login/', '/auth/refresh/', '/auth/signup/'};

  // Bare Dio, no interceptors — used only for the refresh call itself
  // and for manually retrying a failed request. Keeps this class from
  // triggering itself recursively through the main client.
  final Dio _plainDio;

  Completer<String?>? _refreshCompleter;

  AuthInterceptor({
    required TokenStorage tokenStorage,
    required String baseUrl,
    required this.onSessionExpired,
  }) : _tokenStorage = tokenStorage,
       _plainDio = Dio(
         BaseOptions(
           baseUrl: baseUrl,
           connectTimeout: ApiConfig.connectTimeout,
           receiveTimeout: ApiConfig.receiveTimeout,
           sendTimeout: ApiConfig.sendTimeout,
         ),
       );

  bool _isSkipped(String path) => _skipPaths.any((skip) => path.contains(skip));

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_isSkipped(options.path)) {
      final access = await _tokenStorage.readAccess();
      if (access != null) {
        options.headers['Authorization'] = 'Bearer $access';
      }
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final path = err.requestOptions.path;
    final status = err.response?.statusCode;
    final code = err.response?.data is Map ? err.response?.data['code'] : null;
    final alreadyRetried = err.requestOptions.extra['_retried'] == true;

    final shouldRefresh =
        status == 401 &&
        !_isSkipped(path) &&
        code == 'token_not_valid' &&
        !alreadyRetried;

    if (!shouldRefresh) {
      handler.next(err);
      return;
    }

    String? newAccess;
    try {
      newAccess = await _refresh();
    } catch (refreshErr) {
      // Broadened from `on DioException`: _doRefresh can also throw a
      // TypeError or similar if a proxy/captive portal returns a 200 with
      // an unexpected body. Every path out of onError must call handler
      // exactly once — wrapping non-DioException errors keeps that true.
      handler.next(
        refreshErr is DioException
            ? refreshErr
            : DioException(
                requestOptions: err.requestOptions,
                type: DioExceptionType.unknown,
                error: refreshErr,
              ),
      );
      return;
    }

    if (newAccess == null) {
      // _refresh() determined the session is genuinely dead
      // (onSessionExpired already fired inside _doRefresh).
      handler.next(err);
      return;
    }

    try {
      final retryOptions = err.requestOptions;
      retryOptions.extra['_retried'] = true;
      retryOptions.headers['Authorization'] = 'Bearer $newAccess';

      final response = await _plainDio.fetch(retryOptions);
      if (kDebugMode) debugPrint('↻ retried ${retryOptions.path}');
      handler.resolve(response);
    } on DioException catch (retryErr) {
      handler.next(retryErr);
    }
  }

  /// Returns the new access token, or null if the session is genuinely
  /// dead. Throws a DioException if refresh failed due to a network
  /// problem (caller should treat that as "offline", not "logged out").
  /// Single-flight: concurrent callers await the same in-flight refresh.
  Future<String?> _refresh() {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    final completer = Completer<String?>();
    _refreshCompleter = completer;
    _doRefresh()
        .then((token) {
          completer.complete(token);
          _refreshCompleter = null;
        })
        .catchError((e) {
          completer.completeError(e);
          _refreshCompleter = null;
        });

    return completer.future;
  }

  Future<String?> _doRefresh() async {
    final refreshToken = await _tokenStorage.readRefresh();
    if (refreshToken == null) {
      await _tokenStorage.clear();
      onSessionExpired();
      return null;
    }

    try {
      final response = await _plainDio.post(
        '/auth/refresh/',
        data: {'refresh': refreshToken},
      );

      final newAccess = response.data is Map
          ? response.data['access'] as String?
          : null;
      if (newAccess == null) {
        await _tokenStorage.clear();
        onSessionExpired();
        return null;
      }

      final newRefresh =
          response.data['refresh'] as String?; // rotated, may be absent
      await _tokenStorage.saveTokens(
        access: newAccess,
        refresh: newRefresh ?? refreshToken,
      );
      return newAccess;
    } on DioException catch (e) {
      final status = e.response?.statusCode;

      if (status == 401 || status == 400) {
        // Server explicitly rejected the refresh token — session is dead.
        await _tokenStorage.clear();
        onSessionExpired();
        return null;
      }

      // Anything else (connectionError, timeout, etc.) is a network
      // problem, not an expired session. Rethrow so onError can tell
      // the two apart and NOT log the user out over a dropped signal.
      rethrow;
    }
  }
}
