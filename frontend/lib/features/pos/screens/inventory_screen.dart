import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/colors.dart';
import '../../../core/utils/money_format.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/pos_repository.dart';
import '../product_category.dart';
import '../providers/pos_providers.dart';

enum _StockFilter { all, inStock, low, out }

/// Reasons offered when stock goes DOWN. An increase is always a restock.
const stockDecreaseReasons = ['Correction', 'Damaged'];

/// The reason string sent to the server for a stock change: "Restock" for
/// an increase; for a decrease, the reason the person picked (required).
String? stockAdjustReason(int delta, String? picked) {
  if (delta > 0) return 'Restock';
  return picked != null && stockDecreaseReasons.contains(picked)
      ? picked
      : null;
}

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key, this.startWithAddSheet = false});

  /// Opens the Add product sheet as soon as the screen appears (owners
  /// only) — used by the POS empty state's "Add your first product".
  final bool startWithAddSheet;

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

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.startWithAddSheet) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final auth = ref.read(authControllerProvider);
        if (auth is AuthAuthenticated && auth.user.role == UserRole.owner) {
          _openAddSheet();
        }
      });
    }
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

  Future<void> _openAddSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddProductSheet(onSubmit: _createProduct),
    );
  }

  /// Returns null on success, or an error message for the sheet to show.
  Future<String?> _createProduct(
    String name,
    int priceCentavos,
    int stock,
    String category,
  ) async {
    try {
      await ref
          .read(posRepositoryProvider)
          .createProduct(
            name: name,
            category: category,
            priceCentavos: priceCentavos,
            initialStock: stock,
            // No threshold input in this quick-entry form — the backend
            // model defaults low_stock_threshold to 5, which is a
            // reasonable starting point staff can raise later via a
            // full edit if that's ever built.
            lowStockThreshold: 5,
          );
      _dirty = true;
      await _load();
      if (mounted) _showSnack('Product added.');
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// Returns null on success, or an error message on failure — the row
  /// shows that message inline rather than this screen throwing.
  Future<String?> _adjust(Product product, int delta, String reason) async {
    try {
      await ref
          .read(posRepositoryProvider)
          .adjustStock(product.id, delta: delta, reason: reason);
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

  int _count(List<Product> products, _StockFilter f) {
    switch (f) {
      case _StockFilter.all:
        return products.length;
      case _StockFilter.inStock:
        return products.where((p) => !p.isOutOfStock && !p.isLowStock).length;
      case _StockFilter.low:
        return products.where((p) => p.isLowStock).length;
      case _StockFilter.out:
        return products.where((p) => p.isOutOfStock).length;
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
          title: const Text(
            'Inventory',
            style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700),
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
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'What you sell',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          if (isOwner)
                            FilledButton.icon(
                              onPressed: _openAddSheet,
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add product'),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.accentTeal,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 36),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
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
                                count: _count(allProducts, _StockFilter.all),
                                selected: _filter == _StockFilter.all,
                                onTap: () =>
                                    setState(() => _filter = _StockFilter.all),
                              ),
                            ),
                            Expanded(
                              child: _FilterTab(
                                label: 'In stock',
                                count: _count(
                                  allProducts,
                                  _StockFilter.inStock,
                                ),
                                selected: _filter == _StockFilter.inStock,
                                onTap: () => setState(
                                  () => _filter = _StockFilter.inStock,
                                ),
                              ),
                            ),
                            Expanded(
                              child: _FilterTab(
                                label: 'Low',
                                count: _count(allProducts, _StockFilter.low),
                                selected: _filter == _StockFilter.low,
                                onTap: () =>
                                    setState(() => _filter = _StockFilter.low),
                              ),
                            ),
                            Expanded(
                              child: _FilterTab(
                                label: 'Out',
                                count: _count(allProducts, _StockFilter.out),
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
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Column(
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: const BoxDecoration(
                                  color: AppColors.accentTealBg,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.inventory_2_outlined,
                                  size: 30,
                                  color: AppColors.accentTeal,
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'No products yet',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isOwner
                                    ? 'Tap Add product to start your store.'
                                    : 'The gym owner hasn’t added any '
                                          'products yet.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.subtle,
                                ),
                              ),
                            ],
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
                                ? (delta, reason) =>
                                      _adjust(product, delta, reason)
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

/// Bottom sheet for adding a product (owner-only). Owns its own fields and
/// validation; [onSubmit] returns null on success (the sheet then closes)
/// or an error message to show inline.
class _AddProductSheet extends StatefulWidget {
  const _AddProductSheet({required this.onSubmit});

  final Future<String?> Function(
    String name,
    int priceCentavos,
    int stock,
    String category,
  )
  onSubmit;

  @override
  State<_AddProductSheet> createState() => _AddProductSheetState();
}

class _AddProductSheetState extends State<_AddProductSheet> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();
  bool _submitting = false;
  String? _error;
  // One of the fixed categories, or null for none (saved as empty).
  String? _category;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final name = _nameController.text.trim();
    final price = double.tryParse(_priceController.text.trim());
    final stock = int.tryParse(_stockController.text.trim());

    if (name.isEmpty) {
      setState(() => _error = 'Enter a product name.');
      return;
    }
    if (price == null || price < 0) {
      setState(() => _error = 'Enter a valid price.');
      return;
    }
    if (stock == null || stock < 0) {
      setState(() => _error = 'Enter a valid starting stock count.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    final error = await widget.onSubmit(
      name,
      (price * 100).round(),
      stock,
      _category ?? '',
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _submitting = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Lifts the sheet above the keyboard.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Add product',
                        style: TextStyle(
                          fontSize: 17,
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
                const SizedBox(height: 8),
                _MiniField(
                  controller: _nameController,
                  label: 'PRODUCT NAME',
                  hint: 'e.g. Whey Protein Isolate, Water Bottle',
                  icon: Icons.shopping_bag_outlined,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _MiniField(
                        controller: _priceController,
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
                        controller: _stockController,
                        label: 'INITIAL STOCK (UNITS)',
                        hint: '25',
                        icon: Icons.inventory_2_outlined,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'CATEGORY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 0,
                  children: [
                    for (final c in productCategories)
                      ChoiceChip(
                        avatar: Icon(
                          c.icon,
                          size: 16,
                          color: _category == c.name ? Colors.white : c.color,
                        ),
                        label: Text(c.name),
                        selected: _category == c.name,
                        showCheckmark: false,
                        selectedColor: c.color,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          color: _category == c.name
                              ? Colors.white
                              : AppColors.ink,
                        ),
                        onSelected: _submitting
                            ? null
                            : (on) => setState(
                                () => _category = on ? c.name : null,
                              ),
                      ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.errorBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _error!,
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
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentTeal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    icon: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Icon(Icons.add, size: 18),
                    label: const Text('Add product'),
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
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.accentTeal : AppColors.muted;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
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
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected ? AppColors.accentTealBg : AppColors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: fg,
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

/// One compact product row: stock dot, name, price, and — for active
/// products any staff can adjust — a typable "- N +" stepper on the right.
///
/// Changing the number does NOT save it. Once it differs from the stock on
/// record, a "Not saved yet · 5 → 8" strip with a Save button appears; only
/// tapping Save sends the change. The delta sent to the server is computed
/// automatically (newValue - currentStock), so nobody does that math.
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
  final Future<String?> Function(int delta, String reason)? onAdjust;
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
  // Only meaningful while the pending number is below the stock on record.
  String? _reason;
  // True while the typed text isn't a valid whole number; a failed save
  // (server error) is NOT this, so it can be retried with Save.
  bool _invalidInput = false;

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
      _reason = null;
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
    if (_busy) return;
    var next = _pendingQty + by;
    if (next < 0) next = 0;
    setState(() {
      _pendingQty = next;
      _invalidInput = false;
      _rowError = null;
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
      setState(() {
        _rowError = null;
        _invalidInput = false;
      });
      return;
    }
    final parsed = int.tryParse(trimmed);
    if (parsed == null || parsed < 0) {
      setState(() {
        _rowError = 'Enter a whole number, 0 or higher.';
        _invalidInput = true;
      });
      return;
    }
    setState(() {
      _pendingQty = parsed;
      _rowError = null;
      _invalidInput = false;
    });
  }

  Future<void> _confirm() async {
    if (widget.onAdjust == null || _busy) return;
    // Don't let a stale "valid" pendingQty from before an invalid typed
    // entry sneak through — if there's an active validation error, the
    // person needs to fix it first, not have the last good value
    // silently submitted instead.
    if (_invalidInput) return;
    final delta = _pendingQty - widget.product.stockQuantity;
    if (delta == 0) return;
    // A decrease must say why; the Save button is disabled until then.
    final reason = stockAdjustReason(delta, _reason);
    if (reason == null) return;

    setState(() {
      _busy = true;
      _rowError = null;
    });
    final error = await widget.onAdjust!(delta, reason);
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
    final isDecrease = _pendingQty < product.stockQuantity;
    final needsReason = isDecrease && _reason == null;

    final Color dotColor;
    final String statusWord;
    if (product.isOutOfStock) {
      dotColor = AppColors.errorText;
      statusWord = 'Out of stock';
    } else if (product.isLowStock) {
      dotColor = AppColors.expiringBg;
      statusWord = 'Low stock';
    } else {
      dotColor = AppColors.accentGreen;
      statusWord = 'In stock';
    }

    final subtitle = [
      formatMoney(product.priceCentavos, widget.currencyCode),
      if (product.category.isNotEmpty) product.category,
      if (!product.isActive) 'Inactive',
    ].join(' · ');

    return Opacity(
      opacity: product.isActive ? 1.0 : 0.55,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Semantics(
                  label: statusWord,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (canEdit)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StepButton(icon: Icons.remove, onTap: () => _bump(-1)),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 44,
                        child: TextField(
                          controller: _qtyController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          onChanged: _onTyped,
                          enabled: !_busy,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 8,
                            ),
                            filled: true,
                            fillColor: hasChange
                                ? AppColors.expiringIcon
                                : AppColors.fieldBg,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      _StepButton(icon: Icons.add, onTap: () => _bump(1)),
                    ],
                  )
                else
                  Text(
                    product.isOutOfStock
                        ? 'Out of stock'
                        : '${product.stockQuantity} units',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                if (widget.isOwner && widget.onToggleActive != null)
                  IconButton(
                    onPressed: widget.onToggleActive,
                    visualDensity: VisualDensity.compact,
                    tooltip: product.isActive ? 'Deactivate' : 'Reactivate',
                    icon: Icon(
                      product.isActive
                          ? Icons.archive_outlined
                          : Icons.unarchive_outlined,
                      size: 18,
                      color: AppColors.subtle,
                    ),
                  )
                else
                  const SizedBox(width: 4),
              ],
            ),
            if (canEdit && hasChange && !_invalidInput) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
                decoration: BoxDecoration(
                  color: AppColors.expiringIcon,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Not saved yet · ${product.stockQuantity} → '
                        '$_pendingQty',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.expiringBg,
                        ),
                      ),
                    ),
                    FilledButton(
                      onPressed: (_busy || needsReason) ? null : _confirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accentTeal,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text(
                              'Save',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              if (isDecrease) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Text(
                      'Why? ',
                      style: TextStyle(fontSize: 12, color: AppColors.subtle),
                    ),
                    for (final r in stockDecreaseReasons) ...[
                      ChoiceChip(
                        label: Text(r, style: const TextStyle(fontSize: 12)),
                        selected: _reason == r,
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        selectedColor: AppColors.accentTealBg,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() => _reason = r),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ],
            ],
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
