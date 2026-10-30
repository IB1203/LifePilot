/// Evaluates calculator input such as `1200 + 18%` or `(450 × 3) ÷ 2`.
///
/// `%` after a number divides it by 100, except that `a + b%` and `a − b%`
/// add or subtract b percent of a, as on phone calculators (so
/// `1200 + 18%` is 1416). Returns null for incomplete or invalid input,
/// including division by zero.
double? evaluateExpression(String input) {
  final tokens = _tokenize(input);
  if (tokens == null || tokens.isEmpty) return null;
  final parser = _Parser(tokens);
  try {
    final value = parser.expression().value;
    if (!parser.atEnd || value.isNaN || value.isInfinite) return null;
    return value;
  } on FormatException {
    return null;
  }
}

/// Formats a result without float noise: up to 8 decimals, trailing zeros
/// removed.
String formatCalculatorResult(double value) {
  final rounded = double.parse(value.toStringAsFixed(8));
  if (rounded == rounded.truncateToDouble() && rounded.abs() < 1e15) {
    return rounded.toInt().toString();
  }
  return rounded
      .toStringAsFixed(8)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

const _operators = '+-×÷*/%()';

List<String>? _tokenize(String input) {
  final tokens = <String>[];
  final source = input.replaceAll(' ', '').replaceAll('−', '-');
  var i = 0;
  while (i < source.length) {
    final char = source[i];
    if (_operators.contains(char)) {
      tokens.add(switch (char) {
        '*' => '×',
        '/' => '÷',
        _ => char,
      });
      i++;
      continue;
    }
    final match = RegExp(r'\d+\.?\d*|\.\d+').matchAsPrefix(source, i);
    if (match == null) return null;
    tokens.add(match.group(0)!);
    i = match.end;
  }
  return tokens;
}

class _Value {
  const _Value(this.value, {this.percent = false});

  final double value;

  /// A lone `b%`, which `+` and `−` treat as a percentage of the left side.
  final bool percent;
}

class _Parser {
  _Parser(this.tokens);

  final List<String> tokens;
  int _index = 0;

  bool get atEnd => _index >= tokens.length;
  String? get _peek => atEnd ? null : tokens[_index];

  String _next() {
    if (atEnd) throw const FormatException('Incomplete expression');
    return tokens[_index++];
  }

  _Value expression() {
    var left = _term().value;
    while (_peek == '+' || _peek == '-') {
      final op = _next();
      final right = _term();
      final amount = right.percent ? left * right.value : right.value;
      left = op == '+' ? left + amount : left - amount;
    }
    return _Value(left);
  }

  _Value _term() {
    var left = _factor();
    while (_peek == '×' || _peek == '÷') {
      final op = _next();
      final right = _factor().value;
      if (op == '÷' && right == 0) {
        throw const FormatException('Division by zero');
      }
      left = _Value(op == '×' ? left.value * right : left.value / right);
    }
    return left;
  }

  _Value _factor() {
    if (_peek == '-') {
      _next();
      return _Value(-_factor().value);
    }
    if (_peek == '+') {
      _next();
      return _factor();
    }
    double value;
    final token = _next();
    if (token == '(') {
      value = expression().value;
      if (_next() != ')') throw const FormatException('Missing )');
    } else {
      final number = double.tryParse(token);
      if (number == null) throw const FormatException('Expected a number');
      value = number;
    }
    if (_peek == '%') {
      _next();
      return _Value(value / 100, percent: true);
    }
    return _Value(value);
  }
}
