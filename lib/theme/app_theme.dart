import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// VT Threshold App - Dark Theme
/// Inspired by premium fitness apps with a sleek, modern aesthetic

class AppTheme {
  AppTheme._();

  // ============ COLORS ============

  // Base colors
  static const Color background = Color(0xFF000000);
  static const Color surfaceDark = Color(0xFF0D0D0D);
  static const Color surfaceCard = Color(0xFF1A1A1A);
  static const Color surfaceCardLight = Color(0xFF242424);

  // Border colors
  static const Color borderSubtle = Color(0xFF2A2A2A);
  static const Color borderMedium = Color(0xFF3A3A3A);

  // Text colors
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0B0B0);
  static const Color textMuted = Color(0xFF707070);
  static const Color textDisabled = Color(0xFF505050);

  // Accent colors
  static const Color accentBlue = Color(0xFF4A9EFF);
  static const Color accentBlueDim = Color(0xFF2D5A8A);
  static const Color accentGreen = Color(0xFF34C759);
  static const Color accentGreenDim = Color(0xFF1E5631);
  static const Color accentRed = Color(0xFFFF453A);
  static const Color accentRedDim = Color(0xFF8A2B27);
  static const Color accentOrange = Color(0xFFFF9F0A);
  static const Color accentOrangeDim = Color(0xFF8A5A0A);
  static const Color accentPurple = Color(0xFFBF5AF2);
  static const Color accentYellow = Color(0xFFFFD60A);

  // Zone colors (for workout feedback)
  static const Color zoneGreen = Color(0xFF1A3D1F);
  static const Color zoneYellow = Color(0xFF3D3A1A);
  static const Color zoneRed = Color(0xFF3D1A1A);
  static const Color zoneRecovery = Color(0xFF1A1A1A);

  // Chart colors
  static const Color chartLine = Color(0xFF4A9EFF);
  static const Color chartLineGlow = Color(0x404A9EFF);
  static const Color chartDot = Color(0x664A9EFF);
  static const Color chartThreshold = Color(0xFFFF453A);
  static const Color chartGrid = Color(0xFF2A2A2A);

  // ============ GRADIENTS ============

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1E1E1E),
      Color(0xFF141414),
    ],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF4A9EFF),
      Color(0xFF2D7DD2),
    ],
  );

  static const LinearGradient greenGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF34C759),
      Color(0xFF28A745),
    ],
  );

  // ============ SHADOWS ============

  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: Colors.black.withOpacity(0.3),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> get glowShadow => [
        BoxShadow(
          color: accentBlue.withOpacity(0.3),
          blurRadius: 20,
          spreadRadius: 2,
        ),
      ];

  static List<BoxShadow> get subtleShadow => [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ];

  // ============ BORDER RADIUS ============

  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusXLarge = 24.0;
  static const double radiusCircular = 100.0;

  // ============ SPACING ============

  static const double spacingXS = 4.0;
  static const double spacingS = 8.0;
  static const double spacingM = 16.0;
  static const double spacingL = 24.0;
  static const double spacingXL = 32.0;
  static const double spacingXXL = 48.0;

  // ============ TYPOGRAPHY ============

  static const String fontFamily = 'SF Pro Display';
  static const String fontFamilyMono = 'SF Mono';

  static const TextStyle displayLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 64,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -2,
    height: 1.1,
  );

  static const TextStyle displayMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 48,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -1.5,
    height: 1.1,
  );

  static const TextStyle headlineLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 32,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    letterSpacing: -0.5,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static const TextStyle titleLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static const TextStyle titleMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );

  static const TextStyle labelLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: textMuted,
    letterSpacing: 1.2,
  );

  static const TextStyle labelSmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: textMuted,
    letterSpacing: 0.8,
  );

  static const TextStyle monoLarge = TextStyle(
    fontFamily: fontFamilyMono,
    fontSize: 56,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    letterSpacing: -2,
  );

  static const TextStyle monoMedium = TextStyle(
    fontFamily: fontFamilyMono,
    fontSize: 32,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  // ============ DECORATIONS ============

  static BoxDecoration get cardDecoration => BoxDecoration(
        color: surfaceCard,
        borderRadius: BorderRadius.circular(radiusLarge),
        border: Border.all(color: borderSubtle, width: 1),
      );

  static BoxDecoration get cardDecorationElevated => BoxDecoration(
        gradient: cardGradient,
        borderRadius: BorderRadius.circular(radiusLarge),
        border: Border.all(color: borderSubtle, width: 1),
        boxShadow: cardShadow,
      );

  static BoxDecoration get inputDecoration => BoxDecoration(
        color: surfaceCard,
        borderRadius: BorderRadius.circular(radiusMedium),
        border: Border.all(color: borderSubtle, width: 1),
      );

  static BoxDecoration circleButtonDecoration(Color color) => BoxDecoration(
        color: color.withOpacity(0.15),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      );

  // ============ THEME DATA ============

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          primary: accentBlue,
          secondary: accentGreen,
          surface: surfaceCard,
          error: accentRed,
          onPrimary: textPrimary,
          onSecondary: textPrimary,
          onSurface: textPrimary,
          onError: textPrimary,
        ),
        fontFamily: fontFamily,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: titleLarge,
          iconTheme: IconThemeData(color: textPrimary),
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: accentBlue,
            foregroundColor: textPrimary,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMedium),
            ),
            textStyle: titleMedium,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: textSecondary,
            textStyle: bodyMedium,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
            borderSide: const BorderSide(color: borderSubtle),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
            borderSide: const BorderSide(color: borderSubtle),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
            borderSide: const BorderSide(color: accentBlue, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          hintStyle: bodyMedium.copyWith(color: textMuted),
          labelStyle: labelLarge,
        ),
        dividerTheme: const DividerThemeData(
          color: borderSubtle,
          thickness: 1,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: surfaceCard,
          contentTextStyle: bodyMedium.copyWith(color: textPrimary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
          ),
          behavior: SnackBarBehavior.floating,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: surfaceCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLarge),
          ),
          titleTextStyle: headlineMedium,
          contentTextStyle: bodyLarge,
        ),
      );
}
