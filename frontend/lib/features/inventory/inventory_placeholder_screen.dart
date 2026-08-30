import 'package:flutter/material.dart';

class InventoryPlaceholderScreen extends StatelessWidget {
  const InventoryPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Inventory\ncoming soon',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, color: Colors.grey),
        ),
      ),
    );
  }
}
