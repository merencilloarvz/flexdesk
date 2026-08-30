import 'package:dio/dio.dart';

enum ApiExceptionKind {
  network,
  unauthorized,
  forbidden,
  notFound,
  validation,
  throttled,
  server,
  cancelled,
  unknown,
}

class ApiException implements Exception {
  final ApiExceptionKind kind;
  final String message;
  final Map<String, List<String>>? fieldErrors;
  final Duration? retryAfter;

  ApiException({
    required this.kind,
    required this.message,
    this.fieldErrors,
    this.retryAfter,
  });

  factory ApiException.from(DioException e) {
    final kind = _kindFrom(e);
    final data = e.response?.data;

    String message = 'Something went wrong. Please try again.';
    Map<String, List<String>>? fieldErrors;

    if (data is Map<String, dynamic>) {
      if (data['detail'] is String) {
        message = data['detail'] as String;
      }

      final parsed = <String, List<String>>{};
      data.forEach((key, value) {
        if (key != 'detail' && value is List) {
          final strings = value.map((v) => v.toString()).toList();
          if (strings.isNotEmpty) parsed[key] = strings;
        }
      });
      if (parsed.isNotEmpty) fieldErrors = parsed;

      if (data['detail'] is! String) {
        if (data['non_field_errors'] is List &&
            (data['non_field_errors'] as List).isNotEmpty) {
          message = (data['non_field_errors'] as List).join(' ');
        } else if (fieldErrors != null && fieldErrors.isNotEmpty) {
          final firstList = fieldErrors.values.first;
          if (firstList.isNotEmpty) message = firstList.first;
        }
      }
    }

    Duration? retryAfter;
    if (kind == ApiExceptionKind.throttled) {
      final header = e.response?.headers.value('Retry-After');
      final seconds = int.tryParse(header ?? '');
      if (seconds != null) retryAfter = Duration(seconds: seconds);
    }

    switch (kind) {
      case ApiExceptionKind.network:
        message = 'No connection. Changes will sync when you\'re back online.';
        break;
      case ApiExceptionKind.throttled:
        message = 'Too many attempts. Try again shortly.';
        break;
      default:
        break;
    }

    return ApiException(
      kind: kind,
      message: message,
      fieldErrors: fieldErrors,
      retryAfter: retryAfter,
    );
  }

  static ApiExceptionKind _kindFrom(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return ApiExceptionKind.network;
      case DioExceptionType.cancel:
        return ApiExceptionKind.cancelled;
      default:
        break;
    }

    final status = e.response?.statusCode;
    if (status == 401) return ApiExceptionKind.unauthorized;
    if (status == 403) return ApiExceptionKind.forbidden;
    if (status == 404) return ApiExceptionKind.notFound;
    if (status == 400) return ApiExceptionKind.validation;
    if (status == 429) return ApiExceptionKind.throttled;
    if (status != null && status >= 500) return ApiExceptionKind.server;

    return ApiExceptionKind.unknown;
  }
}
