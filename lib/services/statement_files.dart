import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;

import '../core/csv.dart';

/// Reads a bank statement file into rows of cells: Excel (.xlsx) workbooks,
/// or CSV / tab-separated text. Excel dates become ISO text (2026-10-31).
List<List<String>> readStatementTable(String fileName, Uint8List bytes) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.xlsx') || lower.endsWith('.xlsm')) {
    return _excelRows(bytes);
  }
  if (lower.endsWith('.xls')) {
    throw const FormatException(
        'Old .xls files cannot be read. Open it and save as .xlsx or CSV, or export CSV from net banking.');
  }
  if (lower.endsWith('.pdf')) {
    throw const FormatException(
        'PDF statements cannot be read yet. Download the statement as CSV or Excel from net banking.');
  }
  String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    text = latin1.decode(bytes);
  }
  if (text.startsWith('﻿')) text = text.substring(1);
  final sample = text.length > 4000 ? text.substring(0, 4000) : text;
  if ('\t'.allMatches(sample).length > ','.allMatches(sample).length) {
    return [
      for (final line in const LineSplitter().convert(text)) line.split('\t'),
    ];
  }
  return parseCsv(text);
}

String _two(int value) => value.toString().padLeft(2, '0');

String _cellText(xl.CellValue? value) => switch (value) {
      null => '',
      xl.DateCellValue() => () {
          final date = value.asDateTimeLocal();
          return '${date.year}-${_two(date.month)}-${_two(date.day)}';
        }(),
      xl.DateTimeCellValue() => () {
          final date = value.asDateTimeLocal();
          return '${date.year}-${_two(date.month)}-${_two(date.day)}';
        }(),
      xl.IntCellValue(value: final number) => '$number',
      xl.DoubleCellValue(value: final number) => '$number',
      _ => value.toString(),
    };

List<List<String>> _excelRows(Uint8List bytes) {
  final book = xl.Excel.decodeBytes(bytes);
  // The sheet with the most rows is the statement; others are cover pages.
  xl.Sheet? best;
  int bestRowsWithData = -1;
  int bestMaxRows = 0;
  for (final sheet in book.tables.values) {
    int rowsWithData = 0;
    for (final row in sheet.rows) {
      if (row.any((cell) =>
          cell != null &&
          cell.value != null &&
          cell.value.toString().trim().isNotEmpty)) {
        rowsWithData++;
      }
    }
    if (rowsWithData > bestRowsWithData ||
        (rowsWithData == bestRowsWithData && sheet.maxRows > bestMaxRows)) {
      best = sheet;
      bestRowsWithData = rowsWithData;
      bestMaxRows = sheet.maxRows;
    }
  }
  if (best == null) return const [];
  return [
    for (final row in best.rows)
      [for (final cell in row) _cellText(cell?.value)],
  ];
}
