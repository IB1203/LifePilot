import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifepilot_ai/core/local_store.dart';
import 'package:lifepilot_ai/core/models.dart';
import 'package:lifepilot_ai/core/receipt_text.dart';
import 'package:lifepilot_ai/core/statement_import.dart';
import 'package:lifepilot_ai/features/statement_import_flow.dart';
import 'package:lifepilot_ai/services/statement_files.dart';
import 'package:lifepilot_ai/ui/theme.dart';

final _now = DateTime(2026, 11, 10, 12);

// Layouts follow the banks' published statement formats with made-up
// numbers. Real files vary; add any that read wrongly here.
const _hdfc = '''
HDFC BANK Ltd.,,,,,,
Account No : 50100012341234,,,,,,
Statement From : 01/10/2026 To : 31/10/2026,,,,,,
,,,,,,
Date,Narration,Chq./Ref.No.,Value Dt,Withdrawal Amt.,Deposit Amt.,Closing Balance
01/10/26,UPI-SWIGGY-SWIGGY8@YBL-YESB0YBLUPI-430912345678-PAYMENT,0000430912345678,01/10/26,250.00,,"49,750.00"
05/10/26,NEFT-HDFCN52026100512345-ACME TECHNOLOGIES PVT LTD,HDFCN52026100512345,05/10/26,,"50,000.00","99,750.00"
06/10/26,POS 4567XXXXXXXX1234 AMAZON PAY INDIA,000000000000,06/10/26,"1,499.00",,"98,251.00"
08/10/26,UPI-REFUND-AMAZON-amazon@apl-430912345680-REFUND,0000430912345680,08/10/26,,499.00,"98,750.00"
********,,,,,,
STATEMENT SUMMARY :-,,,,,,
''';

