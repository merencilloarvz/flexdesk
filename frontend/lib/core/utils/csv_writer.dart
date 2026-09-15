/// Minimal CSV writer — no `csv` package dependency, since every export
/// in this app is a small, well-known set of columns (dates, labels,
/// plain numbers) with no need for a full RFC 4180 parser/writer.
///
/// A field is quoted only when it actually contains a comma, a quote,
/// or a newline; embedded quotes are doubled per the CSV convention.
/// Rows are joined with CRLF, matching what spreadsheet apps expect.
library;

String csvField(Object? value) {
  final text = value?.toString() ?? '';
  if (text.contains(',') || text.contains('"') || text.contains('\n')) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

String csvRow(List<Object?> fields) => fields.map(csvField).join(',');

String buildCsv(List<String> header, List<List<Object?>> rows) {
  final buffer = StringBuffer(csvRow(header));
  buffer.write('\r\n');
  for (final row in rows) {
    buffer.write(csvRow(row));
    buffer.write('\r\n');
  }
  return buffer.toString();
}
