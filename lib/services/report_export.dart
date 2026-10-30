import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/finance_calc.dart';
import '../core/formatters.dart';
import '../core/local_store.dart';
import '../core/models.dart';

/// Everything a monthly statement shows, computed from recorded data only.
class MonthlyReport {
  MonthlyReport._({
    required this.month,
    required this.summary,
    required this.categories,
    required this.budgets,
    required this.bills,
    required this.goals,
    required this.entries,
    required this.generatedAt,
  });

  factory MonthlyReport.from(LifePilotStore store, DateTime month) {
    final range = monthRange(month);
    final entries = store.entries
        .where((entry) => range.contains(entry.occurredAt))
        .toList()
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    final reference = range.end.subtract(const Duration(seconds: 1));
    final asOf = store.now().isBefore(reference) ? store.now() : reference;
    return MonthlyReport._(
      month: range.start,
      summary: summarize(store.entries, range),
      categories: categoryTotals(store.entries, range),
      budgets: [
        for (final budget in store.budgets)
          if (budget.period == BudgetPeriod.monthly)
            budgetStatus(budget, store.entries, asOf),
      ],
      bills: [
        for (final bill in store.bills)
          for (final payment in bill.payments)
            if (range.contains(payment.paidAt))
              (name: bill.name, payment: payment),
      ],
      goals: store.goals,
      entries: entries,
      generatedAt: store.now(),
    );
  }

  final DateTime month;
  final PeriodSummary summary;
  final Map<String, int> categories;
  final List<BudgetStatus> budgets;
  final List<({String name, BillPayment payment})> bills;
  final List<SavingsGoal> goals;
  final List<LedgerEntry> entries;
  final DateTime generatedAt;

  String get title => 'LifePilot statement · ${monthLabel(month)}';

  String get fileStem =>
      'lifepilot-${month.year}-${month.month.toString().padLeft(2, '0')}';
}

/// Amounts for files: the built-in PDF fonts have no rupee glyph, so a
/// non-ASCII symbol is written as "Rs.".
String _money(int paise) {
  final text = formatMoney(paise);
  return MoneyFormat.symbol == '₹' ? text.replaceFirst('₹', 'Rs. ') : text;
}

Future<Uint8List> buildReportPdf(MonthlyReport report) async {
  final doc = pw.Document(title: report.title, author: 'LifePilot AI');
  const accent = PdfColor.fromInt(0xFF167D72);
  pw.Widget heading(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
        child: pw.Text(text,
            style: pw.TextStyle(
                fontSize: 13, fontWeight: pw.FontWeight.bold, color: accent)),
      );
  pw.Widget table(List<String> headers, List<List<String>> rows,
          {Set<int> numeric = const {}}) =>
      rows.isEmpty
          ? pw.Text('Nothing recorded.',
              style: const pw.TextStyle(color: PdfColors.grey700))
          : pw.TableHelper.fromTextArray(
              headers: headers,
              data: rows,
              headerStyle:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
              cellAlignments: {
                for (final index in numeric) index: pw.Alignment.centerRight,
              },
            );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    footer: (context) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text(
          'Generated ${formatDateTime(report.generatedAt)} · page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
    ),
    build: (context) => [
      pw.Text(report.title,
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.Text(
          'Based only on entries recorded in LifePilot. Not a bank statement or net worth.',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      heading('Summary'),
      table([
        '',
        'Amount'
      ], [
        ['Income', _money(report.summary.income)],
        ['Expenses', _money(report.summary.expenses)],
        ['Net recorded cash flow', _money(report.summary.netCashFlow)],
      ], numeric: {
        1
      }),
      heading('Spending by category'),
      table([
        'Category',
        'Amount',
        'Share'
      ], [
        for (final MapEntry(key: name, value: amount)
            in report.categories.entries)
          [
            name,
            _money(amount),
            report.summary.expenses == 0
                ? ''
                : '${(amount * 100 / report.summary.expenses).round()}%',
          ],
      ], numeric: {
        1,
        2
      }),
      heading('Budgets'),
      table([
        'Category',
        'Limit',
        'Spent',
        'Remaining',
        'Used'
      ], [
        for (final status in report.budgets)
          [
            status.budget.category,
            _money(status.limitPaise),
            _money(status.spentPaise),
            _money(status.remainingPaise),
            '${status.utilizationPercent}%',
          ],
      ], numeric: {
        1,
        2,
        3,
        4
      }),
      heading('Bills paid'),
      table([
        'Bill',
        'Due',
        'Paid on',
        'Amount'
      ], [
        for (final item in report.bills)
          [
            item.name,
            formatDate(item.payment.dueAt),
            formatDate(item.payment.paidAt),
            _money(item.payment.amountPaise),
          ],
      ], numeric: {
        3
      }),
      heading('Savings goals'),
      table([
        'Goal',
        'Saved',
        'Target',
        'Progress'
      ], [
        for (final goal in report.goals)
          [
            goal.name,
            _money(goal.savedPaise),
            _money(goal.targetPaise),
            '${(goal.progress * 100).round()}%',
          ],
      ], numeric: {
        1,
        2,
        3
      }),
      heading('Transactions'),
      table([
        'Date',
        'Description',
        'Category',
        'Method',
        'Amount'
      ], [
        for (final entry in report.entries)
          [
            formatShortDate(entry.occurredAt),
            entry.title,
            entry.category,
            entry.paymentMethod,
            '${entry.isIncome ? '+' : '-'}${_money(entry.amountPaise)}',
          ],
      ], numeric: {
        4
      }),
    ],
  ));
  return doc.save();
}

