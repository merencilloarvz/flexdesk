import 'package:flexdesk/features/dashboard/screens/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 25, 12);

  test('lastSyncedLabel', () {
    expect(lastSyncedLabel(null, now), 'Not synced yet');
    expect(lastSyncedLabel(now, now), 'Last synced just now');
    expect(
      lastSyncedLabel(now.subtract(const Duration(minutes: 5)), now),
      'Last synced 5 min ago',
    );
    expect(
      lastSyncedLabel(now.subtract(const Duration(hours: 3)), now),
      'Last synced 3 h ago',
    );
    expect(
      lastSyncedLabel(now.subtract(const Duration(days: 2)), now),
      'Last synced 2 d ago',
    );
  });
}
