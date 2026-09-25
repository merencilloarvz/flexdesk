import 'package:flexdesk/core/utils/cash_helpers.dart';
import 'package:flexdesk/features/pos/data/pos_repository.dart';
import 'package:flexdesk/features/pos/providers/cart_provider.dart';
import 'package:flexdesk/features/pos/product_category.dart';
import 'package:flexdesk/features/pos/screens/inventory_screen.dart';
import 'package:flexdesk/features/pos/screens/pos_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Product _product({
  String name = 'Water',
  int price = 4500,
  int stock = 10,
  int threshold = 5,
}) => Product(
  id: 'p1',
  name: name,
  category: '',
  priceCentavos: price,
  stockQuantity: stock,
  lowStockThreshold: threshold,
  isActive: true,
);

void main() {
  group('quickCashOptions', () {
    test('never offers a note smaller than the total', () {
      expect(quickCashOptions(45000), [500, 1000]);
      expect(quickCashOptions(15000), [200, 500, 1000]);
      expect(quickCashOptions(3000), [50, 100, 200]);
    });

    test('big sales get round amounts above the total', () {
      expect(quickCashOptions(135000), [1500, 2000]);
    });

    test('an exact note total is left to the Exact button', () {
      expect(quickCashOptions(50000), isNot(contains(500)));
    });
  });

  test('pluralize', () {
    expect(pluralize(1, 'item'), '1 item');
    expect(pluralize(0, 'item'), '0 items');
    expect(pluralize(6, 'Product'), '6 Products');
  });

  test('category matching is case-insensitive; unknown stays neutral', () {
    expect(categoryFor('Drinks')?.name, 'Drinks');
    expect(categoryFor('merch')?.name, 'Merch');
    expect(categoryFor(' Gear ')?.name, 'Gear');
    expect(categoryFor('Whatever'), isNull);
    expect(categoryFor(''), isNull);
  });

  group('ProductTile', () {
    Widget host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 105, child: child)),
      ),
    );

    testWidgets('long name fits three-per-row width without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          ProductTile(
            product: _product(name: 'Whey Protein Isolate 2kg', price: 189900),
            cartQuantity: 2,
            currencyCode: 'PHP',
            onAdd: () {},
            onRemove: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Whey Protein Isolate 2kg'), findsOneWidget);
    });

    testWidgets('out of stock cannot be tapped', (tester) async {
      var adds = 0;
      await tester.pumpWidget(
        host(
          ProductTile(
            product: _product(stock: 0),
            cartQuantity: 0,
            currencyCode: 'PHP',
            onAdd: () => adds++,
            onRemove: () {},
          ),
        ),
      );
      await tester.tap(find.text('Water'));
      expect(adds, 0);
      expect(find.text('Out of stock'), findsOneWidget);
    });

    testWidgets('stepper only appears once in cart', (tester) async {
      Widget tile(int qty) => host(
        ProductTile(
          product: _product(),
          cartQuantity: qty,
          currencyCode: 'PHP',
          onAdd: () {},
          onRemove: () {},
        ),
      );
      await tester.pumpWidget(tile(0));
      expect(find.byIcon(Icons.remove), findsNothing);
      await tester.pumpWidget(tile(1));
      expect(find.byIcon(Icons.remove), findsOneWidget);
    });
  });

  group('ConfirmSaleSheet', () {
    Future<void> open(WidgetTester tester, {int priceCentavos = 45000}) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cartProvider.overrideWith((ref) {
              final n = CartNotifier();
              n.addOne(_product(price: priceCentavos));
              return n;
            }),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ConfirmSaleSheet(currencyCode: 'PHP', onConfirmed: (_) {}),
            ),
          ),
        ),
      );
    }

    FilledButton completeButton(WidgetTester tester) => tester.widget(
      find.ancestor(
        of: find.text('Complete sale'),
        matching: find.byType(FilledButton),
      ),
    );

    testWidgets('blank tendered is allowed; no change shown', (tester) async {
      await open(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Amount due'), findsOneWidget);
      expect(completeButton(tester).onPressed, isNotNull);
    });

    testWidgets('short amount shows still owed and blocks completion', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('1'));
      await tester.tap(find.text('00'));
      await tester.pump();
      expect(find.text('Still owed'), findsOneWidget);
      expect(completeButton(tester).onPressed, isNull);
    });

    testWidgets('quick amount shows change and allows completion', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('₱500'));
      await tester.pump();
      expect(find.text('Change'), findsOneWidget);
      expect(find.text('₱50.00'), findsOneWidget);
      expect(completeButton(tester).onPressed, isNotNull);
    });

    testWidgets('Exact with centavos gives zero change', (tester) async {
      await open(tester, priceCentavos: 15050);
      await tester.tap(find.text('Exact'));
      await tester.pump();
      expect(find.text('₱0.00'), findsOneWidget);
    });
  });

  test(
    'stock adjustment reason: increases are Restock, decreases need a pick',
    () {
      expect(stockAdjustReason(5, null), 'Restock');
      expect(stockAdjustReason(5, 'Damaged'), 'Restock');
      expect(stockAdjustReason(-2, null), isNull);
      expect(stockAdjustReason(-2, 'Damaged'), 'Damaged');
      expect(stockAdjustReason(-2, 'Correction'), 'Correction');
      expect(stockAdjustReason(-2, 'Restock'), isNull);
    },
  );
}
