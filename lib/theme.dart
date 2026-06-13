import 'package:flutter/material.dart';

class AppTheme {
  // ─── Colors ───────────────────────────────────────────────────────────────
  static const Color background   = Color(0xFF0F1117);
  static const Color surface      = Color(0xFF1A1D27);
  static const Color surfaceAlt   = Color(0xFF22263A);
  static const Color primary      = Color(0xFF4F8EF7);
  static const Color primaryDark  = Color(0xFF1E3A5F);
  static const Color green        = Color(0xFF22c55e);
  static const Color yellow       = Color(0xFFf59e0b);
  static const Color red          = Color(0xFFef4444);
  static const Color indigo       = Color(0xFF6366f1);
  static const Color textPrimary  = Color(0xFFFFFFFF);
  static const Color textSecondary= Color(0xFF9CA3AF);
  static const Color textDim      = Color(0xFF6B7280);
  static const Color acBg         = Color(0xFF1E3A5F);
  static const Color acBlue       = Color(0xFF93C5FD);
  static const Color nonAcBg      = Color(0xFF1F2937);
  static const Color nonAcText    = Color(0xFF9CA3AF);
  static const Color blueDark     = Color(0xFF1E3A5F);
  static const Color blueLight    = Color(0xFF93C5FD);
  static const Color blue         = Color(0xFF3B82F6);

  // ─── Theme ────────────────────────────────────────────────────────────────
  static ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      surface: surface,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: primary.withValues(alpha: 0.2),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(color: textSecondary, fontSize: 11),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      foregroundColor: textPrimary,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    ),
    dividerColor: surfaceAlt,
    useMaterial3: true,
  );
}
