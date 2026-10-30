import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import 'widgets.dart';

class BarSeries {
  const BarSeries(this.label, this.color, this.values);

  final String label;
  final Color color;
  final List<int> values;
}

/// Vertical bar chart with one or more series per group. Long-press or hover
/// a group for exact values. Values are in paise.
class BarChart extends StatelessWidget {
  const BarChart({
    required this.labels,
    required this.series,
    this.height = 180,
    this.showEveryNthLabel = 1,
    this.semanticLabel,
    super.key,
  });

  final List<String> labels;
  final List<BarSeries> series;
  final double height;
  final int showEveryNthLabel;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final maxValue = series
        .expand((item) => item.values)
        .fold<int>(0, (largest, value) => math.max(largest, value));
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Semantics(
      label: semanticLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (series.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(
                spacing: 14,
                children: [
                  for (final item in series)
                    _Legend(color: item.color, label: item.label),
                ],
              ),
            ),
          Text(maxValue == 0 ? '' : formatMoneyCompact(maxValue),
              style: theme.textTheme.labelSmall?.copyWith(color: muted)),
          const SizedBox(height: 4),
          SizedBox(
            height: height,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: motion(context, 650),
              curve: Curves.easeOutCubic,
              builder: (context, grow, _) => Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var index = 0; index < labels.length; index++)
                    Expanded(
                      child: Tooltip(
                        triggerMode: TooltipTriggerMode.longPress,
                        message: [
                          labels[index],
                          for (final item in series)
                            '${item.label}: ${formatMoney(item.values[index])}',
                        ].join('\n'),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: labels.length > 14 ? 1 : 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (final item in series)
                                Expanded(
                                  child: Container(
                                    height: maxValue == 0
                                        ? 0
                                        : math.max(
                                            item.values[index] > 0 ? 2.0 : 0.0,
                                            height *
                                                grow *
                                                item.values[index] /
                                                maxValue),
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 0.5),
                                    decoration: BoxDecoration(
                                      color: item.color,
                                      borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(4)),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 4),
          Row(
            children: [
              for (var index = 0; index < labels.length; index++)
                Expanded(
                  child: Text(
                    index % showEveryNthLabel == 0 ? labels[index] : '',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class DonutSlice {
  const DonutSlice(this.label, this.value, this.color);

  final String label;
  final int value;
  final Color color;
}

/// Category share as a donut with a legend listing exact amounts.
class DonutChart extends StatelessWidget {
  const DonutChart({
    required this.slices,
    required this.centerLabel,
    required this.centerValue,
    this.size = 150,
    super.key,
  });

  final List<DonutSlice> slices;
  final String centerLabel;
  final String centerValue;
  final double size;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<int>(0, (sum, slice) => sum + slice.value);
    final theme = Theme.of(context);
    final chart = SizedBox.square(
      dimension: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: motion(context, 800),
        curve: Curves.easeOutCubic,
        builder: (context, sweep, _) => CustomPaint(
          painter: _DonutPainter(
            slices: slices,
            total: total,
            sweep: sweep,
            track: theme.colorScheme.surfaceContainerHighest,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(centerLabel, style: theme.textTheme.labelSmall),
                FittedBox(
                  child: Text(centerValue,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final legend = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final slice in slices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                _Dot(color: slice.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(slice.label,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Text(
                  total == 0 ? '' : '${(slice.value * 100 / total).round()}%',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(width: 8),
                Text(formatMoneyCompact(slice.value),
                    style: theme.textTheme.labelLarge),
              ],
            ),
          ),
      ],
    );
    return Semantics(
      label:
          'Category breakdown: ${slices.map((s) => '${s.label} ${formatMoney(s.value)}').join(', ')}',
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 360
            ? Column(children: [chart, const SizedBox(height: 16), legend])
            : Row(children: [
                chart,
                const SizedBox(width: 20),
                Expanded(child: legend),
              ]),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.total,
    required this.sweep,
    required this.track,
  });

  final List<DonutSlice> slices;
  final int total;
  final double sweep;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.14;
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (total <= 0) return;
    var start = -math.pi / 2;
    for (final slice in slices) {
      final angle = math.pi * 2 * slice.value / total * sweep;
      canvas.drawArc(rect, start, math.max(0, angle - 0.02), false,
          paint..color = slice.color);
      start += angle;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.sweep != sweep ||
      oldDelegate.total != total ||
      oldDelegate.slices != slices;
}

/// Line chart for values that may be negative, such as monthly cash flow.
class LineChart extends StatelessWidget {
  const LineChart({
    required this.labels,
    required this.values,
    required this.color,
    this.height = 150,
    super.key,
  });

  final List<String> labels;
  final List<int> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        SizedBox(
          height: height,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: motion(context, 700),
            builder: (context, progress, _) => CustomPaint(
              size: Size.infinite,
              painter: _LinePainter(
                values: values,
                color: color,
                zero: theme.colorScheme.outlineVariant,
                progress: progress,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: Tooltip(
                  message: '${labels[i]}: ${formatMoney(values[i])}',
                  child: Text(labels[i],
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.values,
    required this.color,
    required this.zero,
    required this.progress,
  });

  final List<int> values;
  final Color color;
  final Color zero;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxValue = values.fold<int>(0, math.max);
    final minValue = values.fold<int>(0, math.min);
    final span = (maxValue - minValue) == 0 ? 1 : maxValue - minValue;
    double y(int value) =>
        size.height - 8 - (value - minValue) / span * (size.height - 16);
    final step = size.width / values.length;
    final points = [
      for (var i = 0; i < values.length; i++)
        Offset(step * i + step / 2, y((values[i] * progress).round())),
    ];
    canvas.drawLine(
        Offset(0, y(0)),
        Offset(size.width, y(0)),
        Paint()
          ..color = zero
          ..strokeWidth = 1);
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round);
    for (final point in points) {
      canvas.drawCircle(point, 4, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_LinePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.values != values;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(color: color),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
