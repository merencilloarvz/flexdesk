import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/colors.dart';
import '../../auth/providers/auth_providers.dart';
import '../../../core/utils/cash_helpers.dart';
import '../../../core/utils/money_format.dart';
import '../../dashboard/providers/analytics_providers.dart';
import '../../shell/app_shell.dart';
import '../data/pos_repository.dart';
import '../product_category.dart';
import '../providers/cart_provider.dart';
import '../providers/pos_providers.dart';
import 'inventory_screen.dart';

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  List<Product>? _products;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final products = await ref.read(posRepositoryProvider).fetchProducts();
      if (!mounted) return;
      setState(() {
        // Deactivated products still come back from /products/ (the
        // backend deliberately doesn't filter them out server-side —
        // Inventory needs to be able to show them in its own INACTIVE
        // section). POS is the one place that must never sell one, so
        // the filter belongs here.
        _products = products.where((p) => p.isActive).toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _addToCart(Product product) {
    if (product.isOutOfStock) return;
    final added = ref.read(cartProvider.notifier).addOne(product);
    if (!added) {
      _showSnack('Only ${product.stockQuantity} in stock.');
    }
  }

  void _removeFromCart(String productId) {
    ref.read(cartProvider.notifier).removeOne(productId);
  }

  Future<void> _openInventory({bool addProduct = false}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => InventoryScreen(startWithAddSheet: addProduct),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _openConfirm(String currencyCode) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: false,
      builder: (_) => ConfirmSaleSheet(
        currencyCode: currencyCode,
        onConfirmed: (result) async {
          if (result.outcome == SaleActionOutcome.success) {
            ref.read(cartProvider.notifier).clear();
            // The dashboard's sales figure derives entirely from this
            // FutureProvider, keyed by (gymId, range) — recording a
            // sale doesn't change either key, so nothing re-fetches it
            // on its own. Invalidate the whole family so every range a
            // user might have already viewed goes stale, not just the
            // current one.
            ref.invalidate(analyticsProvider);
            await _load();
            if (mounted) {
              _showSnack(
                'Sale recorded — ${formatMoney(result.sale!.totalAmountCentavos, currencyCode)}',
              );
            }
          } else if (result.outcome == SaleActionOutcome.insufficientStock) {
            // The sheet itself now stays open and shows this message
            // inline — no snackbar here, since it would render behind
            // the still-open sheet and likely never be seen. Still
            // refresh product tiles so they correct themselves.
            await _load();
          }
          // offline / rejected: sheet stays open with its own inline
          // error and the cart is untouched — nothing to do here.
        },
      ),
    );
  }

  /// Sellable products first; out-of-stock ones sit in their own section
  /// at the bottom. When nothing can be sold, a short message replaces
  /// the grid instead of a screen of greyed-out cards.
  Widget _productList({
    required String currencyCode,
    required CartNotifier cartNotifier,
    required double bottomPadding,
  }) {
    final products = _products!;
    final sellable = products.where((p) => !p.isOutOfStock).toList();
    final out = products.where((p) => p.isOutOfStock).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        // Three across on normal phones; two on very narrow screens so
        // names stay readable.
        final columns = constraints.maxWidth >= 330 ? 3 : 2;

        Widget rows(List<Product> items) => Column(
          children: [
            for (var i = 0; i < items.length; i += columns)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var c = 0; c < columns; c++) ...[
                        if (c > 0) const SizedBox(width: 8),
                        Expanded(
                          child: i + c < items.length
                              ? ProductTile(
                                  product: items[i + c],
                                  cartQuantity: cartNotifier.quantityOf(
                                    items[i + c].id,
                                  ),
                                  currencyCode: currencyCode,
                                  onAdd: () => _addToCart(items[i + c]),
                                  onRemove: () =>
                                      _removeFromCart(items[i + c].id),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
          children: [
            if (sellable.isEmpty)
              const _NothingToSell()
            else ...[
              rows(sellable),
              if (out.isNotEmpty) ...[
                const _SectionDivider(label: 'Out of stock'),
                rows(out),
              ],
            ],
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final currencyCode = authState is AuthAuthenticated
        ? authState.user.gym?.currency ?? 'PHP'
        : 'PHP';
    final isOwner =
        authState is AuthAuthenticated && authState.user.role == UserRole.owner;

    final cart = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);

    // Rough allowance for the cart card's height — it grows with line
    // count (capped, since the line list scrolls), so this is generous
    // rather than exact; the grid just needs enough clearance that the
    // last row isn't hidden behind the card.
    final cartCardAllowance = cart.isEmpty
        ? 24.0
        : 130.0 + (cart.length.clamp(0, 3) * 26.0);

    final hasProducts = _products != null && _products!.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        backgroundColor: AppColors.pageBg,
        elevation: 0,
        title: const Text(
          'POS & Store',
          style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700),
        ),
        iconTheme: const IconThemeData(color: AppColors.ink),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (hasProducts)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: _StockOverviewCard(
                  products: _products!,
                  onManageStock: _openInventory,
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!))
                  : !hasProducts
                  ? _EmptyProducts(
                      isOwner: isOwner,
                      onAdd: () => _openInventory(addProduct: true),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppColors.accentTeal,
                      child: _productList(
                        currencyCode: currencyCode,
                        cartNotifier: cartNotifier,
                        bottomPadding:
                            AppShell.reservedNavHeight + cartCardAllowance,
                      ),
                    ),
            ),
          ],
        ),
      ),
      bottomSheet: cart.isEmpty
          ? null
          : _CartSummaryCard(
              bottomInset: AppShell.reservedNavHeight,
              currencyCode: currencyCode,
              onPayNow: () => _openConfirm(currencyCode),
            ),
    );
  }
}

