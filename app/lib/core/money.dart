import 'package:intl/intl.dart';

final _euro = NumberFormat.currency(
  locale: 'es_ES',
  symbol: '€',
  decimalDigits: 2,
);

/// Formats integer cents as a Spanish euro amount, e.g. `3000` -> `30,00 €`.
String formatCents(int cents) => _euro.format(cents / 100);

/// Parses user input such as `16,95` or `16.95` into cents.
/// Returns `null` when the input is not a valid non-negative amount.
int? parseCents(String input) {
  final normalized = input
      .trim()
      .replaceAll('€', '')
      .replaceAll(',', '.')
      .trim();
  if (normalized.isEmpty) return null;
  final value = double.tryParse(normalized);
  if (value == null || value < 0) return null;
  return (value * 100).round();
}

/// Inverse of [parseCents], for pre-filling form fields.
String centsToInput(int cents) =>
    (cents / 100).toStringAsFixed(2).replaceAll('.', ',');
