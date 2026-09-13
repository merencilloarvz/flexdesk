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
  // A blocked gym's subscription (402) — never network, never a payload
  // problem, and never auto-retryable on its own: retrying does nothing
  // until the owner pays. Kept distinct from `unknown` so callers (the
  // offline queue in particular) can tell "the server is having a bad
  // day" apart from "this gym needs to subscribe".
  subscriptionRequired,
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
    if (status == 402) return ApiExceptionKind.subscriptionRequired;
    if (status == 403) return ApiExceptionKind.forbidden;
    if (status == 404) return ApiExceptionKind.notFound;
    if (status == 400) return ApiExceptionKind.validation;
    if (status == 429) return ApiExceptionKind.throttled;
    if (status != null && status >= 500) return ApiExceptionKind.server;

    return ApiExceptionKind.unknown;
  }
}

/// The message to persist on a locally-queued row's syncError field when
/// a create attempt is rejected outside the retryable/duplicate cases —
/// shared by the offline-queue repositories so the two never drift apart
/// on what gets stored there.
///
/// Deliberately NEVER the raw backend text for a blocked subscription:
/// that's gym-level billing state (already surfaced by the
/// subscription_blocked banner from /auth/me/), not something that
/// belongs sitting next to a check-in or member row out of context,
/// possibly seen by someone other than whoever attempted the action.
/// Every other kind still uses the server's own message — it's still
/// useful context for a genuinely failed row.
String rowSyncErrorMessage(ApiException e) {
  if (e.kind == ApiExceptionKind.subscriptionRequired) {
    return "Couldn't sync — the gym's FlexDesk subscription needs attention";
  }
  return e.message;
}
