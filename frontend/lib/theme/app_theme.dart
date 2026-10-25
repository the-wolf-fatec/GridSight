import 'package:flutter/material.dart';

/// Paleta pensada para o tema do desafio Tecsys:
/// - Azul-marinho profundo: infraestrutura / rede de distribuição / tecnologia
/// - Âmbar / laranja: energia elétrica
/// - Verde-teal: cobertura de sinal / sucesso
/// - Vermelho telha: alerta / ponto não coberto
class AppColors {
  AppColors._();

  static const Color background = Color(0xFF0B1622);
  static const Color surface = Color(0xFF122236);
  static const Color surfaceAlt = Color(0xFF17293F);
  static const Color primary = Color(0xFF1E4E79); // azul rede elétrica
  static const Color primaryLight = Color(0xFF2E6FA8);
  static const Color energy = Color(0xFFF4A300); // âmbar energia
  static const Color coverage = Color(0xFF14B8A6); // teal cobertura
  static const Color coverageDark = Color(0xFF0E7C70);
  static const Color alert = Color(0xFFE0523A); // alerta / não coberto
  static const Color textPrimary = Color(0xFFF3F6FA);
  static const Color textSecondary = Color(0xFFAFC0D4);
  static const Color divider = Color(0xFF223A54);
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primaryLight,
        secondary: AppColors.energy,
        tertiary: AppColors.coverage,
        error: AppColors.alert,
        surface: AppColors.surface,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.divider),
        ),
        margin: EdgeInsets.zero,
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: AppColors.surfaceAlt,
        selectedIconTheme: IconThemeData(color: AppColors.energy),
        selectedLabelTextStyle: TextStyle(color: AppColors.energy),
        unselectedIconTheme: IconThemeData(color: AppColors.textSecondary),
        unselectedLabelTextStyle: TextStyle(color: AppColors.textSecondary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surfaceAlt,
        indicatorColor: AppColors.energy.withOpacity(0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? AppColors.energy : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          );
        }),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.energy,
          foregroundColor: AppColors.background,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.coverage,
          side: const BorderSide(color: AppColors.coverage),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.coverage,
        thumbColor: AppColors.coverage,
        inactiveTrackColor: AppColors.divider,
        valueIndicatorColor: AppColors.coverageDark,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.coverage : AppColors.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.coverage.withOpacity(0.4)
              : AppColors.divider,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.energy),
      dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.coverage, width: 1.5),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}
