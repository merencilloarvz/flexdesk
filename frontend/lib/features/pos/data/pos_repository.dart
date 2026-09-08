import '../../../core/api/api_exception.dart';
import '../../../core/utils/money.dart';
import 'pos_api.dart';

class Product {
  Product({
    required this.id,
    required this.name,
    required this.category,
    required this.priceCentavos,
    required this.stockQuantity,
    required this.lowStockThreshold,
    required this.isActive,
  });

  final String id;
  final String name;
  final String category;
  final int priceCentavos;
  final int stockQuantity;
  final int lowStockThreshold;
  final bool isActive;

  bool get isOutOfStock => stockQuantity <= 0;
  bool get isLowStock => !isOutOfStock && stockQuantity <= lowStockThreshold;

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: json['id'] as String,
    name: json['name'] as String,
    category: json['category'] as String? ?? '',
    priceCentavos: parseCentavos(json['price'] as String),
    stockQuantity: json['stock_quantity'] as int,
    lowStockThreshold: json['low_stock_threshold'] as int,
    isActive: json['is_active'] as bool,
  );
}

class SaleItem {
  SaleItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.unitPriceCentavos,
    required this.quantity,
    required this.lineTotalCentavos,
  });

  final String id;
  final String productId;
  final String productName;
  final int unitPriceCentavos;
  final int quantity;
  final int lineTotalCentavos;

  factory SaleItem.fromJson(Map<String, dynamic> json) => SaleItem(
    id: json['id'] as String,
    productId: json['product'] as String,
    productName: json['product_name'] as String,
    unitPriceCentavos: parseCentavos(json['unit_price'] as String),
    quantity: json['quantity'] as int,
    lineTotalCentavos: parseCentavos(json['line_total'] as String),
  );
}

class Sale {
  Sale({
    required this.id,
    required this.memberId,
    required this.memberName,
    required this.totalAmountCentavos,
    required this.soldAt,
    required this.soldByName,
    required this.voidedAt,
    required this.items,
  });

  final String id;
  final String? memberId;
  final String? memberName;
  final int totalAmountCentavos;
  final DateTime soldAt;
  final String? soldByName;
  final DateTime? voidedAt;
  final List<SaleItem> items;

  bool get isVoided => voidedAt != null;

  factory Sale.fromJson(Map<String, dynamic> json) => Sale(
    id: json['id'] as String,
    memberId: json['member'] as String?,
    memberName: json['member_name'] as String?,
    totalAmountCentavos: parseCentavos(json['total_amount'] as String),
    soldAt: DateTime.parse(json['sold_at'] as String),
    soldByName: json['sold_by_name'] as String?,
    voidedAt: json['voided_at'] != null
        ? DateTime.parse(json['voided_at'] as String)
        : null,
    items: (json['items'] as List)
        .cast<Map<String, dynamic>>()
        .map(SaleItem.fromJson)
        .toList(),
  );
}

class AlertItem {
  AlertItem({
    required this.id,
    required this.name,
    required this.stockQuantity,
    required this.lowStockThreshold,
    required this.state,
  });

  final String id;
  final String name;
  final int stockQuantity;
  final int lowStockThreshold;
  final String state; // 'critical' or 'low'

  factory AlertItem.fromJson(Map<String, dynamic> json) => AlertItem(
    id: json['id'] as String,
    name: json['name'] as String,
    stockQuantity: json['stock_quantity'] as int,
    lowStockThreshold: json['low_stock_threshold'] as int,
    state: json['state'] as String,
  );
}

class InventoryAlerts {
  InventoryAlerts({
    required this.inStockCount,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.items,
  });

  final int inStockCount;
  final int lowStockCount;
  final int outOfStockCount;
  final List<AlertItem> items;

  factory InventoryAlerts.fromJson(Map<String, dynamic> json) =>
      InventoryAlerts(
        inStockCount: json['in_stock_count'] as int,
        lowStockCount: json['low_stock_count'] as int,
        outOfStockCount: json['out_of_stock_count'] as int,
        items: (json['items'] as List)
            .cast<Map<String, dynamic>>()
            .map(AlertItem.fromJson)
            .toList(),
      );
}

class StockAdjustment {
  StockAdjustment({
    required this.id,
    required this.delta,
    required this.reason,
    required this.createdAt,
  });

