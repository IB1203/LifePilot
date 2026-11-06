import 'dart:convert';
import 'dart:math' as math;

/// Income tax and GST rules as data. Each financial year has a JSON rules
/// file; the app ships the years below and the user can import or edit
/// rules when a budget changes them, without an app update. Amounts are in
/// whole rupees and rates in percent, so the file is easy to read and edit.
///
/// Built-in values were checked on 6 November 2026 against the e-filing
/// portal's tax slab page for AY 2026-27 and the Income Tax Department's
/// threshold table (standard deduction), and for FY 2026-27 against the
/// Finance Bill 2026 memorandum (slabs unchanged; new-regime surcharge
/// capped at 25%). GST rates follow the GST 2.0 rate notifications
/// effective 22 September 2025. Results are estimates, not tax advice.

const _slabsNew = [
  {'upTo': 400000, 'rate': 0},
  {'upTo': 800000, 'rate': 5},
  {'upTo': 1200000, 'rate': 10},
  {'upTo': 1600000, 'rate': 15},
  {'upTo': 2000000, 'rate': 20},
  {'upTo': 2400000, 'rate': 25},
  {'upTo': null, 'rate': 30},
];

const _oldTail = [
  {'upTo': 1000000, 'rate': 20},
  {'upTo': null, 'rate': 30},
];

Map<String, Object?> _builtIn(String year, String source, String notes) => {
      'schemaVersion': 1,
      'financialYear': year,
      'source': source,
      'lastVerified': '2026-11-06',
      'notes': notes,
      'newRegime': {
        'standardDeduction': 75000,
        'slabs': _slabsNew,
        'rebate': {'incomeLimit': 1200000, 'maxRebate': 60000},
      },
      'oldRegime': {
        'standardDeduction': 50000,
        'slabs': {
          'below60': [
            {'upTo': 250000, 'rate': 0},
            {'upTo': 500000, 'rate': 5},
            ..._oldTail,
          ],
          'senior': [
            {'upTo': 300000, 'rate': 0},
            {'upTo': 500000, 'rate': 5},
            ..._oldTail,
          ],
          'superSenior': [
            {'upTo': 500000, 'rate': 0},
            ..._oldTail,
          ],
        },
        'rebate': {'incomeLimit': 500000, 'maxRebate': 12500},
        'limits': {'section80C': 150000},
      },
      'surcharge': {
        'newRegime': [
          {'above': 5000000, 'rate': 10},
          {'above': 10000000, 'rate': 15},
          {'above': 20000000, 'rate': 25},
        ],
        'oldRegime': [
          {'above': 5000000, 'rate': 10},
          {'above': 10000000, 'rate': 15},
          {'above': 20000000, 'rate': 25},
          {'above': 50000000, 'rate': 37},
        ],
      },
      'cessPercent': 4,
      'gst': {
        'effectiveFrom': '2025-09-22',
        'source':
            'GST rate notifications (CGST Rate) dated 17 Sep 2025, effective 22 Sep 2025 — cbic-gst.gov.in',
        'rates': [
          {'rate': 0, 'label': 'Nil (exempt essentials)'},
          {'rate': 5, 'label': 'Merit rate (daily-use goods)'},
          {'rate': 18, 'label': 'Standard rate'},
          {'rate': 40, 'label': 'Luxury and sin goods'},
          {'rate': 3, 'label': 'Gold, silver and jewellery'},
          {'rate': 0.25, 'label': 'Rough diamonds and stones'},
        ],
      },
    };

/// Rules shipped with the app, by financial year.
final Map<String, String> builtInTaxRules = {
  '2025-26': jsonEncode(_builtIn(
      '2025-26',
      'https://www.incometax.gov.in/iec/foportal/help/individual/return-applicable-1',
      'AY 2026-27. Checked against the e-filing portal tax slabs page.')),
  '2026-27': jsonEncode(_builtIn(
      '2026-27',
      'https://www.indiabudget.gov.in/doc/memo.pdf',
      'Tax Year 2026-27 under the Income-tax Act, 2025. Budget 2026 kept the slabs; re-check after any later change.')),
};

