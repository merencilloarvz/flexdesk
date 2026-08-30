/// Converts a DRF DecimalField wire string (e.g. `"1500.00"`) into whole
/// centavos as an int. Parses the string directly — never through `double`,
/// which would reintroduce the imprecision the integer column exists to
/// avoid.
///
/// max_digits=12, decimal_places=2 on the backend means a ceiling of
/// 9,999,999,999.99, i.e. 999,999,999,999 centavos — comfortably inside
/// Dart's 64-bit int on Android.
int parseCentavos(String v) {
  final parts = v.split('.');
  final whole = int.parse(parts[0]);
  final frac = parts.length > 1
      ? parts[1].padRight(2, '0').substring(0, 2)
      : '00';
  final magnitude = whole.abs() * 100 + int.parse(frac);
  return whole < 0 || v.startsWith('-') ? -magnitude : magnitude;
}

/// Inverse of [parseCentavos] — produces the decimal string the backend
/// expects on the wire when sending a price back up (`150000` -> `"1500.00"`).
/// Pure integer math, no `double`, for the same reason [parseCentavos]
/// avoids it — this column exists specifically to sidestep float rounding.
String centavosToDecimalString(int cents) {
  final sign = cents < 0 ? '-' : '';
  final magnitude = cents.abs();
  final whole = magnitude ~/ 100;
  final frac = (magnitude % 100).toString().padLeft(2, '0');
  return '$sign$whole.$frac';
}

// Sanity checks worth running once, e.g. in a unit test:
//   parseCentavos("1500.00") == 150000
//   parseCentavos("0.05")    == 5
//   parseCentavos("-10.50")  == -1050
//   centavosToDecimalString(150000) == "1500.00"
//   centavosToDecimalString(-1050)  == "-10.50"
