import 'package:flutter/material.dart';

class PosPlaceholderScreen extends StatelessWidget {
  const PosPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'POS\ncoming soon',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, color: Colors.grey),
        ),
      ),
    );
  }
}