void main() {
  group('reading cells', () {
    test('dates in the formats banks use', () {
      final oct31 = DateTime(2026, 10, 31);
      for (final text in [
        '31/10/2026',
        '31-10-26',
        '31.10.2026',
        '31 Oct 2026',
        '31-Oct-26',
        '2026-10-31',
        '2026-10-31 00:00:00',
        '46326',
      ]) {
        expect(parseStatementDate(text), oct31, reason: text);
      }
      expect(parseStatementDate('31/02/2026'), isNull);
      expect(parseStatementDate('Opening balance'), isNull);
    });

    test('amounts with symbols, commas, signs and Dr/Cr', () {
      expect(parseStatementAmount('1,234.50'), 123450);
      expect(parseStatementAmount('₹ 1,23,456.00'), 12345600);
      expect(parseStatementAmount('250.00 Dr'), -25000);
      expect(parseStatementAmount('250.00 Cr'), 25000);
      expect(parseStatementAmount('(250)'), -25000);
      expect(parseStatementAmount('-250'), -25000);
      expect(parseStatementAmount(''), isNull);
      expect(parseStatementAmount('0.00'), isNull);
      expect(parseStatementAmount('Total'), isNull);
    });
  });

  group('statement layouts', () {
    test('HDFC: header below bank details, separate debit and credit', () {
      final parsed = parseStatementTable(
          readStatementTable('statement.csv', utf8.encode(_hdfc)));
      expect(parsed.error, isNull);
      expect(parsed.rows, hasLength(4));
      expect(parsed.skipped, 2, reason: 'the ****** and summary lines');
      final swiggy = parsed.rows.first;
      expect(swiggy.date, DateTime(2026, 10, 1));
      expect(swiggy.kind, EntryKind.expense);
      expect(swiggy.amountPaise, 25000);
      expect(swiggy.balancePaise, 4975000);
      expect(parsed.rows[1].kind, EntryKind.income);
      expect(parsed.rows[1].amountPaise, 5000000);
    });

    test('Kotak style: one amount column with Dr / Cr', () {
      final parsed = parseStatementTable([
        [
          'Sl. No.',
          'Date',
          'Description',
          'Chq / Ref No.',
          'Amount',
          'Dr / Cr',
          'Balance'
        ],
        [
          '1',
          '02-11-2026',
          'UPI/RAVI KUMAR/430912345681/Lunch',
          '',
          '300.00',
          'DR',
          '9,700.00'
        ],
        [
          '2',
          '03-11-2026',
          'IMPS-430912345682-ANITA S-SBIN0001234',
          '',
          '1,000.00',
          'CR',
          '10,700.00'
        ],
      ]);
      expect([for (final row in parsed.rows) row.kind],
          [EntryKind.expense, EntryKind.income]);
      expect(parsed.rows.last.amountPaise, 100000);
    });

    test('SBI style: Txn Date wins over Value Date; signed amounts', () {
      final parsed = parseStatementTable([
        [
          'Value Date',
          'Txn Date',
          'Description',
          'Ref No./Cheque No.',
          'Debit',
          'Credit',
          'Balance'
        ],
        [
          '2 Nov 2026',
          '1 Nov 2026',
          'TO TRANSFER-UPI/DR/430912345683/ZOMATO/YESB/zomato@ybl/Pay',
          '',
          '450.00',
          '',
          '5,550.00'
        ],
      ]);
      expect(parsed.rows.single.date, DateTime(2026, 11, 1));
      final signed = parseStatementTable([
        ['Date', 'Particulars', 'Amount'],
        ['01/11/2026', 'ATM WDL 1234 MG ROAD', '-2000'],
        ['02/11/2026', 'INTEREST CREDIT', '120.50'],
      ]);
      expect(signed.rows.first.kind, EntryKind.expense);
      expect(signed.rows.last.kind, EntryKind.income);
    });

    test('a file without the needed columns explains what to do', () {
      final parsed = parseStatementTable([
        ['Name', 'Phone'],
        ['Ravi', '98765'],
      ]);
      expect(parsed.rows, isEmpty);
      expect(parsed.error, contains('CSV or Excel'));
    });
  });

  group('files', () {
    test('tab-separated text and Excel workbooks', () {
      final tsv = readStatementTable(
          'statement.txt',
          utf8.encode(
              'Date\tNarration\tDebit\tCredit\n01/11/2026\tTEA\t20\t\n'));
      expect(parseStatementTable(tsv).rows.single.amountPaise, 2000);

      final book = xl.Excel.createExcel();
      final sheet = book[book.getDefaultSheet()!];
      sheet.appendRow([
        xl.TextCellValue('Date'),
        xl.TextCellValue('Narration'),
        xl.TextCellValue('Withdrawal'),
        xl.TextCellValue('Deposit'),
      ]);
      sheet.appendRow([
        const xl.DateCellValue(year: 2026, month: 11, day: 1),
        xl.TextCellValue('UPI-CHAI POINT-chai@ybl-430912345684'),
        const xl.DoubleCellValue(85.5),
        xl.TextCellValue(''),
      ]);
      final rows = parseStatementTable(readStatementTable(
              'statement.xlsx', Uint8List.fromList(book.encode()!)))
          .rows;
      expect(rows.single.date, DateTime(2026, 11, 1));
      expect(rows.single.amountPaise, 8550);
    });

    test('PDF and old .xls files are refused with advice', () {
      expect(() => readStatementTable('s.pdf', Uint8List(0)),
          throwsA(isA<FormatException>()));
      expect(() => readStatementTable('s.xls', Uint8List(0)),
          throwsA(isA<FormatException>()));
    });
  });

  test('payee names from narrations', () {
    expect(
        narrationParty(
            'UPI-SWIGGY-SWIGGY8@YBL-YESB0YBLUPI-430912345678-PAYMENT'),
        'SWIGGY');
    expect(
        narrationParty(
            'TO TRANSFER-UPI/DR/430912345683/ZOMATO/YESB/zomato@ybl/Pay'),
        'ZOMATO');
    expect(narrationParty('NEFT-HDFCN52026100512345-ACME TECHNOLOGIES PVT LTD'),
        'ACME TECHNOLOGIES PVT LTD');
    expect(narrationParty('IMPS-430912345682-ANITA S-SBIN0001234'), 'ANITA S');
    expect(narrationParty('POS 4567XXXXXXXX1234 AMAZON PAY INDIA'),
        'AMAZON PAY INDIA');
    expect(narrationParty('ATM WDL 1234 MG ROAD'), 'ATM cash withdrawal');
    expect(narrationParty('ACH D- NETFLIX'), 'NETFLIX');
    expect(narrationParty('UPI/430912345678/430912345679/ravi@okaxis'),
        'ravi@okaxis');
  });

  group('importing', () {
    test('new rows become drafts; recorded ones and re-imports are skipped',
        () async {
      final store = LifePilotStore.inMemory(clock: () => _now);
      await store.addCategoryRule('swiggy', 'Food');
      // Already recorded from an SMS, a day later than the statement date.
      await store.addEntry(
          kind: EntryKind.income,
          amountPaise: 5000000,
          category: 'Salary',
          title: 'Salary',
          occurredAt: DateTime(2026, 10, 6, 9));
      final rows = parseStatementTable(
              readStatementTable('statement.csv', utf8.encode(_hdfc)))
          .rows;
      final import = buildStatementImport(store, rows);
      expect(import.duplicates, 1);
      expect(import.drafts, hasLength(3));
      expect(import.drafts.first.entry.title, 'SWIGGY');
      expect(import.drafts.first.entry.category, 'Food');
      expect(import.drafts.first.entry.paymentMethod, 'UPI');
      final refund = import.drafts.firstWhere((draft) => draft.entry.isIncome);
      expect(refund.entry.category, 'Refunds');
      expect(import.debitedPaise, 25000 + 149900);
      expect(import.closing!.paise, 9875000);
      expect(import.closing!.at, DateTime(2026, 10, 8));

      await store.applyStatementImport(import, balanceLabel: 'HDFC savings');
      expect(store.pending, hasLength(3));
      expect(store.pending.first.source, 'statement');
      expect(store.bankBalances.single.bank, 'HDFC savings');

      final again = buildStatementImport(store, rows);
      expect(again.drafts, isEmpty);
      // The row that was already recorded is remembered too.
      expect(again.alreadyImported, 4);
    });

    test('two equal payments on one day are not merged into one', () {
      final store = LifePilotStore.inMemory(clock: () => _now);
      final rows = [
        for (final narration in ['UPI-TEA STALL-1', 'UPI-TEA STALL-2'])
          StatementRow(
              date: DateTime(2026, 11, 1),
              narration: narration,
              kind: EntryKind.expense,
              amountPaise: 2000),
      ];
      expect(buildStatementImport(store, rows).drafts, hasLength(2));
    });

    test('closing balance of a newest-first statement is the first row', () {
      final store = LifePilotStore.inMemory(clock: () => _now);
      final import = buildStatementImport(store, [
        StatementRow(
            date: DateTime(2026, 11, 2),
            narration: 'B',
            kind: EntryKind.expense,
            amountPaise: 100,
            balancePaise: 900),
        StatementRow(
            date: DateTime(2026, 11, 1),
            narration: 'A',
            kind: EntryKind.expense,
            amountPaise: 100,
            balancePaise: 1000),
      ]);
      expect(import.closing!.paise, 900);
    });

    testWidgets('the review dialog creates drafts for the chosen account',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final store = LifePilotStore.inMemory(clock: () => _now);
      final account = await store.addAccount('HDFC savings', AccountKind.bank);
      final parsed = parseStatementTable(
          readStatementTable('statement.csv', utf8.encode(_hdfc)));
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => reviewStatement(context, store, parsed),
              child: const Text('Open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('4 transactions'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HDFC savings').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create 4 drafts'));
      await tester.pumpAndSettle();
      expect(store.pending, hasLength(4));
      expect(
          store.pending.every((draft) => draft.entry.accountId == account.id),
          isTrue);
    });
  });

  group('receipts', () {
    test('total, date, merchant and GST from a typical bill', () {
      const text = '''
TAX INVOICE
CAFE COFFEE DAY
MG Road, Bengaluru 560001
GSTIN: 29ABCDE1234F1Z5
Date: 08/11/2026  Time: 14:32
Cappuccino 1 x 180.00     180.00
Sandwich   1 x 220.00     220.00
Sub Total                 400.00
CGST 2.5%                  10.00
SGST 2.5%                  10.00
Grand Total            ₹ 420.00
Thank you! Visit again
''';
      final fields = parseReceiptText(text, now: _now);
      expect(fields.totalPaise, 42000);
      expect(fields.date, DateTime(2026, 11, 8));
      expect(fields.merchant, 'CAFE COFFEE DAY');
      expect(fields.gstPaise, 2000);
    });

    test('amount on the line after "Total", and no total label at all', () {
      final split = parseReceiptText('SHOP\nTOTAL\nRs. 1,250.00\n', now: _now);
      expect(split.totalPaise, 125000);
      final unlabeled = parseReceiptText(
          'KIRANA STORE\nRice 120.00\nOil 185.50\n',
          now: _now);
      expect(unlabeled.totalPaise, 18550);
      expect(unlabeled.merchant, 'KIRANA STORE');
    });

    test('future and very old dates are ignored', () {
      expect(parseReceiptText('Date 12/12/2026', now: _now).date, isNull);
      expect(parseReceiptText('Date 01/01/2020', now: _now).date, isNull);
      expect(parseReceiptText('nothing useful', now: _now).isEmpty, isTrue);
    });
  });
}
