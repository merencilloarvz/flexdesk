// Hand-rolled CSV writer used by Sales History's export feature — no
// `csv` package dependency, so this covers the escaping rules
// directly rather than trusting a library's test suite for them.
import 'package:flutter_test/flutter_test.dart';

import 'package:flexdesk/core/utils/csv_writer.dart';

void main() {
  group('csvField', () {
    test('plain text is returned unquoted', () {
      expect(csvField('Walk-in'), 'Walk-in');
    });

    test('null becomes an empty field', () {
      expect(csvField(null), '');
    });

    test('numbers and other objects are stringified', () {
      expect(csvField(42), '42');
      expect(csvField(12.5), '12.5');
    });

    test('a field containing a comma is quoted', () {
      expect(csvField('Shake, Choco'), '"Shake, Choco"');
    });

    test('a field containing a quote is quoted and the quote doubled', () {
      expect(csvField('12" pizza'), '"12"" pizza"');
    });

    test('a field containing a newline is quoted', () {
      expect(csvField('line one\nline two'), '"line one\nline two"');
    });
  });

  group('csvRow', () {
    test('joins fields with commas, quoting only where needed', () {
      expect(
        csvRow(['2024-10-24', 'Walk-in', 'Mark, A.', 75]),
        '2024-10-24,Walk-in,"Mark, A.",75',
      );
    });
  });

  group('buildCsv', () {
    test('header row plus data rows, each ending in CRLF', () {
      final csv = buildCsv(
        ['Date', 'Type', 'Amount'],
        [
          ['2024-10-24', 'Walk-in', '75.00'],
          ['2024-10-23', 'Membership', '1200.00'],
        ],
      );

      expect(
        csv,
        'Date,Type,Amount\r\n'
        '2024-10-24,Walk-in,75.00\r\n'
        '2024-10-23,Membership,1200.00\r\n',
      );
    });

    test('an empty row list still produces just the header', () {
      expect(buildCsv(['A', 'B'], []), 'A,B\r\n');
    });
  });
}
