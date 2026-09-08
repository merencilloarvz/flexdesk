import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';

/// Talks to the POS/Inventory endpoints. Deliberately no local caching
/// layer underneath this — see the repository for why. Stock is
/// contended, finite state (Stage 8, D1): a cached count is a lie the
/// moment another device sells the last unit.
class PosApi {
  PosApi(this._dio);

  final Dio _dio;

  // ---- Products ----

  Future<List<Map<String, dynamic>>> fetchProducts({
    bool? lowStock,
    bool? outOfStock,
  }) async {
    var page = 1;
    final all = <Map<String, dynamic>>[];
    try {
      while (true) {
        final response = await _dio.get(
          '/products/',
          queryParameters: {
            'page': page,
            if (lowStock == true) 'low_stock': '1',
            if (outOfStock == true) 'out_of_stock': '1',
          },
        );
        final body = response.data as Map<String, dynamic>;
        all.addAll((body['results'] as List).cast<Map<String, dynamic>>());
        if (body['next'] == null) break;
        page++;
        if (page > 200) {
          throw ApiException(
            kind: ApiExceptionKind.unknown,
            message:
                'Product list is unexpectedly large. Please contact support.',
          );
        }
      }
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
    return all;
  }

  Future<Map<String, dynamic>> createProduct(Map<String, dynamic> body) async {
    try {
      final response = await _dio.post('/products/', data: body);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<Map<String, dynamic>> updateProduct(
    String id,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _dio.patch('/products/$id/', data: body);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<Map<String, dynamic>> adjustStock(
    String productId, {
    required int delta,
    String reason = '',
  }) async {
    try {
      final response = await _dio.post(
        '/products/$productId/adjust/',
        data: {'delta': delta, 'reason': reason},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<List<Map<String, dynamic>>> fetchAdjustments(String productId) async {
    try {
      final response = await _dio.get('/products/$productId/adjustments/');
      return (response.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  // ---- Sales ----

  Future<List<Map<String, dynamic>>> fetchSales({String? date}) async {
    var page = 1;
    final all = <Map<String, dynamic>>[];
    try {
      while (true) {
        final response = await _dio.get(
          '/sales/',
          queryParameters: {'page': page, if (date != null) 'date': date},
        );
        final body = response.data as Map<String, dynamic>;
        all.addAll((body['results'] as List).cast<Map<String, dynamic>>());
        if (body['next'] == null) break;
        page++;
        if (page > 200) {
          throw ApiException(
            kind: ApiExceptionKind.unknown,
            message:
                'Sales list is unexpectedly large. Please contact support.',
          );
        }
      }
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
    return all;
  }

  Future<Map<String, dynamic>> fetchSale(String id) async {
    try {
      final response = await _dio.get('/sales/$id/');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<Map<String, dynamic>> createSale({
    required List<Map<String, dynamic>> items,
    String? memberId,
  }) async {
    try {
      final response = await _dio.post(
        '/sales/',
        data: {'items': items, if (memberId != null) 'member': memberId},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> voidSale(String id) async {
    try {
      await _dio.post('/sales/$id/void/');
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  // ---- Inventory alerts ----

  Future<Map<String, dynamic>> fetchInventoryAlerts() async {
    try {
      final response = await _dio.get('/inventory/alerts/');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }
}