/// Workbook with Summary, Categories, Budgets and Transactions sheets.
/// Amounts are numbers in rupees so they can be summed in a spreadsheet.
Uint8List buildReportXlsx(MonthlyReport report) {
  final book = xl.Excel.createExcel();
  final defaultSheet = book.getDefaultSheet() ?? 'Sheet1';
  book.rename(defaultSheet, 'Summary');
  xl.CellValue text(String value) => xl.TextCellValue(value);
  xl.CellValue rupees(int paise) => xl.DoubleCellValue(paise / 100);

  book.appendRow('Summary', [text(report.title)]);
  book.appendRow('Summary', [
    text('Based only on entries recorded in LifePilot. Not a bank statement.')
  ]);
  book.appendRow('Summary', []);
  book.appendRow('Summary', [text('Income'), rupees(report.summary.income)]);
  book.appendRow(
      'Summary', [text('Expenses'), rupees(report.summary.expenses)]);
  book.appendRow('Summary',
      [text('Net recorded cash flow'), rupees(report.summary.netCashFlow)]);

  book.appendRow('Categories', [text('Category'), text('Amount')]);
  for (final MapEntry(key: name, value: amount) in report.categories.entries) {
    book.appendRow('Categories', [text(name), rupees(amount)]);
  }

  book.appendRow('Budgets',
      [text('Category'), text('Limit'), text('Spent'), text('Remaining')]);
  for (final status in report.budgets) {
    book.appendRow('Budgets', [
      text(status.budget.category),
      rupees(status.limitPaise),
      rupees(status.spentPaise),
      rupees(status.remainingPaise),
    ]);
  }

  book.appendRow('Transactions', [
    text('Date'),
    text('Type'),
    text('Description'),
    text('Category'),
    text('Payment method'),
    text('Merchant'),
    text('Amount'),
  ]);
  for (final entry in report.entries) {
    book.appendRow('Transactions', [
      text(entry.occurredAt.toIso8601String().substring(0, 10)),
      text(entry.kind.name),
      text(entry.title),
      text(entry.category),
      text(entry.paymentMethod),
      text(entry.merchant),
      rupees(entry.isIncome ? entry.amountPaise : -entry.amountPaise),
    ]);
  }
  final bytes = book.encode();
  if (bytes == null) throw StateError('The spreadsheet could not be created.');
  return Uint8List.fromList(bytes);
}
