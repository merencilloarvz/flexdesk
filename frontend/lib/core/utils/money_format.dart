import 'package:intl/intl.dart';

/// Formats a centavos-denominated integer amount for display.
///
/// `parseCentavos` (in `money.dart`) handles ingest — turning server values
/// into the stored integer. This is the display-only counterpart: the
/// `/ 100` below never touches the stored value, which stays an integer
/// everywhere else in the app.
///
/// Not used by the members list yet (members don't show prices), but built
/// now so plans and POS screens have one place to call, reading the code
/// from `gym.currency` — nobody should hardcode a peso sign.
String formatMoney(int centavos, String currencyCode) =>
    NumberFormat.simpleCurrency(name: currencyCode).format(centavos / 100);
