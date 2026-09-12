import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/colors.dart';
import '../../../core/utils/money_format.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/pos_repository.dart';
import '../providers/pos_providers.dart';

enum _StockFilter { all, inStock, low, out }

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  List<Product>? _products;
  bool _loading = true;
  String? _error;
  _StockFilter _filter = _StockFilter.all;

  // Tracks whether anything changed (add, adjust, deactivate) so
  // PosScreen knows whether it needs to refresh when this screen closes.
  bool _dirty = false;

  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();
  bool _addSubmitting = false;
  String? _addError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    super.dispose();
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
        _products = products;
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

  Future<void> _submitAddProduct() async {
    final name = _nameController.text.trim();
    final price = double.tryParse(_priceController.text.trim());
    final stock = int.tryParse(_stockController.text.trim());

    if (name.isEmpty) {
      setState(() => _addError = 'Enter a product name.');
      return;
    }
    if (price == null || price < 0) {
      setState(() => _addError = 'Enter a valid price.');
      return;
    }
    if (stock == null || stock < 0) {
      setState(() => _addError = 'Enter a valid starting stock count.');
      return;
    }

    setState(() {
      _addSubmitting = true;
      _addError = null;
    });

    try {
      await ref
          .read(posRepositoryProvider)
          .createProduct(
            name: name,
            category: '',
            priceCentavos: (price * 100).round(),
            initialStock: stock,
            // No threshold input in this quick-entry form — the backend
            // model defaults low_stock_threshold to 5, which is a
            // reasonable starting point staff can raise later via a
            // full edit if that's ever built.
            lowStockThreshold: 5,
          );
      if (!mounted) return;
      _nameController.clear();
      _priceController.clear();
      _stockController.clear();
      _dirty = true;
      setState(() => _addSubmitting = false);
      await _load();
      _showSnack('Product added.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _addError = e.message;
        _addSubmitting = false;
      });
    }
  }

  /// Returns null on success, or an error message on failure — the row
  /// shows that message inline rather than this screen throwing.
  Future<String?> _adjust(Product product, int delta) async {
    try {
      await ref
          .read(posRepositoryProvider)
          .adjustStock(product.id, delta: delta, reason: 'Restock');
      _dirty = true;
      await _load();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<void> _confirmDeactivate(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deactivate this product?'),
        content: Text(
          '${product.name} will no longer show up in POS or the sale grid. '
          'Past sales that included it are kept exactly as recorded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Deactivate',
              style: TextStyle(color: AppColors.errorText),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(posRepositoryProvider).deactivateProduct(product.id);
      _dirty = true;
      await _load();
    } on ApiException catch (e) {
      _showSnack(e.message);
    }
  }

  /// No confirmation dialog — unlike deactivating, restoring a product
  /// isn't destructive, so it doesn't need the same friction.
  Future<void> _reactivate(Product product) async {
    try {
      await ref.read(posRepositoryProvider).reactivateProduct(product.id);
      _dirty = true;
      await _load();
    } on ApiException catch (e) {
      _showSnack(e.message);
    }
  }

  List<Product> _filtered(List<Product> products) {
    switch (_filter) {
      case _StockFilter.all:
        return products;
      case _StockFilter.inStock:
        return products.where((p) => !p.isOutOfStock && !p.isLowStock).toList();
      case _StockFilter.low:
        return products.where((p) => p.isLowStock).toList();
      case _StockFilter.out:
        return products.where((p) => p.isOutOfStock).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isOwner =
        authState is AuthAuthenticated && authState.user.role == UserRole.owner;
    final currencyCode = authState is AuthAuthenticated
        ? authState.user.gym?.currency ?? 'PHP'
        : 'PHP';

    // Deactivated products are no longer split into a separate
    // INACTIVE section — they're filtered by stock state exactly like
    // any other product (an inactive product sitting at 0 units shows
    // up under "Out", same as an active one). They're only visually
    // distinguished on the row itself (an "Inactive" tag + a restore
    // button instead of an archive icon).
    final allProducts = _products ?? const <Product>[];
    final filtered = _filtered(allProducts);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_dirty);
      },
      child: Scaffold(
        backgroundColor: AppColors.pageBg,
        appBar: AppBar(
          backgroundColor: AppColors.pageBg,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.ink),
            onPressed: () => Navigator.of(context).pop(_dirty),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Inventory',
                style: TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accentTealBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${allProducts.length} items',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accentTeal,
                  ),
                ),
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.accentTeal,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    children: [
                      if (isOwner) ...[
                        _AddProductCard(
                          nameController: _nameController,
                          priceController: _priceController,
                          stockController: _stockController,
                          submitting: _addSubmitting,
                          error: _addError,
                          onSubmit: _submitAddProduct,
                        ),
                        const SizedBox(height: 20),
                      ],
                      Row(
                        children: [
                          Text(
                            'INVENTORY ITEMS · ${allProducts.length} Products',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.fieldBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _FilterTab(
                                label: 'All',
                                selected: _filter == _StockFilter.all,
                                onTap: () =>
                                    setState(() => _filter = _StockFilter.all),
                              ),
                            ),
                            Expanded(
                              child: _FilterTab(
                                label: 'In Stock',
                                selected: _filter == _StockFilter.inStock,
                                onTap: () => setState(
                                  () => _filter = _StockFilter.inStock,
                                ),
                              ),
                            ),
                            Expanded(
                              child: _FilterTab(
                                label: 'Low',
                                selected: _filter == _StockFilter.low,
                                onTap: () =>
                                    setState(() => _filter = _StockFilter.low),
                              ),
                            ),
                            Expanded(
                              child: _FilterTab(
                                label: 'Out',
                                selected: _filter == _StockFilter.out,
                                onTap: () =>
                                    setState(() => _filter = _StockFilter.out),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (allProducts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'No products yet — add one above.',
                              style: TextStyle(color: AppColors.subtle),
                            ),
                          ),
                        )
                      else if (filtered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'No products match this filter.',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        )
                      else
                        for (final product in filtered)
                          _ProductRow(
                            key: ValueKey(product.id),
                            product: product,
                            currencyCode: currencyCode,
                            isOwner: isOwner,
                            // A delisted product's stock isn't worth
                            // restocking until it's reactivated first —
                            // the stepper is disabled for it.
                            onAdjust: product.isActive
                                ? (delta) => _adjust(product, delta)
                                : null,
                            onToggleActive: isOwner
                                ? () => product.isActive
                                      ? _confirmDeactivate(product)
                                      : _reactivate(product)
                                : null,
                          ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// Inline "quick entry" add-product card, owner-only. Replaces a separate
/// add-product screen — no navigation, no FAB (the FAB previously used
/// here rendered underneath the app's persistent bottom nav bar and
/// couldn't be tapped).
class _AddProductCard extends StatelessWidget {
  const _AddProductCard({
    required this.nameController,
    required this.priceController,
    required this.stockController,
    required this.submitting,
    required this.error,
    required this.onSubmit,
  });

  final TextEditingController nameController;
  final TextEditingController priceController;
  final TextEditingController stockController;
  final bool submitting;
  final String? error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Add Custom Product',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.fieldBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Quick Entry',
                  style: TextStyle(fontSize: 10, color: AppColors.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            'Configure item details & inventory',
            style: TextStyle(fontSize: 11, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          _MiniField(
            controller: nameController,
            label: 'PRODUCT NAME',
            hint: 'e.g. Whey Protein Isolate, Water Bottle',
            icon: Icons.shopping_bag_outlined,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MiniField(
                  controller: priceController,
                  label: 'PRICE',
                  hint: '150',
                  prefixText: '₱',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniField(
                  controller: stockController,
                  label: 'INITIAL STOCK (UNITS)',
                  hint: '25',
                  icon: Icons.inventory_2_outlined,
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.errorBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                error!,
                style: const TextStyle(
                  color: AppColors.errorText,
                  fontSize: 12,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: submitting ? null : onSubmit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentTeal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              icon: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Icon(Icons.add, size: 18),
              label: const Text('Add Product'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniField extends StatelessWidget {
  const _MiniField({
    required this.controller,
    required this.label,
    required this.hint,
    this.icon,
    this.prefixText,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  // Exactly one of these two is expected to be provided by the caller —
  // an icon (e.g. product name, stock count) or a literal prefix string
  // (the peso sign for price, since Flutter/Material has no built-in
  // currency icon for ₱).
  final IconData? icon;
  final String? prefixText;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 13, color: AppColors.ink),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.muted, fontSize: 12),
            prefixIcon: prefixText != null
                ? Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Align(
                      widthFactor: 1,
                      child: Text(
                        prefixText!,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  )
                : Icon(icon, size: 16, color: AppColors.muted),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
            filled: true,
            fillColor: AppColors.fieldBg,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterTab extends StatelessWidget {
  const _FilterTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.cardBg : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.accentTeal : AppColors.muted,
          ),
        ),
      ),
    );
  }
}

/// One product row: status/category/price/units on top, and — for active
/// products any staff can adjust — a typable "- N +" stepper plus a
/// confirm checkmark that only activates once the number actually
/// changes. The delta sent to the server is computed automatically
/// (newValue - currentStock), so nobody has to do that math by hand.
class _ProductRow extends StatefulWidget {
  const _ProductRow({
    super.key,
    required this.product,
    required this.currencyCode,
    required this.isOwner,
    required this.onAdjust,
    required this.onToggleActive,
  });

  final Product product;
  final String currencyCode;
  final bool isOwner;
  final Future<String?> Function(int delta)? onAdjust;
  // A single callback that deactivates an active product or reactivates
  // an inactive one — the row picks which action and which icon/label
  // to show based on product.isActive, so the caller doesn't need two
  // separate optional callbacks.
  final VoidCallback? onToggleActive;

  @override
  State<_ProductRow> createState() => _ProductRowState();
}

class _ProductRowState extends State<_ProductRow> {
  late final TextEditingController _qtyController;
  late int _pendingQty;
  bool _busy = false;
  String? _rowError;

  @override
  void initState() {
    super.initState();
    _pendingQty = widget.product.stockQuantity;
    _qtyController = TextEditingController(text: '$_pendingQty');
  }

  @override
  void didUpdateWidget(covariant _ProductRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A successful adjustment reloads the whole product list, so this
    // row gets a fresh Product with the new server-confirmed stock —
    // resync the pending value to match rather than leaving a stale
    // number sitting in the field.
    if (widget.product.stockQuantity != oldWidget.product.stockQuantity) {
      _pendingQty = widget.product.stockQuantity;
      _qtyController.text = '$_pendingQty';
    }
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  void _bump(int by) {
    var next = _pendingQty + by;
    if (next < 0) next = 0;
    setState(() {
      _pendingQty = next;
      _qtyController.text = '$_pendingQty';
      _qtyController.selection = TextSelection.collapsed(
        offset: _qtyController.text.length,
      );
    });
  }

  void _onTyped(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      // Still typing (e.g. just cleared the field) — don't flash an
      // error for a transient empty state.
      setState(() => _rowError = null);
      return;
    }
    final parsed = int.tryParse(trimmed);
    if (parsed == null || parsed < 0) {
      setState(() => _rowError = 'Enter a whole number, 0 or higher.');
      return;
    }
    setState(() {
      _pendingQty = parsed;
      _rowError = null;
    });
  }

  Future<void> _confirm() async {
    if (widget.onAdjust == null) return;
    // Don't let a stale "valid" pendingQty from before an invalid typed
    // entry sneak through — if there's an active validation error, the
    // person needs to fix it first, not have the last good value
    // silently submitted instead.
    if (_rowError != null) return;
    final delta = _pendingQty - widget.product.stockQuantity;
    if (delta == 0) return;

    setState(() {
      _busy = true;
      _rowError = null;
    });
    final error = await widget.onAdjust!(delta);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _rowError = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final canEdit = widget.onAdjust != null;
    final hasChange = _pendingQty != product.stockQuantity;

    final String statusLabel;
    final Color statusColor;
    if (product.isOutOfStock) {
      statusLabel = 'Out of Stock';
      statusColor = AppColors.errorText;
    } else if (product.isLowStock) {
      statusLabel = 'Low Stock';
      statusColor = AppColors.expiringBg;
    } else {
      statusLabel = 'In Stock';
      statusColor = AppColors.linkGreen;
    }

    return Opacity(
      opacity: product.isActive ? 1.0 : 0.55,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
                if (!product.isActive) ...[
                  const Text(
                    ' · ',
                    style: TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.disabledBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Inactive',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.disabledLabel,
                      ),
                    ),
                  ),
                ],
                if (product.category.isNotEmpty) ...[
                  const Text(
                    ' · ',
                    style: TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                  Text(
                    product.category,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                  ),
                ],
                const Spacer(),
                if (widget.isOwner && widget.onToggleActive != null)
                  InkWell(
                    onTap: widget.onToggleActive,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        product.isActive
                            ? Icons.archive_outlined
                            : Icons.unarchive_outlined,
                        size: 16,
                        color: AppColors.subtle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              product.name,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              formatMoney(product.priceCentavos, widget.currencyCode),
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 10),
            if (canEdit)
              Row(
                children: [
                  _StepButton(icon: Icons.remove, onTap: () => _bump(-1)),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 52,
                    child: TextField(
                      controller: _qtyController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      onChanged: _onTyped,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        filled: true,
                        fillColor: AppColors.fieldBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _StepButton(icon: Icons.add, onTap: () => _bump(1)),
                  const Spacer(),
                  _ConfirmButton(
                    enabled: hasChange && !_busy && _rowError == null,
                    busy: _busy,
                    onTap: _confirm,
                  ),
                ],
              )
            else
              Text(
                product.isOutOfStock
                    ? 'Out of stock'
                    : '${product.stockQuantity} units',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            if (_rowError != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                decoration: BoxDecoration(
                  color: AppColors.errorBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _rowError!,
                  style: const TextStyle(
                    color: AppColors.errorText,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: AppColors.fieldBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: AppColors.ink),
      ),
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? AppColors.accentTeal : AppColors.disabledBg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 30,
          height: 30,
          child: busy
              ? const Padding(
                  padding: EdgeInsets.all(7),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : Icon(
                  Icons.check,
                  size: 16,
                  color: enabled ? Colors.white : AppColors.disabledLabel,
                ),
        ),
      ),
    );
  }
}