/// The Indian financial year (April to March) containing [date], e.g.
/// "2026-27" for any date from 1 April 2026 to 31 March 2027.
String financialYearOf(DateTime date) {
  final start = date.month >= 4 ? date.year : date.year - 1;
  return '$start-${((start + 1) % 100).toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Model

class Slab {
  const Slab(this.upTo, this.rate);

  /// Upper limit in rupees; null for the top slab.
  final int? upTo;
  final double rate;
}

class RegimeRules {
  const RegimeRules({
    required this.standardDeduction,
    required this.slabs,
    required this.rebateIncomeLimit,
    required this.maxRebate,
  });

  final int standardDeduction;

  /// Slabs by age group: "below60", "senior", "superSenior". The new
  /// regime has one set for everyone, stored under "below60".
  final Map<String, List<Slab>> slabs;
  final int rebateIncomeLimit;
  final int maxRebate;

  List<Slab> slabsFor(AgeGroup age) => slabs[age.name] ?? slabs['below60']!;
}

enum AgeGroup { below60, senior, superSenior }

extension AgeGroupLabel on AgeGroup {
  String get label => switch (this) {
        AgeGroup.below60 => 'Below 60',
        AgeGroup.senior => '60 to 79',
        AgeGroup.superSenior => '80 and above',
      };
}

class GstRate {
  const GstRate(this.rate, this.label);

  final double rate;
  final String label;
}

class TaxRules {
  const TaxRules({
    required this.financialYear,
    required this.source,
    required this.lastVerified,
    required this.notes,
    required this.newRegime,
    required this.oldRegime,
    required this.section80CLimit,
    required this.surchargeNew,
    required this.surchargeOld,
    required this.cessPercent,
    required this.gstRates,
    required this.gstEffectiveFrom,
    required this.gstSource,
  });

  final String financialYear;
  final String source;
  final String lastVerified;
  final String notes;
  final RegimeRules newRegime;
  final RegimeRules oldRegime;
  final int section80CLimit;
  final List<({int above, double rate})> surchargeNew;
  final List<({int above, double rate})> surchargeOld;
  final double cessPercent;
  final List<GstRate> gstRates;
  final String gstEffectiveFrom;
  final String gstSource;
}

/// Reads and checks a rules file. Throws [FormatException] with a message
/// that says what is wrong, so a bad import is refused, not half-applied.
TaxRules parseTaxRules(String source) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException {
    throw const FormatException('This is not valid JSON.');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('The rules must be a JSON object.');
  }
  final json = decoded;
  T need<T>(Map<String, dynamic> map, String key, String where) {
    final value = map[key];
    if (value is! T) {
      throw FormatException('Missing or wrong "$key" in $where.');
    }
    return value;
  }

  if (json['schemaVersion'] != 1) {
    throw const FormatException('Unsupported schemaVersion (expected 1).');
  }
  final year = need<String>(json, 'financialYear', 'the file');
  if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(year)) {
    throw const FormatException('financialYear must look like "2026-27".');
  }

  double rate(Object? value, String where) {
    if (value is! num || value < 0 || value > 100) {
      throw FormatException('Rate in $where must be a number from 0 to 100.');
    }
    return value.toDouble();
  }

  int rupees(Object? value, String where) {
    if (value is! num || value < 0 || value != value.roundToDouble()) {
      throw FormatException('$where must be a whole number of rupees.');
    }
    return value.toInt();
  }

  List<Slab> slabs(Object? value, String where) {
    if (value is! List || value.isEmpty) {
      throw FormatException('$where must be a list of slabs.');
    }
    final result = <Slab>[];
    int? previous;
    for (var i = 0; i < value.length; i++) {
      final item = value[i];
      if (item is! Map) {
        throw FormatException('Slab ${i + 1} in $where is not an object.');
      }
      final upTo = item['upTo'];
      final last = i == value.length - 1;
      if (last != (upTo == null)) {
        throw FormatException('In $where only the last slab has "upTo": null.');
      }
      final limit =
          upTo == null ? null : rupees(upTo, '$where slab ${i + 1} upTo');
      if (limit != null && previous != null && limit <= previous) {
        throw FormatException('Slabs in $where must go up in order.');
      }
      previous = limit ?? previous;
      result.add(Slab(limit, rate(item['rate'], '$where slab ${i + 1}')));
    }
    return result;
  }

  RegimeRules regime(String key) {
    final map = need<Map<String, dynamic>>(json, key, 'the file');
    final rebate = need<Map<String, dynamic>>(map, 'rebate', key);
    final rawSlabs = map['slabs'];
    final bySlab = rawSlabs is Map
        ? {
            for (final entry in rawSlabs.entries)
              entry.key as String: slabs(entry.value, '$key ${entry.key}'),
          }
        : {'below60': slabs(rawSlabs, key)};
    if (!bySlab.containsKey('below60')) {
      throw FormatException('$key slabs need a "below60" list.');
    }
    return RegimeRules(
      standardDeduction:
          rupees(map['standardDeduction'], '$key standardDeduction'),
      slabs: bySlab,
      rebateIncomeLimit:
          rupees(rebate['incomeLimit'], '$key rebate incomeLimit'),
      maxRebate: rupees(rebate['maxRebate'], '$key rebate maxRebate'),
    );
  }

  List<({int above, double rate})> surcharge(Object? value, String where) {
    if (value is! List) throw FormatException('$where must be a list.');
    return [
      for (final item in value)
        if (item is Map)
          (
            above: rupees(item['above'], '$where above'),
            rate: rate(item['rate'], where)
          )
        else
          throw FormatException('$where has an entry that is not an object.'),
    ]..sort((a, b) => a.above.compareTo(b.above));
  }

  final surchargeMap =
      need<Map<String, dynamic>>(json, 'surcharge', 'the file');
  final gst = need<Map<String, dynamic>>(json, 'gst', 'the file');
  final gstRates = need<List<dynamic>>(gst, 'rates', 'gst');
  final oldMap = need<Map<String, dynamic>>(json, 'oldRegime', 'the file');
  final limits = oldMap['limits'];
  return TaxRules(
    financialYear: year,
    source: json['source'] as String? ?? '',
    lastVerified: json['lastVerified'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
    newRegime: regime('newRegime'),
    oldRegime: regime('oldRegime'),
    section80CLimit: limits is Map && limits['section80C'] != null
        ? rupees(limits['section80C'], 'section80C limit')
        : 150000,
    surchargeNew: surcharge(surchargeMap['newRegime'], 'surcharge newRegime'),
    surchargeOld: surcharge(surchargeMap['oldRegime'], 'surcharge oldRegime'),
    cessPercent: rate(json['cessPercent'], 'cessPercent'),
    gstRates: [
      for (final item in gstRates)
        if (item is Map)
          GstRate(
              rate(item['rate'], 'gst rates'), item['label'] as String? ?? '')
        else
          throw const FormatException('gst rates must be objects.'),
    ],
    gstEffectiveFrom: gst['effectiveFrom'] as String? ?? '',
    gstSource: gst['source'] as String? ?? '',
  );
}