  final String id;
  final int delta;
  final String reason;
  final DateTime createdAt;

  factory StockAdjustment.fromJson(Map<String, dynamic> json) =>
      StockAdjustment(
        id: json['id'] as String,
        delta: json['delta'] as int,
        reason: json['reason'] as String? ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

enum SaleActionOutcome { success, insufficientStock, offline, rejected }

class SaleActionResult {
  const SaleActionResult({required this.outcome, this.sale, this.message});

  final SaleActionOutcome outcome;
  final Sale? sale;
  final String? message;
}

/// Deliberately online-only (Stage 8, D1): stock is finite, contended
/// state, so a sale can never be queued for later sync — two offline
/// sales of the last unit would both "succeed" locally with no way to
/// tell which one was real. No Drift table, no cache, same reasoning
/// ScheduleRepository uses for spots_left.
class PosRepository {
  PosRepository(this._api);

  final PosApi _api;

  Future<List<Product>> fetchProducts({
    bool? lowStock,
    bool? outOfStock,
  }) async {
    final raw = await _api.fetchProducts(
      lowStock: lowStock,
      outOfStock: outOfStock,
    );
    return raw.map(Product.fromJson).toList();
  }

  Future<Product> createProduct({
    required String name,
    required String category,
    required int priceCentavos,
    required int initialStock,
    required int lowStockThreshold,
  }) async {
    final json = await _api.createProduct({
      'name': name,
      'category': category,
      'price': centavosToDecimalString(priceCentavos),
      'stock_quantity': initialStock,
      'low_stock_threshold': lowStockThreshold,
    });
    return Product.fromJson(json);
  }

  /// On the Part A negative-stock rejection, throws an ApiException whose
  /// message names how much is on hand — the caller shows that directly
  /// rather than clamping the input, per the spec (Part C).
  Future<Product> adjustStock(
    String productId, {
    required int delta,
    String reason = '',
  }) async {
    final json = await _api.adjustStock(
      productId,
      delta: delta,
      reason: reason,
    );
    return Product.fromJson(json);
  }

  Future<List<StockAdjustment>> fetchAdjustments(String productId) async {
    final raw = await _api.fetchAdjustments(productId);
    return raw.map(StockAdjustment.fromJson).toList();
  }

  Future<Product> setActive(String productId, bool isActive) async {
    final json = await _api.updateProduct(productId, {'is_active': isActive});
    return Product.fromJson(json);
  }

  Future<Product> deactivateProduct(String productId) =>
      setActive(productId, false);

  /// No confirmation dialog needed on the caller's side for this one —
  /// unlike deactivating, restoring a product isn't destructive.
  Future<Product> reactivateProduct(String productId) =>
      setActive(productId, true);

  Future<List<Sale>> fetchSales({DateTime? date}) async {
    final raw = await _api.fetchSales(date: date != null ? _fmt(date) : null);
    return raw.map(Sale.fromJson).toList();
  }

  Future<Sale> fetchSale(String id) async {
    final json = await _api.fetchSale(id);
    return Sale.fromJson(json);
  }

  Future<SaleActionResult> createSale({
    required List<({String productId, int quantity})> items,
    String? memberId,
  }) async {
    try {
      final json = await _api.createSale(
        items: [
          for (final item in items)
            {'product_id': item.productId, 'quantity': item.quantity},
        ],
        memberId: memberId,
      );
      return SaleActionResult(
        outcome: SaleActionOutcome.success,
        sale: Sale.fromJson(json),
      );
    } on ApiException catch (e) {
      if (e.kind == ApiExceptionKind.network) {
        return const SaleActionResult(
          outcome: SaleActionOutcome.offline,
          message: 'You need a connection to record a sale.',
        );
      }
      if (e.kind == ApiExceptionKind.validation &&
          e.message.contains('Not enough stock')) {
        return SaleActionResult(
          outcome: SaleActionOutcome.insufficientStock,
          message: e.message,
        );
      }
      return SaleActionResult(
        outcome: SaleActionOutcome.rejected,
        message: e.message,
      );
    }
  }

  Future<void> voidSale(String id) => _api.voidSale(id);

  Future<InventoryAlerts> fetchInventoryAlerts() async {
    final json = await _api.fetchInventoryAlerts();
    return InventoryAlerts.fromJson(json);
  }

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