class _EmptyProducts extends StatelessWidget {
  const _EmptyProducts({required this.isOwner, required this.onAdd});

  final bool isOwner;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 96),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.accentTealBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.storefront_outlined,
                size: 30,
                color: AppColors.accentTeal,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No products yet',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isOwner
                  ? 'Add the drinks, supplements and gear you sell at the '
                        'counter, and they will show up here ready to ring up.'
                  : 'The gym owner hasn’t added any products yet. Once they '
                        'do, they will show up here ready to ring up.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.subtle),
            ),
            if (isOwner) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add your first product'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentTeal,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Stock status carried by colour: green when everything is in stock,
/// amber when anything is low or out. Hidden by the caller when there are
/// no products at all.
class _StockOverviewCard extends StatelessWidget {
  const _StockOverviewCard({
    required this.products,
    required this.onManageStock,
  });

  final List<Product> products;
  final VoidCallback onManageStock;

  @override
  Widget build(BuildContext context) {
    final low = products.where((p) => p.isLowStock).length;
    final out = products.where((p) => p.isOutOfStock).length;
    final allGood = low == 0 && out == 0;

    final title = allGood
        ? 'All in stock'
        : [
            if (low > 0) '$low low',
            if (out > 0) '$out out of stock',
          ].join(' · ');
    final bg = allGood ? AppColors.successBg : AppColors.expiringIcon;
    final fg = allGood ? AppColors.linkGreen : AppColors.expiringBg;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              allGood
                  ? Icons.check_circle_outline
                  : Icons.warning_amber_rounded,
              size: 20,
              color: fg,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  pluralize(products.length, 'product'),
                  style: TextStyle(
                    fontSize: 11,
                    color: fg.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: onManageStock,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentTeal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: const Text(
              'Manage Stock',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact product card that ends where its content ends: a thin category
/// strip (icon + colour, grey when out of stock), name, price, stock left
/// — and the quantity stepper only once the product is in the cart. The
/// whole card adds one unit when tapped; out-of-stock cards are dimmed and
/// inert.
class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.product,
    required this.cartQuantity,
    required this.currencyCode,
    required this.onAdd,
    required this.onRemove,
  });

  final Product product;
  final int cartQuantity;
  final String currencyCode;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final out = product.isOutOfStock;
    final inCart = cartQuantity > 0;

    final category = categoryFor(product.category);
    final stripColor = out
        ? AppColors.disabledLabel
        : (category?.color ?? uncategorizedColor);
    final stripIcon = category?.icon ?? uncategorizedIcon;
    // Fixed categories show their name; anything else shows its own text
    // so old free-text categories aren't hidden.
    final stripLabel = category?.name ?? product.category.trim();

    final stockText = out
        ? 'Out of stock'
        : product.isLowStock
        ? 'Low · ${product.stockQuantity} left'
        : '${product.stockQuantity} left';
    final stockColor = out
        ? AppColors.errorText
        : product.isLowStock
        ? AppColors.expiringBg
        : AppColors.muted;

    return Semantics(
      button: true,
      enabled: !out,
      label:
          '${product.name}, ${formatMoney(product.priceCentavos, currencyCode)}, '
          '$stockText',
      child: Opacity(
        opacity: out ? 0.6 : 1.0,
        child: Material(
          color: AppColors.cardBg,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: inCart
                ? const BorderSide(color: AppColors.accentTeal, width: 1.5)
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: out ? null : onAdd,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  color: stripColor.withValues(alpha: 0.16),
                  child: Row(
                    children: [
                      Icon(stripIcon, size: 14, color: stripColor),
                      if (stripLabel.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            stripLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: stripColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        formatMoney(product.priceCentavos, currencyCode),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        stockText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: stockColor,
                        ),
                      ),
                      if (inCart) ...[
                        const SizedBox(height: 6),
                        _QtyStepperPill(
                          quantity: cartQuantity,
                          onAdd: out ? null : onAdd,
                          onRemove: onRemove,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 10),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Divider(height: 1, color: AppColors.border)),
        ],
      ),
    );
  }
}

class _NothingToSell extends StatelessWidget {
  const _NothingToSell();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        children: [
          Icon(Icons.remove_shopping_cart_outlined, color: AppColors.muted),
          SizedBox(height: 10),
          Text(
            'Nothing can be sold right now — restock in Manage Stock',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.subtle),
          ),
        ],
      ),
    );
  }
}

