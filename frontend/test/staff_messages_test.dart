import 'package:flexdesk/features/settings/screens/staff_create_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('email-taken covers accounts at other gyms', () {
    final msg = staffEmailErrorMessage(
      'An account with this email already exists.',
    );
    expect(msg, contains('another gym'));
  });

  test('password validator messages are translated', () {
    expect(
      staffPasswordErrorMessage('This password is too common.'),
      contains('too common'),
    );
    expect(
      staffPasswordErrorMessage('This password is entirely numeric.'),
      contains('only numbers'),
    );
    expect(
      staffPasswordErrorMessage('Something unexpected'),
      'Something unexpected',
    );
  });
}
