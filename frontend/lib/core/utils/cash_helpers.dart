/// "1 item" / "2 items". [plural] defaults to `${singular}s`.
String pluralize(int count, String singular, {String? plural}) =>
    '$count ${count == 1 ? singular : (plural ?? '${singular}s')}';

/// Quick "cash received" amounts for a sale, in whole pesos.
///
/// "Exact" is offered separately by the UI. This returns up to three
/// more amounts that actually COVER [totalCentavos] (never a note smaller
/// than the sale): the common notes 50/100/200/500/1000, plus the next
/// round ₱500 and ₱1000 above the total so big sales still get useful
/// buttons. Sorted ascending, without duplicates, and never equal to the
/// exact total (that's what Exact is for).
///
///  - ₱150  -> 200, 500, 1000
///  - ₱450  -> 500, 1000
///  - ₱30   -> 50, 100, 200
///  - ₱1350 -> 1500, 2000
List<int> quickCashOptions(int totalCentavos) {
  if (totalCentavos <= 0) return const [];
  const notes = [50, 100, 200, 500, 1000];

  int roundUp(int pesosTotal, int step) =>
      ((pesosTotal + step - 1) ~/ step) * step;

  final totalPesosCeil = (totalCentavos + 99) ~/ 100;
  final candidates = <int>{
    ...notes,
    roundUp(totalPesosCeil, 500),
    roundUp(totalPesosCeil, 1000),
  };

  final covering = candidates.where((p) => p * 100 > totalCentavos).toList()
    ..sort();
  return covering.take(3).toList();
}