/// "- N +" pill shown on a tile once that product has at least one unit
/// in the cart, so quantity can be adjusted without leaving the grid.
class _QtyStepperPill extends StatelessWidget {
  const _QtyStepperPill({
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  final int quantity;
  final VoidCallback? onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: AppColors.accentTealBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(999),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              child: Icon(Icons.remove, size: 16, color: AppColors.accentTeal),
            ),
          ),
          Text(
            '$quantity',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          InkWell(
            onTap: onAdd,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              child: Icon(
                Icons.add,
                size: 16,
                color: onAdd == null
                    ? AppColors.disabledLabel
                    : AppColors.accentTeal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Persistent cart summary — pinned above the nav bar. Item quantities are
/// adjusted from the product grid; this card is a read-only summary plus
/// Clear Cart and the Charge button, which carries the total so it is
/// confirmed before the tap, not after.
class _CartSummaryCard extends ConsumerWidget {
  const _CartSummaryCard({
    required this.bottomInset,
    required this.currencyCode,
    required this.onPayNow,
  });

  final double bottomInset;
  final String currencyCode;
  final VoidCallback onPayNow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset + 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  'CART SUMMARY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentTealBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    pluralize(notifier.itemCount, 'item'),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accentTeal,
                    ),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: cart.isEmpty ? null : notifier.clear,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Clear Cart',
                    style: TextStyle(fontSize: 12, color: AppColors.accentTeal),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Long carts scroll here instead of pushing the Charge button
            // off screen.
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 84),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  for (final line in cart)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${line.quantity}x ${line.productName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          Text(
                            formatMoney(line.lineTotalCentavos, currencyCode),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: cart.isEmpty ? null : onPayNow,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentTeal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: Text(
                  'Charge ${formatMoney(notifier.totalCentavos, currencyCode)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirmation sheet before recording — amount due, an optional
/// (client-only, never-sent) amount received via an in-sheet number pad,
/// change / still-owed, and Complete sale. No optimistic UI: the cart is
/// only cleared by the caller after a 201.
///
/// Amount received is optional: left blank, the sale can be completed and
/// no change is shown. Once an amount is entered it must cover the total.
class ConfirmSaleSheet extends ConsumerStatefulWidget {
  const ConfirmSaleSheet({
    super.key,
    required this.currencyCode,
    required this.onConfirmed,
  });

  final String currencyCode;
  final void Function(SaleActionResult result) onConfirmed;

  @override
  ConsumerState<ConfirmSaleSheet> createState() => _ConfirmSaleSheetState();
}

class _ConfirmSaleSheetState extends ConsumerState<ConfirmSaleSheet> {
  // Whole pesos typed on the pad; empty means "nothing entered".
  String _digits = '';
  // Set by "Exact": the precise total, which may include centavos that the
  // whole-peso pad can't type. Cleared as soon as a pad key is pressed.
  int? _exactCentavos;
  bool _submitting = false;
  String? _error;

  static const _maxDigits = 7;

  int get _total => ref.read(cartProvider.notifier).totalCentavos;

  /// Tendered in centavos, or null when nothing has been entered.
  int? get _tenderedCentavos =>
      _exactCentavos ??
      (_digits.isEmpty ? null : (int.tryParse(_digits) ?? 0) * 100);

  bool get _short {
    final t = _tenderedCentavos;
    return t != null && t < _total;
  }

  void _press(String key) {
    if (_submitting) return;
    setState(() {
      _exactCentavos = null;
      if (key == '⌫') {
        if (_digits.isNotEmpty) {
          _digits = _digits.substring(0, _digits.length - 1);
        }
        return;
      }
      var next = _digits + key;
      // No leading zeros ("00", "007").
      next = next.replaceFirst(RegExp(r'^0+'), '');
      if (next.length > _maxDigits) return;
      _digits = next;
    });
  }

  void _setTenderedCentavos(int centavos) {
    if (_submitting) return;
    setState(() {
      _exactCentavos = null;
      _digits = '${centavos ~/ 100}';
    });
  }

  Future<void> _confirm() async {
    if (_submitting || _short) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final cart = ref.read(cartProvider);
    final repo = ref.read(posRepositoryProvider);

    final result = await repo.createSale(
      items: [
        for (final line in cart)
          (productId: line.productId, quantity: line.quantity),
      ],
    );

    if (!mounted) return;

    if (result.outcome == SaleActionOutcome.success) {
      // Only a successful sale closes this sheet — on any failure the
      // person stays here with the error shown and can retry (e.g. once
      // back online) without having to reopen the sheet from scratch.
      Navigator.of(context).pop();
      widget.onConfirmed(result);
    } else {
      setState(() {
        _submitting = false;
        _error = result.message ?? 'Something went wrong. Please try again.';
      });
      // Parent still runs its own side effects (e.g. refreshing the
      // product list on insufficient stock) even though the sheet stays
      // open here.
      widget.onConfirmed(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final total = _total;
    final tendered = _tenderedCentavos;
    final quick = quickCashOptions(total);
    final media = MediaQuery.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.94),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Confirm sale',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      tooltip: 'Close',
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // Everything scrolls except the Complete sale button, so the
              // button can never be covered on a small screen.
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Amount due',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                      Text(
                        formatMoney(total, widget.currencyCode),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w800,
                          color: AppColors.accentTeal,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 64),
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: cart.length,
                          itemBuilder: (context, index) {
                            final line = cart[index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 1),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${line.quantity} × ${line.productName}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.subtle,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    formatMoney(
                                      line.lineTotalCentavos,
                                      widget.currencyCode,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.subtle,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Amount received (optional) — display only; typed
                      // on the pad below.
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.fieldBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Text(
                              'Cash received',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.muted,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  tendered == null
                                      ? 'Optional'
                                      : formatMoney(
                                          tendered,
                                          widget.currencyCode,
                                        ),
                                  style: TextStyle(
                                    fontSize: tendered == null ? 14 : 22,
                                    fontWeight: FontWeight.w700,
                                    color: tendered == null
                                        ? AppColors.disabledLabel
                                        : AppColors.ink,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _QuickChip(
                            label: 'Exact',
                            onTap: () {
                              if (_submitting) return;
                              setState(() {
                                _digits = '';
                                _exactCentavos = total;
                              });
                            },
                          ),
                          for (final pesos in quick)
                            _QuickChip(
                              label: formatMoney(
                                pesos * 100,
                                widget.currencyCode,
                              ).replaceAll('.00', ''),
                              onTap: () => _setTenderedCentavos(pesos * 100),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _ChangeBlock(
                        tendered: tendered,
                        total: total,
                        currencyCode: widget.currencyCode,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 12,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.errorBg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: AppColors.errorText,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      _NumberPad(onKey: _press),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: FilledButton(
                  onPressed: (_submitting || _short) ? null : _confirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentTeal,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.disabledBg,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Text(
                          'Complete sale',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.accentTeal,
        ),
      ),
      backgroundColor: AppColors.accentTealBg,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      onPressed: onTap,
    );
  }
}

/// Big tinted block: change when tendered covers the total, what's still
/// owed when it doesn't, and a neutral hint when nothing is entered.
class _ChangeBlock extends StatelessWidget {
  const _ChangeBlock({
    required this.tendered,
    required this.total,
    required this.currencyCode,
  });

  final int? tendered;
  final int total;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final String label;
    final String value;

    if (tendered == null) {
      bg = AppColors.fieldBg;
      fg = AppColors.muted;
      label = 'Change';
      value = '—';
    } else if (tendered! >= total) {
      bg = AppColors.successBg;
      fg = AppColors.linkGreen;
      label = 'Change';
      value = formatMoney(tendered! - total, currencyCode);
    } else {
      bg = AppColors.errorBg;
      fg = AppColors.errorText;
      label = 'Still owed';
      value = formatMoney(total - tendered!, currencyCode);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 1-9, 00, 0, backspace. Whole pesos only; long-press backspace clears.
class _NumberPad extends StatelessWidget {
  const _NumberPad({required this.onKey});

  final void Function(String key) onKey;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['00', '0', '⌫'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in _rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                for (final key in row)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Material(
                        color: AppColors.fieldBg,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => onKey(key),
                          onLongPress: key == '⌫'
                              ? () {
                                  for (var i = 0; i < 8; i++) {
                                    onKey('⌫');
                                  }
                                }
                              : null,
                          child: SizedBox(
                            height: 46,
                            child: Center(
                              child: key == '⌫'
                                  ? const Icon(
                                      Icons.backspace_outlined,
                                      size: 20,
                                      color: AppColors.ink,
                                    )
                                  : Text(
                                      key,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.ink,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