/// Every value that differs between two rules files, as "path: old → new",
/// so the user sees exactly what an import changes before applying it.
List<String> diffTaxRules(String before, String after) {
  final changes = <String>[];
  void walk(String path, Object? a, Object? b) {
    if (a is Map && b is Map) {
      for (final key in {...a.keys, ...b.keys}) {
        walk(path.isEmpty ? '$key' : '$path.$key', a[key], b[key]);
      }
    } else if (a is List && b is List) {
      for (var i = 0; i < math.max(a.length, b.length); i++) {
        walk('$path[${i + 1}]', i < a.length ? a[i] : null,
            i < b.length ? b[i] : null);
      }
    } else if (a != b && !(a is num && b is num && a == b)) {
      changes.add('$path: ${a ?? '—'} → ${b ?? '—'}');
    }
  }

  walk('', jsonDecode(before), jsonDecode(after));
  return changes;
}

// ---------------------------------------------------------------------------
// Income tax

class TaxInput {
  const TaxInput({
    this.salary = 0,
    this.otherIncome = 0,
    this.section80C = 0,
    this.otherDeductions = 0,
    this.age = AgeGroup.below60,
  });

  /// Gross salary or pension for the year, in rupees.
  final int salary;

  /// Interest, rent, freelance and other income, in rupees.
  final int otherIncome;

  /// Old regime only: 80C investments (capped by the rules).
  final int section80C;

  /// Old regime only: 80D, HRA exemption, home-loan interest and other
  /// deductions, in rupees.
  final int otherDeductions;
  final AgeGroup age;
}

class TaxResult {
  const TaxResult({
    required this.taxableIncome,
    required this.slabTax,
    required this.rebate,
    required this.surcharge,
    required this.cess,
    required this.steps,
  });

  final int taxableIncome;
  final int slabTax;
  final int rebate;
  final int surcharge;
  final int cess;

  /// The working, line by line.
  final List<String> steps;

  int get total => slabTax - rebate + surcharge + cess;
}

