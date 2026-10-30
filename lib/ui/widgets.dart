import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models.dart';
import 'theme.dart';

/// True when the user asked the system to reduce motion.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

Duration motion(BuildContext context, int milliseconds) => reduceMotion(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

class SectionHeader extends StatelessWidget {
  const SectionHeader(
      {required this.title, this.action, this.onAction, super.key});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      )),
            ),
            if (action != null)
              TextButton(onPressed: onAction, child: Text(action!)),
          ],
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: compact ? 22 : 28, color: scheme.primary),
            ),
            const SizedBox(height: 12),
            Text(title,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            if (actionLabel != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: onAction,
                icon: const Icon(Icons.add),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Progress bar that animates to its value. Values over 1 show as full.
class AnimatedBar extends StatelessWidget {
  const AnimatedBar({
    required this.value,
    this.color,
    this.height = 8,
    super.key,
  });

  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: motion(context, 700),
        curve: Curves.easeOutCubic,
        builder: (context, animated, _) => LinearProgressIndicator(
          value: animated,
          minHeight: height,
          color: color,
          borderRadius: BorderRadius.circular(height),
          backgroundColor:
              Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      );
}

/// Circular progress with content in the middle, animated to its value.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    required this.value,
    required this.child,
    this.size = 56,
    this.stroke = 6,
    this.color,
    this.animate = true,
    super.key,
  });

  final double value;
  final Widget child;
  final double size;
  final double stroke;
  final Color? color;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    Widget ring(double progress) => SizedBox(
          width: size,
          height: size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: progress,
                strokeWidth: stroke,
                strokeCap: StrokeCap.round,
                color: color,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              Center(child: child),
            ],
          ),
        );
    if (!animate) return ring(value.clamp(0.0, 1.0));
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
      duration: motion(context, 800),
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) => ring(animated),
    );
  }
}

/// Fades and slides its child in once, after a short delay based on [index],
/// to stagger lists of cards. Shows immediately when motion is reduced.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({required this.index, required this.child, super.key});

  final int index;
  final Widget child;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> {
  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(Duration(milliseconds: 40 + 50 * widget.index.clamp(0, 8)),
        () => mounted ? setState(() => _visible = true) : null);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return widget.child;
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.06),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.caption,
    this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? Theme.of(context).colorScheme.primary;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
              ),
              if (caption != null) ...[
                const SizedBox(height: 2),
                Text(caption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Two-column grid whose rows grow with their content, so tiles stay
/// readable at large text sizes (unlike a fixed aspect-ratio grid).
class TileGrid extends StatelessWidget {
  const TileGrid({required this.children, this.spacing = 10, super.key});

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (var i = 0; i < children.length; i += 2) ...[
            if (i > 0) SizedBox(height: spacing),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: children[i]),
                  SizedBox(width: spacing),
                  Expanded(
                    child: i + 1 < children.length
                        ? children[i + 1]
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ],
        ],
      );
}

/// A list of tiles inside one card, separated by dividers.
class CardList extends StatelessWidget {
  const CardList({required this.children, this.indent = 16, super.key});

  final List<Widget> children;
  final double indent;

  @override
  Widget build(BuildContext context) => Card(
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              children[i],
              if (i < children.length - 1)
                Divider(height: 1, indent: indent, endIndent: 0),
            ],
          ],
        ),
      );
}

Color priorityColor(BuildContext context, TaskPriority priority) {
  final scheme = Theme.of(context).colorScheme;
  final colors = AppColors.of(context);
  return switch (priority) {
    TaskPriority.low => scheme.outline,
    TaskPriority.medium => scheme.primary,
    TaskPriority.high => colors.warning,
    TaskPriority.urgent => scheme.error,
  };
}

class PriorityBadge extends StatelessWidget {
  const PriorityBadge({required this.priority, super.key});

  final TaskPriority priority;

  @override
  Widget build(BuildContext context) {
    final color = priorityColor(context, priority);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(priority.label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w700)),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill({required this.label, this.color, this.icon, super.key});

  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tone = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: tone),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: tone, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

void showMessage(BuildContext context, String text, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(dialogContext).colorScheme.error,
                  foregroundColor: Theme.of(dialogContext).colorScheme.onError)
              : null,
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}

/// Page padding used by every scrollable screen, leaving room for the FAB.
const pagePadding = EdgeInsets.fromLTRB(16, 8, 16, 112);
