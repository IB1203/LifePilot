import 'package:flutter/material.dart';

const _seed = Color(0xFF167D72);

/// Semantic colors used across finance and task screens, tuned for contrast
/// in both themes.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.income,
    required this.expense,
    required this.warning,
    required this.chart,
  });

  final Color income;
  final Color expense;
  final Color warning;
  final List<Color> chart;

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  @override
  AppColors copyWith({
    Color? income,
    Color? expense,
    Color? warning,
    List<Color>? chart,
  }) =>
      AppColors(
        income: income ?? this.income,
        expense: expense ?? this.expense,
        warning: warning ?? this.warning,
        chart: chart ?? this.chart,
      );

  @override
  AppColors lerp(AppColors? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

const _lightColors = AppColors(
  income: Color(0xFF16775F),
  expense: Color(0xFFB4483A),
  warning: Color(0xFFA86200),
  chart: [
    Color(0xFF167D72),
    Color(0xFFD0743C),
    Color(0xFF4F6BD8),
    Color(0xFFB0478F),
    Color(0xFF7E9B2E),
    Color(0xFF8A6BD1),
    Color(0xFF9A8873),
  ],
);

const _darkColors = AppColors(
  income: Color(0xFF6FD3B5),
  expense: Color(0xFFFF9A8A),
  warning: Color(0xFFFFC266),
  chart: [
    Color(0xFF5FC9B8),
    Color(0xFFF0A06A),
    Color(0xFF8FA3FF),
    Color(0xFFE48AC6),
    Color(0xFFB4CF66),
    Color(0xFFB9A2F5),
    Color(0xFFC9B9A5),
  ],
);

ThemeData buildTheme(Brightness brightness, {Color seed = _seed}) {
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  final dark = brightness == Brightness.dark;
  const radius = BorderRadius.all(Radius.circular(16));
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    brightness: brightness,
  );
  return base.copyWith(
    scaffoldBackgroundColor: dark ? scheme.surface : const Color(0xFFF5F8F6),
    extensions: [dark ? _darkColors : _lightColors],
    textTheme: base.textTheme.copyWith(
      headlineSmall: base.textTheme.headlineSmall
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleLarge:
          base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium:
          base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: dark ? scheme.surfaceContainer : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: dark ? 0.4 : 0.55)),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? scheme.surface : const Color(0xFFF5F8F6),
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 1,
      titleTextStyle: base.textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: dark ? scheme.surfaceContainer : Colors.white,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll(
          base.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? scheme.surfaceContainerHigh : Colors.white,
      border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12))),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10))),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12))),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      showDragHandle: true,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
    ),
  );
}
