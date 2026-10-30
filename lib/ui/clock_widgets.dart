import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'widgets.dart';

/// Rebuilds only its [builder] subtree on a fixed interval, aligned to the
/// wall clock, so a ticking clock does not rebuild the surrounding screen.
class Tick extends StatefulWidget {
  const Tick({
    required this.builder,
    this.interval = const Duration(seconds: 1),
    this.now,
    super.key,
  });

  final Widget Function(BuildContext context, DateTime now) builder;
  final Duration interval;

  /// Time source, for tests.
  final DateTime Function()? now;

  @override
  State<Tick> createState() => _TickState();
}

class _TickState extends State<Tick> {
  Timer? _timer;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    final interval = widget.interval.inMilliseconds;
    final now = _now();
    final wait = interval - now.millisecondsSinceEpoch % interval;
    _timer =
        Timer(Duration(milliseconds: wait < 15 ? wait + interval : wait), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _now());
}

/// Analog clock. The second hand sweeps smoothly using a ticker that only
/// repaints the painter; with reduced motion it steps once per second.
class AnalogClock extends StatefulWidget {
  const AnalogClock({this.size = 200, this.now, super.key});

  final double size;
  final DateTime Function()? now;

  @override
  State<AnalogClock> createState() => _AnalogClockState();
}

class _AnalogClockState extends State<AnalogClock>
    with SingleTickerProviderStateMixin {
  late final ValueNotifier<DateTime> _time;
  late final Ticker _ticker;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _time = ValueNotifier(_now());
    _ticker = createTicker((_) {
      final now = _now();
      final stepped = reduceMotion(context);
      if (stepped && now.second == _time.value.second) return;
      _time.value = now;
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Analog clock',
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _ClockPainter(
            time: _time,
            face: scheme.surfaceContainerHighest,
            ticks: scheme.onSurfaceVariant,
            hands: scheme.onSurface,
            accent: scheme.primary,
            smooth: !reduceMotion(context),
          ),
        ),
      ),
    );
  }
}

class _ClockPainter extends CustomPainter {
  _ClockPainter({
    required this.time,
    required this.face,
    required this.ticks,
    required this.hands,
    required this.accent,
    required this.smooth,
  }) : super(repaint: time);

  final ValueNotifier<DateTime> time;
  final Color face;
  final Color ticks;
  final Color hands;
  final Color accent;
  final bool smooth;

  @override
  void paint(Canvas canvas, Size size) {
    final now = time.value;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(center, radius, Paint()..color = face);

    final tickPaint = Paint()
      ..color = ticks
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 60; i++) {
      final major = i % 5 == 0;
      tickPaint.strokeWidth = major ? 3 : 1;
      final angle = i * math.pi / 30;
      final outer = radius * 0.92;
      final inner = radius * (major ? 0.8 : 0.86);
      canvas.drawLine(
        center + Offset(math.sin(angle), -math.cos(angle)) * inner,
        center + Offset(math.sin(angle), -math.cos(angle)) * outer,
        tickPaint,
      );
    }

    final seconds = now.second + (smooth ? now.millisecond / 1000 : 0);
    final minutes = now.minute + seconds / 60;
    final hours = (now.hour % 12) + minutes / 60;
    void hand(double turns, double length, double width, Color color) {
      final angle = turns * 2 * math.pi;
      canvas.drawLine(
        center - Offset(math.sin(angle), -math.cos(angle)) * radius * 0.08,
        center + Offset(math.sin(angle), -math.cos(angle)) * radius * length,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
    }

    hand(hours / 12, 0.5, radius * 0.06, hands);
    hand(minutes / 60, 0.72, radius * 0.04, hands);
    hand(seconds / 60, 0.8, radius * 0.018, accent);
    canvas.drawCircle(center, radius * 0.045, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_ClockPainter oldDelegate) =>
      oldDelegate.face != face ||
      oldDelegate.hands != hands ||
      oldDelegate.smooth != smooth;
}

/// Countdown ring whose progress animates smoothly between ticks.
class CountdownRing extends StatelessWidget {
  const CountdownRing({
    required this.progress,
    required this.child,
    this.size = 240,
    this.color,
    super.key,
  });

  /// Fraction remaining, from 1 to 0.
  final double progress;
  final Widget child;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: progress.clamp(0.0, 1.0)),
        duration: motion(context, 900),
        builder: (context, value, _) => ProgressRing(
          value: value,
          size: size,
          stroke: 10,
          color: color,
          animate: false,
          child: child,
        ),
      );
}
