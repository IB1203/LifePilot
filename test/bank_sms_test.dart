import 'package:flutter_test/flutter_test.dart';
import 'package:lifepilot_ai/core/bank_sms.dart';
import 'package:lifepilot_ai/core/models.dart';

final _received = DateTime(2026, 10, 30, 9, 15);

// Message formats below follow the banks' published patterns with made-up
// numbers. Real messages vary; add any that parse wrongly here.

void main() {
  void expectParsed(
    String body, {
    required EntryKind kind,
    required int paise,
    String counterparty = '',
    String? reference,
    String? account,
    SmsChannel? channel,
    DateTime? date,
    bool refund = false,
  }) {
    final parsed = parseBankSms(body, received: _received);
    expect(parsed, isNotNull, reason: body);
    expect(parsed!.kind, kind, reason: body);
    expect(parsed.amountPaise, paise, reason: body);
    expect(parsed.counterparty, counterparty, reason: body);
    if (reference != null) expect(parsed.reference, reference, reason: body);
    if (account != null) expect(parsed.accountHint, account, reason: body);
    if (channel != null) expect(parsed.channel, channel, reason: body);
    if (date != null) expect(parsed.date, date, reason: body);
    expect(parsed.isRefund, refund, reason: body);
  }

  final oct29 = DateTime(2026, 10, 29);

  group('bank formats', () {
    test('HDFC Bank UPI debit, card spend and UPI credit', () {
      expectParsed(
          'Sent Rs.250.00\nFrom HDFC Bank A/C *1234\nTo SWIGGY\nOn 29/10/26\nRef 430912345678\nNot You?\nCall 18002586161/SMS BLOCK UPI to 7308080808',
          kind: EntryKind.expense,
          paise: 25000,
          counterparty: 'SWIGGY',
          reference: '430912345678',
          account: '1234',
          date: oct29);
      expectParsed(
          'Rs.1250.00 spent on HDFC Bank Card x5678 at AMAZON PAY INDIA on 2026-10-29:14:30:01.Not You? To Block+Reissue Call 18002586161/SMS BLOCK CC 5678 to 7308080808',
          kind: EntryKind.expense,
          paise: 125000,
          counterparty: 'AMAZON PAY INDIA',
          account: '5678',
          channel: SmsChannel.card,
          date: oct29);
      expectParsed(
          'Money Received - INR 5,000.00 in your HDFC Bank A/c xx1234 on 29-10-26 by A/c linked to VPA ravi.k@okaxis (UPI Ref No 430912345679).',
          kind: EntryKind.income,
          paise: 500000,
          counterparty: 'ravi.k@okaxis',
          reference: '430912345679',
          channel: SmsChannel.upi,
          date: oct29);
    });

    test('SBI UPI debit without a rupee sign', () {
      expectParsed(
          'Dear UPI user A/C X1234 debited by 250.0 on date 29Oct26 trf to SWIGGY Refno 430912345678. If not u? call 1800111109. -SBI',
          kind: EntryKind.expense,
          paise: 25000,
          counterparty: 'SWIGGY',
          reference: '430912345678',
          channel: SmsChannel.upi,
          date: oct29);
    });

    test('ICICI Bank debit names the payee before "credited"', () {
      expectParsed(
          'ICICI Bank Acct XX123 debited for Rs 250.00 on 29-Oct-26; SWIGGY credited. UPI:430912345678. Call 18002662 for dispute. SMS BLOCK 123 to 9215676766.',
          kind: EntryKind.expense,
          paise: 25000,
          counterparty: 'SWIGGY',
          reference: '430912345678',
          account: '123',
          date: oct29);
    });

    test('Axis Bank multi-line UPI debit', () {
      expectParsed(
          'INR 250.00 debited\nA/c no. XX1234\n29-10-26, 14:22:11\nUPI/P2M/430912345678/SWIGGY\nNot you? SMS BLOCKUPI Cust ID to 919951860002\nAxis Bank',
          kind: EntryKind.expense,
          paise: 25000,
          counterparty: 'SWIGGY',
          reference: '430912345678',
          channel: SmsChannel.upi,
          date: oct29);
    });

    test('Kotak, IDFC FIRST and Bank of Baroda', () {
      expectParsed(
          'Sent Rs.250.00 from Kotak Bank AC X1234 to swiggy@icici on 29-10-26.UPI Ref 430912345678. Not you, https://kotak.com/KBANKT/Fraud',
          kind: EntryKind.expense,
          paise: 25000,
          counterparty: 'swiggy@icici',
          reference: '430912345678',
          account: '1234');
      expectParsed(
          'Your A/C XXXXXX1234 has been debited with INR 250.00 on 29/10/2026 14:22 towards UPI/430912345678/SWIGGY. New bal: INR 9,750.00. Not you? Call 18001024111',
          kind: EntryKind.expense,
          paise: 25000,
          counterparty: 'SWIGGY',
          reference: '430912345678',
          date: oct29);
      expectParsed(
          'Rs.250.00 Dr. from A/C XXXXXX1234 and Cr. to swiggy@icici. Ref:430912345678. AvlBal:Rs9750.00(2026:10:29 14:22:11)',
          kind: EntryKind.expense,
          paise: 25000,
          counterparty: 'swiggy@icici',
          reference: '430912345678',
          date: oct29);
    });

    test('public-sector banks without a payee', () {
      expectParsed(
          'An amount of INR 1,200.00 has been DEBITED to your account XXX1234 on 29/10/2026. Total Avail.bal INR 8,800.00. - Canara Bank',
          kind: EntryKind.expense,
          paise: 120000,
          date: oct29);
      expectParsed(
          'A/c *1234 Debited for Rs:600.00 on 29-10-2026 12:10:42 by Mob Bk ref no 430912345678 Avl Bal Rs:5400.00.If not you, Call 1800222243 -Union Bank of India',
          kind: EntryKind.expense,
          paise: 60000,
          // "Mob Bk" is the channel (mobile banking), not a payee.
          reference: '430912345678');
    });

    test('salary, refunds and reversals', () {
      expectParsed(
          'Your A/c XX1234 is credited with INR 50,000.00 on 30-10-2026 by NEFT from ACME TECHNOLOGIES PVT LTD. Avl Bal INR 1,23,456.00',
          kind: EntryKind.income,
          paise: 5000000,
          counterparty: 'ACME TECHNOLOGIES PVT LTD',
          date: DateTime(2026, 10, 30));
      expectParsed(
          'Refund of Rs 499.00 from AMAZON has been credited to your card XX5678 on 28-10-26.',
          kind: EntryKind.income,
          paise: 49900,
          counterparty: 'AMAZON',
          refund: true,
          date: DateTime(2026, 10, 28));
      expectParsed(
          'Rs 250.00 reversed to your A/c XX1234 on 29-10-26 against UPI txn 430912345678',
          kind: EntryKind.income,
          paise: 25000,
          reference: '430912345678',
          refund: true);
    });

    test('ATM withdrawal and wallet payment', () {
      expectParsed(
          'Rs.2000.00 withdrawn at ATM S1AW000123 from A/c XX1234 on 29-10-26. Avl bal Rs 8,000.00',
          kind: EntryKind.expense,
          paise: 200000,
          counterparty: 'ATM S1AW000123',
          channel: SmsChannel.atm);
      expectParsed(
          'Paid Rs.250 to Swiggy from Paytm Balance. Updated Balance: Rs 100. Txn ID 12345678901',
          kind: EntryKind.expense,
          paise: 25000,
          counterparty: 'Swiggy',
          reference: '12345678901');
    });

    test('a balance or limit is never taken as the amount', () {
      expectParsed(
          'Avl Lmt INR 50,000 on card XX5678. INR 1,499.00 spent at AMAZON PAY on 29-Oct-26.',
          kind: EntryKind.expense,
          paise: 149900,
          counterparty: 'AMAZON PAY');
    });

    test('implausible dates are ignored', () {
      final parsed = parseBankSms(
          'Rs 100 debited from A/c XX1234 on 01-01-20 to SHOP.',
          received: _received);
      expect(parsed!.date, isNull);
    });
  });

  group('available balance', () {
    void expectBalance(String body, int? paise, {bool limit = false}) {
      final balance = smsBalance(body);
      if (paise == null) {
        expect(balance, isNull, reason: body);
        return;
      }
      expect(balance, isNotNull, reason: body);
      expect(balance!.paise, paise, reason: body);
      expect(balance.isLimit, limit, reason: body);
    }

    test('reads the balance in common bank formats', () {
      expectBalance('Debited INR 250. New bal: INR 9,750.00. Not you?', 975000);
      expectBalance('Ref:430912345678. AvlBal:Rs9750.00(2026:10:29 14:22:11)',
          975000);
      expectBalance('Total Avail.bal INR 8,800.00. - Canara Bank', 880000);
      expectBalance('Avl Bal Rs:5400.00.If not you, Call 1800222243', 540000);
      expectBalance('Avbl bal Rs 1,02,000', 10200000);
      expectBalance('Paid Rs.250 from Paytm Balance. Updated Balance: Rs 100',
          10000);
      expectBalance(
          'Your A/c XX1234 balance is Rs 5,000.00 as on 06-11-26', 500000);
    });

    test('card limits, owed balances and look-alikes', () {
      expectBalance('INR 1,499 spent. Avl Lmt INR 50,000', 5000000,
          limit: true);
      // An account balance wins over a credit limit in the same message.
      expectBalance('Avl Lmt INR 50,000. Avl Bal INR 2,000.00', 200000);
      expectBalance('Avl bal:INR 1,000.00 Dr', -100000);
      expectBalance('Minimum balance Rs 10,000 not maintained', null);
      expectBalance('Your loan outstanding balance Rs 2,00,000', null);
      expectBalance('Rs 500 debited. Not you? Call 1800', null);
    });

    test('a parsed transaction carries its balance', () {
      final parsed = parseBankSms(
          'Rs.2000.00 withdrawn at ATM S1AW000123 from A/c XX1234 on 29-10-26. Avl bal Rs 8,000.00',
          received: _received);
      expect(parsed!.balance!.paise, 800000);
      expect(parsed.amountPaise, 200000);
    });
  });

  group('credited or debited', () {
    test('a balance marked CR does not turn a debit into a credit', () {
      expectParsed(
          'Avl Bal Rs 9,000 CR. Rs 500 debited from A/c XX1234 at SHOP',
          kind: EntryKind.expense,
          paise: 50000,
          counterparty: 'SHOP',
          account: '1234');
    });

    test('"credited to" a payee is money going out', () {
      expectParsed(
          'Rs 500.00 credited to abc@ybl from your A/c XX1234. UPI Ref 430912345680',
          kind: EntryKind.expense,
          paise: 50000,
          counterparty: 'abc@ybl');
      expectParsed('Rs 500.00 credited to your A/c XX1234 from abc@ybl',
          kind: EntryKind.income, paise: 50000, counterparty: 'abc@ybl');
      expect(
          smsDirection(
              'Your a/c no. XXXXXX4321 is credited with Rs 50,000.00 on 01-11-26 from ACME CORP.'),
          EntryKind.income,
          reason: '"no. XXXXXX4321 is" is the account, not a payee');
      expectParsed(
          'Dear Customer. Rs 500 credited to your a/c XX1234 by NEFT from ACME',
          kind: EntryKind.income,
          paise: 50000,
          counterparty: 'ACME');
    });

    test('noun forms: "has credit", "debit of"', () {
      expect(
          smsDirection(
              'Your A/C XXXXX1234 has credit for BY TRANSFER of Rs 500.00 on 29Oct26'),
          EntryKind.income);
      expect(
          smsDirection('There is a debit of Rs 500.00 in your A/c XX1234'),
          EntryKind.expense);
      expect(smsDirection('Your credit card statement is ready'), isNull);
    });

    test('executed autopay is kept, mandate set-up is ignored', () {
      final debit = parseBankSms(
          'Rs 649.00 debited from A/c XX1234 towards NETFLIX e-mandate. UMRN ABC123',
          received: _received);
      expect(debit!.kind, EntryKind.expense);
      expect(debit.amountPaise, 64900);
      expect(debit.isAutoPay, isTrue);
      expect(
          parseBankSms(
              'Your e-mandate for Rs 649.00 towards NETFLIX has been registered successfully.',
              received: _received),
          isNull);
      expect(
          parseBankSms(
              'Rs 649.00 will be debited on 05-11-26 via e-mandate for NETFLIX.',
              received: _received),
          isNull);
    });

    test('credit card bill payments are flagged, card purchases are not', () {
      final payment = parseBankSms(
          'Payment of Rs 5,000.00 received on your HDFC Bank Credit Card XX5678 on 29-10-26.',
          received: _received);
      expect(payment!.isCardBillPayment, isTrue);
      final purchase = parseBankSms(
          'Rs 1,200 paid to BESCOM bill payment via credit card XX5678',
          received: _received);
      expect(purchase!.kind, EntryKind.expense);
      expect(purchase.isCardBillPayment, isFalse);
    });
  });

  group('senders and scams', () {
    test('recognises bank sender IDs', () {
      final hdfc = classifySender('VM-HDFCBK-S');
      expect(hdfc.kind, SenderKind.bank);
      expect(hdfc.bank, 'HDFC Bank');
      expect(classifySender('JD-SBIUPI').bank, 'SBI');
      expect(classifySender('AX-MYCOOP').kind, SenderKind.unknownHeader);
      expect(classifySender('AX-MYCOOP', extraSenders: ['mycoop']).kind,
          SenderKind.bank);
      expect(classifySender('+919876543210').kind, SenderKind.phoneNumber);
      expect(classifySender('pasted').kind, SenderKind.pasted);
    });

    test('flags fake bank messages and lures, not real bank messages', () {
      final phone = classifySender('+919876543210');
      expect(
          scamReason(
              phone, 'Rs 5,000 credited to your a/c. Click to claim now.'),
          contains('phone number'));
      expect(
          scamReason(phone,
              'Dear consumer your electricity power will be disconnected tonight at 9.30pm. Contact 9876500000'),
          isNotNull);
      expect(
          scamReason(classifySender('AD-ALERTS'),
              'Your SBI YONO account will be blocked today. Update your PAN: http://sbi-kyc.xyz/u'),
          isNotNull);
      expect(
          scamReason(classifySender('VM-KOTAKB'),
              'Sent Rs.250.00 ... Not you, https://kotak.com/KBANKT/Fraud'),
          isNull);
      expect(scamReason(phone, 'Running 10 min late, see you soon'), isNull);
    });

    test('redaction removes balances and links', () {
      final text = redactSms(
          'Rs 250 debited. Avl Bal INR 9,750.00. Not you? https://bank.example/x');
      expect(text, isNot(contains('9,750')));
      expect(text, isNot(contains('https')));
      expect(text, contains('Rs 250 debited'));
    });
  });
}
