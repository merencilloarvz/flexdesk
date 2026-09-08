import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/colors.dart';
import '../../auth/providers/auth_providers.dart';
import '../../../core/utils/money_format.dart';
import '../../shell/app_shell.dart';
import '../data/pos_repository.dart';
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
  InventoryAlerts? _alerts;
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
      final repo = ref.read(posRepositoryProvider);
      final results = await Future.wait([
        repo.fetchProducts(),
        repo.fetchInventoryAlerts(),
      ]);
      if (!mounted) return;
      setState(() {
        // Deactivated products still come back from /products/ (the
        // backend deliberately doesn't filter them out server-side —
        // Inventory needs to be able to show them in its own INACTIVE
        // section). POS is the one place that must never sell one, so
        // the filter belongs here.
        _products = (results[0] as List<Product>)
            .where((p) => p.isActive)
            .toList();
        _alerts = results[1] as InventoryAlerts;
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

  Future<void> _openInventory() async {
    final changed = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const InventoryScreen()));
    if (changed == true) await _load();
  }

  Future<void> _openConfirm(String currencyCode) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: false,
      builder: (_) => _ConfirmSheet(
        currencyCode: currencyCode,
        onConfirmed: (result) async {
          if (result.outcome == SaleActionOutcome.success) {
            ref.read(cartProvider.notifier).clear();
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

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final currencyCode = authState is AuthAuthenticated
        ? authState.user.gym.currency
        : 'PHP';

    final cart = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);

    // Rough allowance for the cart card's height — it grows with line
    // count, so this is generous rather than exact; the grid just needs
    // enough clearance that the last row isn't hidden behind the card.
    final cartCardAllowance = cart.isEmpty
        ? 24.0
        : 170.0 + (cart.length * 24.0);

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
        actions: [
          if (_alerts != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _StockBadgeChip(alerts: _alerts!),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_alerts != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: _StockOverviewCard(
                  alerts: _alerts!,
                  onManageStock: _openInventory,
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!))
                  : (_products == null || _products!.isEmpty)
                  ? const Center(
                      child: Text(
                        'No products yet. Add some from Manage Stock.',
                        style: TextStyle(color: AppColors.subtle),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppColors.accentBlue,
                      child: GridView.builder(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          AppShell.reservedNavHeight + cartCardAllowance,
                        ),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 1.15,
                            ),
                        itemCount: _products!.length,
                        itemBuilder: (context, index) {
                          final product = _products![index];
                          return _ProductTile(
                            product: product,
                            cartQuantity: cartNotifier.quantityOf(product.id),
                            currencyCode: currencyCode,
                            onAdd: () => _addToCart(product),
                            onRemove: () => _removeFromCart(product.id),
                          );
                        },
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

class _StockBadgeChip extends StatelessWidget {
  const _StockBadgeChip({required this.alerts});

  final InventoryAlerts alerts;

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color color;
    if (alerts.lowStockCount > 0) {
      label = 'Stock (${alerts.lowStockCount} Low)';
      color = AppColors.expiringBg;
    } else if (alerts.outOfStockCount > 0) {
      label = 'Stock (${alerts.outOfStockCount} Out)';
      color = AppColors.errorText;
    } else {
      label = 'Stock (Full)';
      color = AppColors.linkGreen;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _StockOverviewCard extends StatelessWidget {
  const _StockOverviewCard({required this.alerts, required this.onManageStock});

  final InventoryAlerts alerts;
  final VoidCallback onManageStock;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.accentBlueBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              size: 18,
              color: AppColors.accentBlue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Stock Overview',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${alerts.inStockCount} in Stock · ${alerts.lowStockCount} Low · '
                  '${alerts.outOfStockCount} Out',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: onManageStock,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentBlue,
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

class _ProductTile extends StatelessWidget {
  const _ProductTile({
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
    final disabled = product.isOutOfStock;

    return Opacity(
      opacity: disabled ? 0.55 : 1.0,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                if (cartQuantity == 0)
                  _RoundIconButton(
                    icon: Icons.add,
                    onTap: disabled ? null : onAdd,
                  )
                else
                  _QtyStepperPill(
                    quantity: cartQuantity,
                    onAdd: disabled ? null : onAdd,
                    onRemove: onRemove,
                  ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatMoney(product.priceCentavos, currencyCode),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  disabled
                      ? 'Out of stock'
                      : product.isLowStock
                      ? 'Low · ${product.stockQuantity} left'
                      : '${product.stockQuantity} in stock',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: disabled
                        ? AppColors.errorText
                        : product.isLowStock
                        ? AppColors.expiringBg
                        : AppColors.muted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onTap == null ? AppColors.disabledBg : AppColors.accentBlue,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 26,
          height: 26,
          child: Icon(
            icon,
            size: 16,
            color: onTap == null ? AppColors.disabledLabel : Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Small "- N +" pill shown on a tile once that product has at least one
/// unit in the cart, so quantity can be adjusted without leaving the grid.
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
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: AppColors.fieldBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(999),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.remove, size: 14, color: AppColors.ink),
            ),
          ),
          SizedBox(
            width: 18,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
          InkWell(
            onTap: onAdd,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.add,
                size: 14,
                color: onAdd == null ? AppColors.disabledLabel : AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Persistent cart summary — pinned above the nav bar, always fully
/// expanded (no collapse/modal step). Item quantities are adjusted from
/// the product grid; this card is a read-only summary plus Clear Cart
/// and Pay Now.
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
        padding: const EdgeInsets.all(16),
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
                    color: AppColors.accentBlueBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${notifier.itemCount} items',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accentBlue,
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
                    style: TextStyle(fontSize: 12, color: AppColors.accentBlue),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final line in cart)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${line.quantity}x ${line.productName}',
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
            const Divider(height: 20),
            Row(
              children: [
                const Text(
                  'GRAND TOTAL',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const Spacer(),
                Text(
                  formatMoney(notifier.totalCentavos, currencyCode),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accentBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: cart.isEmpty ? null : onPayNow,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: const Text('Pay Now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirmation sheet before recording — item list, total, an optional
/// (client-only, never-sent) amount-tendered field, and Confirm. No
/// optimistic UI: the cart is only cleared by the caller after a 201.
class _ConfirmSheet extends ConsumerStatefulWidget {
  const _ConfirmSheet({required this.currencyCode, required this.onConfirmed});

  final String currencyCode;
  final void Function(SaleActionResult result) onConfirmed;

  @override
  ConsumerState<_ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends ConsumerState<_ConfirmSheet> {
  final _tenderedController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _tenderedController.dispose();
    super.dispose();
  }

  int? get _changeCentavos {
    final text = _tenderedController.text.trim();
    if (text.isEmpty) return null;
    final tendered = double.tryParse(text);
    if (tendered == null) return null;
    final total = ref.read(cartProvider.notifier).totalCentavos;
    final change = (tendered * 100).round() - total;
    return change;
  }

  Future<void> _confirm() async {
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
      // back online) without having to reopen Pay Now from scratch.
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
    final total = ref.read(cartProvider.notifier).totalCentavos;
    final change = _changeCentavos;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Confirm sale',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.3,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: cart.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final line = cart[index];
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${line.quantity} × ${line.productName}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    Text(
                      formatMoney(line.lineTotalCentavos, widget.currencyCode),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const Divider(height: 24),
          Row(
            children: [
              const Text(
                'Total',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const Spacer(),
              Text(
                formatMoney(total, widget.currencyCode),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accentBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _tenderedController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Amount tendered (optional)',
              filled: true,
              fillColor: AppColors.fieldBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (change != null) ...[
            const SizedBox(height: 8),
            Text(
              change >= 0
                  ? 'Change: ${formatMoney(change, widget.currencyCode)}'
                  : 'Short by ${formatMoney(-change, widget.currencyCode)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: change >= 0 ? AppColors.linkGreen : AppColors.errorText,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
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
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submitting ? null : _confirm,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
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
                  : const Text('Confirm'),
            ),
          ),
        ],
      ),
    );
  }
}
