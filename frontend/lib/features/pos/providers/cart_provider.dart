import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/pos_repository.dart';

class CartLine {
  const CartLine({
    required this.productId,
    required this.productName,
    required this.unitPriceCentavos,
    required this.quantity,
  });

  final String productId;
  final String productName;
  final int unitPriceCentavos;
  final int quantity;

  int get lineTotalCentavos => unitPriceCentavos * quantity;

  CartLine copyWith({int? quantity}) => CartLine(
    productId: productId,
    productName: productName,
    unitPriceCentavos: unitPriceCentavos,
    quantity: quantity ?? this.quantity,
  );
}

/// Client-side only, per Stage 8 Part B — no backend cart, no draft sale.
/// One POST creates the whole sale; this is just working memory until
/// then, cleared on success and preserved on any failure.
class CartNotifier extends StateNotifier<List<CartLine>> {
  CartNotifier() : super(const []);

  int get itemCount => state.fold(0, (sum, line) => sum + line.quantity);

  int get totalCentavos =>
      state.fold(0, (sum, line) => sum + line.lineTotalCentavos);

  int quantityOf(String productId) {
    final index = state.indexWhere((l) => l.productId == productId);
    return index == -1 ? 0 : state[index].quantity;
  }

  /// Returns false (and adds nothing) if this would exceed
  /// [product.stockQuantity] — the caller shows a brief message rather
  /// than silently no-op'ing.
  bool addOne(Product product) {
    final index = state.indexWhere((l) => l.productId == product.id);
    final current = index == -1 ? 0 : state[index].quantity;
    if (current >= product.stockQuantity) return false;

    if (index == -1) {
      state = [
        ...state,
        CartLine(
          productId: product.id,
          productName: product.name,
          unitPriceCentavos: product.priceCentavos,
          quantity: 1,
        ),
      ];
    } else {
      state = [
        for (final l in state)
          if (l.productId == product.id)
            l.copyWith(quantity: l.quantity + 1)
          else
            l,
      ];
    }
    return true;
  }

  void removeOne(String productId) {
    final index = state.indexWhere((l) => l.productId == productId);
    if (index == -1) return;
    final line = state[index];
    if (line.quantity <= 1) {
      state = [
        for (final l in state)
          if (l.productId != productId) l,
      ];
    } else {
      state = [
        for (final l in state)
          if (l.productId == productId)
            l.copyWith(quantity: l.quantity - 1)
          else
            l,
      ];
    }
  }

  void clear() => state = const [];
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartLine>>((ref) {
  return CartNotifier();
});
