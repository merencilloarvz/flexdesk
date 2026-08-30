import 'package:flutter/material.dart';

class CheckInPlaceholderScreen extends StatelessWidget {
  const CheckInPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Check-In\ncoming soon',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, color: Colors.grey),
        ),
      ),
    );
  }
}
