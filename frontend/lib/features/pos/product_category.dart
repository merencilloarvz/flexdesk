import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';

/// One of the fixed product categories, with the icon and colour used on
/// the POS product strip. Products are matched by their existing
/// `category` text (case-insensitive), so old data keeps working.
class ProductCategory {
  const ProductCategory(this.name, this.icon, this.color);

  final String name;
  final IconData icon;
  final Color color;
}

const productCategories = <ProductCategory>[
  ProductCategory('Drinks', Icons.local_drink_outlined, AppColors.accentBlue),
  ProductCategory(
    'Supplements',
    Icons.medication_outlined,
    AppColors.categoryPurple,
  ),
  ProductCategory('Snacks', Icons.cookie_outlined, AppColors.categoryAmber),
  ProductCategory('Merch', Icons.checkroom_outlined, AppColors.categoryTeal),
  ProductCategory('Gear', Icons.fitness_center, AppColors.linkGreen),
];

/// Icon and colour for anything that isn't one of the fixed categories
/// (including no category at all): a neutral grey box.
const uncategorizedIcon = Icons.inventory_2_outlined;
const uncategorizedColor = AppColors.muted;

/// The fixed category for [raw], or null if it isn't one of them.
ProductCategory? categoryFor(String raw) {
  final key = raw.trim().toLowerCase();
  if (key.isEmpty) return null;
  for (final c in productCategories) {
    if (c.name.toLowerCase() == key) return c;
  }
  return null;
}