int _slabTax(int income, List<Slab> slabs) {
  var tax = 0.0;
  var lower = 0;
  for (final slab in slabs) {
    final upper = slab.upTo ?? income;
    if (income > lower) {
      tax += (math.min(income, upper) - lower) * slab.rate / 100;
    }
    if (slab.upTo == null || income <= slab.upTo!) break;
    lower = slab.upTo!;
  }
  return tax.round();
}

String _r(int rupees) {
  final digits = rupees.abs().toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final left = digits.length - i;
    if (i > 0 && (left == 3 || (left > 3 && (left - 3) % 2 == 0))) {
      out.write(',');
    }
    out.write(digits[i]);
  }
  return '${rupees < 0 ? '-' : ''}₹$out';
}

/// Tax for one regime, with rebate (and its marginal relief), surcharge
/// (and its marginal relief) and cess, rounded to the rupee.
TaxResult computeTax(TaxRules rules, TaxInput input,
    {required bool newRegime}) {
  final regime = newRegime ? rules.newRegime : rules.oldRegime;
  final steps = <String>[];
  final standard = math.min(regime.standardDeduction, input.salary);
  var deductions = standard;
  steps.add(
      'Income ${_r(input.salary + input.otherIncome)} − standard deduction ${_r(standard)}');
  if (!newRegime) {
    final c80 = math.min(input.section80C, rules.section80CLimit);
    deductions += c80 + input.otherDeductions;
    if (c80 > 0) {
      steps.add('− 80C ${_r(c80)} (limit ${_r(rules.section80CLimit)})');
    }
    if (input.otherDeductions > 0) {
      steps.add('− other deductions ${_r(input.otherDeductions)}');
    }
  }
  final taxable = math.max(0, input.salary + input.otherIncome - deductions);
  steps.add('Taxable income ${_r(taxable)}');
  final slabs = regime.slabsFor(newRegime ? AgeGroup.below60 : input.age);
  var tax = _slabTax(taxable, slabs);
  steps.add('Tax by slabs ${_r(tax)}');

  var rebate = 0;
  if (taxable <= regime.rebateIncomeLimit) {
    rebate = math.min(tax, regime.maxRebate);
    if (rebate > 0) steps.add('− rebate (87A) ${_r(rebate)}');
  } else if (newRegime && tax > taxable - regime.rebateIncomeLimit) {
    // Marginal relief: just above the limit, tax cannot exceed the income
    // over the limit.
    rebate = tax - (taxable - regime.rebateIncomeLimit);
    steps.add(
        '− marginal relief ${_r(rebate)} (tax limited to income above ${_r(regime.rebateIncomeLimit)})');
  }
  final afterRebate = tax - rebate;

  var surcharge = 0;
  final bands = newRegime ? rules.surchargeNew : rules.surchargeOld;
  final band = bands.lastWhere((item) => taxable > item.above,
      orElse: () => (above: -1, rate: 0));
  if (band.above >= 0) {
    surcharge = (afterRebate * band.rate / 100).round();
    // Marginal relief: crossing a threshold cannot cost more in tax plus
    // surcharge than the income above it.
    final below = bands.where((item) => item.above < band.above).toList();
    final atThreshold = _slabTax(band.above, slabs);
    final surchargeAt =
        below.isEmpty ? 0 : (atThreshold * below.last.rate / 100).round();
    final cap = atThreshold + surchargeAt + (taxable - band.above);
    if (afterRebate + surcharge > cap) {
      surcharge = math.max(0, cap - afterRebate);
    }
    steps.add('+ surcharge ${band.rate}% ${_r(surcharge)}');
  }
  final cess = ((afterRebate + surcharge) * rules.cessPercent / 100).round();
  if (cess > 0) steps.add('+ cess ${rules.cessPercent}% ${_r(cess)}');
  return TaxResult(
    taxableIncome: taxable,
    slabTax: tax,
    rebate: rebate,
    surcharge: surcharge,
    cess: cess,
    steps: steps,
  );
}

// ---------------------------------------------------------------------------
// GST

class GstResult {
  const GstResult({required this.base, required this.gst, required this.total});

  final double base;
  final double gst;
  final double total;

  /// Intra-state supply: half each as CGST and SGST.
  double get cgst => gst / 2;
  double get sgst => gst / 2;
}

/// Adds GST to [amount] at [ratePercent], or, with [inclusive], takes it
/// out of an amount that already includes it.
GstResult gst(double amount, double ratePercent, {bool inclusive = false}) {
  final base = inclusive ? amount * 100 / (100 + ratePercent) : amount;
  final tax = base * ratePercent / 100;
  return GstResult(base: base, gst: tax, total: base + tax);
}
