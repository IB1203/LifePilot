import 'formatters.dart';
import 'models.dart';

const csvHeader = [
  'date',
  'type',
  'amount',
  'category',
  'description',
  'payment_method',
  'merchant',
  'note',
];

String _escape(String value) =>
    RegExp(r'[",\n\r]').hasMatch(value) || value.trim() != value
        ? '"${value.replaceAll('"', '""')}"'
        : value;

/// CSV with amounts as decimal rupees, so the file opens cleanly in a
/// spreadsheet. Dates are local ISO 8601.
String entriesToCsv(Iterable<LedgerEntry> entries) {
  final rows = <String>[csvHeader.join(',')];
  final sorted = entries.toList()
    ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  for (final entry in sorted) {
    rows.add([
      entry.occurredAt.toIso8601String(),
      entry.kind.name,
      paiseToInput(entry.amountPaise),
      entry.category,
      entry.title,
      entry.paymentMethod,
      entry.merchant,
      entry.note,
    ].map(_escape).join(','));
  }
  return '${rows.join('\r\n')}\r\n';
}

List<List<String>> parseCsv(String source) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var index = 0; index < source.length; index++) {
    final char = source[index];
    if (quoted) {
      if (char == '"') {
        if (index + 1 < source.length && source[index + 1] == '"') {
          field.write('"');
          index++;
        } else {
          quoted = false;
        }
      } else {
        field.write(char);
      }
    } else if (char == '"') {
      quoted = true;
    } else if (char == ',') {
      row.add(field.toString());
      field.clear();
    } else if (char == '\n' || char == '\r') {
      if (char == '\r' &&
          index + 1 < source.length &&
          source[index + 1] == '\n') {
        index++;
      }
      row.add(field.toString());
      field.clear();
      if (row.any((cell) => cell.trim().isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      field.write(char);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    if (row.any((cell) => cell.trim().isNotEmpty)) rows.add(row);
  }
  return rows;
}

class CsvImportResult {
  const CsvImportResult({required this.entries, required this.errors});

  /// Parsed entries with empty ids; the store assigns ids on import.
  final List<LedgerEntry> entries;

  /// Human-readable problems, one per rejected row.
  final List<String> errors;
}

/// Parses a CSV in the format produced by [entriesToCsv]. Column order is
/// taken from the header row; `date`, `type`, and `amount` are required.
CsvImportResult parseEntriesCsv(String source) {
  final rows = parseCsv(source.replaceFirst('﻿', ''));
  if (rows.isEmpty) {
    return const CsvImportResult(entries: [], errors: ['The file is empty.']);
  }
  final header = rows.first.map((cell) => cell.trim().toLowerCase()).toList();
  int column(String name) => header.indexOf(name);
  final dateColumn = column('date');
  final typeColumn = column('type');
  final amountColumn = column('amount');
  if (dateColumn < 0 || typeColumn < 0 || amountColumn < 0) {
    return const CsvImportResult(entries: [], errors: [
      'Missing a required column. Expected date, type, and amount.',
    ]);
  }
  String cell(List<String> row, String name) {
    final index = column(name);
    return index >= 0 && index < row.length ? row[index].trim() : '';
  }

  final entries = <LedgerEntry>[];
  final errors = <String>[];
  for (var index = 1; index < rows.length; index++) {
    final row = rows[index];
    final line = index + 1;
    final date = DateTime.tryParse(cell(row, 'date'));
    final type = cell(row, 'type').toLowerCase();
    final amount = parseRupeesToPaise(cell(row, 'amount'));
    if (date == null) {
      errors.add('Row $line: date is not valid.');
      continue;
    }
    if (type != 'expense' && type != 'income') {
      errors.add('Row $line: type must be expense or income.');
      continue;
    }
    if (amount == null) {
      errors.add('Row $line: amount must be a positive number.');
      continue;
    }
    final category = cell(row, 'category');
    final title = cell(row, 'description');
    final method = cell(row, 'payment_method');
    entries.add(LedgerEntry(
      id: '',
      kind: EntryKind.values.byName(type),
      amountPaise: amount,
      category: category.isEmpty ? 'Other' : category,
      title: title.isEmpty ? (type == 'income' ? 'Income' : 'Expense') : title,
      occurredAt: date,
      paymentMethod: paymentMethods.contains(method) ? method : 'Other',
      merchant: cell(row, 'merchant'),
      note: cell(row, 'note'),
    ));
  }
  return CsvImportResult(entries: entries, errors: errors);
}
