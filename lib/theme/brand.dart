import 'package:flutter/material.dart';

/// Codemagic Design System tokens (see BRANDING.md). Use exactly; never tint.
abstract final class Brand {
  // Brand palette (same in both themes).
  static const noBugBlue = Color(0xFF0031EA);
  static const neverBlue = Color(0xFF0051FF);
  static const continuousBlue = Color(0xFF008BF7);
  static const dashAqua = Color(0xFF00CEFF);
  static const swwYellow = Color(0xFFFF9100);
  static const nativeOrange = Color(0xFFFF4D13);
  static const red = Color(0xFFEC0C43);
  static const pinkMagic = Color(0xFFFE19FF);

  // Buttons.
  static const primary = Color(0xFF0957FF);
  static const primaryPressed = noBugBlue;

  // Dark theme.
  static const darkPage = Color(0xFF01091A);
  static const darkCardTop = Color(0xFF182238);
  static const darkCardBottom = Color(0xFF101A2C);
  static const darkBorder = Color(0x1AFFFFFF); // rgba(255,255,255,.10)
  static const darkHeading = Color(0xFFFFFFFF);
  static const darkBody = Color(0xFFD2DBEE);
  static const darkSubtle = Color(0xFF232A38);
  static const darkSubtleHover = Color(0xFF2E3646);

  // Light theme.
  static const lightPage = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFF2F5FA);
  static const lightBorder = Color(0x1411285B); // rgba(17,40,91,.08)
  static const lightHeading = Color(0xFF11285B);
  static const lightBody = Color(0xFF3A4865);
  static const lightSubtle = Color(0xFFF4F6FB);
  static const lightSubtleHover = Color(0xFFE1E9FB);

  static const blueGradient = LinearGradient(
    colors: [noBugBlue, continuousBlue],
  );
  static const magentaGradient = LinearGradient(colors: [swwYellow, pinkMagic]);

  // Radii and spacing.
  static const radiusSm = 8.0;
  static const radiusMd = 12.0;
  static const radiusCard = 20.0;
  static const radiusButton = 12.0;
  static const radiusPill = 999.0;
  static const buttonHeight = 44.0;

  static const fontFamily = 'Metropolis';
}

/// Theme-dependent brand surfaces that Material's ColorScheme can't express.
@immutable
class BrandSurfaces extends ThemeExtension<BrandSurfaces> {
  const BrandSurfaces({
    required this.cardDecoration,
    required this.cardFill,
    required this.border,
    required this.heading,
    required this.body,
    required this.subtle,
    required this.subtleHover,
    required this.subtleText,
    required this.icon,
    required this.isDark,
  });

  final BoxDecoration cardDecoration;
  final Color cardFill;
  final Color border;
  final Color heading;
  final Color body;
  final Color subtle;
  final Color subtleHover;
  final Color subtleText;
  final Color icon;
  final bool isDark;

  static const dark = BrandSurfaces(
    cardDecoration: BoxDecoration(
      // CSS 160deg ~ from top-left-ish to bottom-right-ish.
      gradient: LinearGradient(
        begin: Alignment(-0.34, -0.94),
        end: Alignment(0.34, 0.94),
        colors: [Brand.darkCardTop, Brand.darkCardBottom],
      ),
      borderRadius: BorderRadius.all(Radius.circular(Brand.radiusCard)),
      border: Border.fromBorderSide(BorderSide(color: Brand.darkBorder)),
    ),
    cardFill: Brand.darkCardTop,
    border: Brand.darkBorder,
    heading: Brand.darkHeading,
    body: Brand.darkBody,
    subtle: Brand.darkSubtle,
    subtleHover: Brand.darkSubtleHover,
    subtleText: Brand.darkHeading,
    icon: Brand.darkBody,
    isDark: true,
  );

  static const light = BrandSurfaces(
    cardDecoration: BoxDecoration(
      color: Brand.lightCard,
      borderRadius: BorderRadius.all(Radius.circular(Brand.radiusCard)),
      border: Border.fromBorderSide(BorderSide(color: Brand.lightBorder)),
    ),
    cardFill: Brand.lightCard,
    border: Brand.lightBorder,
    heading: Brand.lightHeading,
    body: Brand.lightBody,
    subtle: Brand.lightSubtle,
    subtleHover: Brand.lightSubtleHover,
    subtleText: Brand.lightHeading,
    icon: Brand.neverBlue,
    isDark: false,
  );

  @override
  BrandSurfaces copyWith() => this;

  @override
  BrandSurfaces lerp(BrandSurfaces? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

extension BrandContext on BuildContext {
  BrandSurfaces get brand =>
      Theme.of(this).extension<BrandSurfaces>() ?? BrandSurfaces.dark;
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final s = dark ? BrandSurfaces.dark : BrandSurfaces.light;
  final page = dark ? Brand.darkPage : Brand.lightPage;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: Brand.primary,
    onPrimary: Colors.white,
    secondary: Brand.continuousBlue,
    onSecondary: Colors.white,
    tertiary: Brand.swwYellow,
    onTertiary: Brand.darkPage,
    error: Brand.red,
    onError: Colors.white,
    surface: page,
    onSurface: s.heading,
    onSurfaceVariant: s.body,
    surfaceContainerLowest: page,
    surfaceContainerLow: s.cardFill,
    surfaceContainer: s.cardFill,
    surfaceContainerHigh: s.subtle,
    surfaceContainerHighest: s.subtle,
    outline: s.border,
    outlineVariant: s.border,
    primaryContainer: Brand.neverBlue,
    onPrimaryContainer: Colors.white,
    secondaryContainer: s.subtle,
    onSecondaryContainer: s.heading,
  );

  TextStyle h(double size) => TextStyle(
    fontFamily: Brand.fontFamily,
    fontSize: size,
    fontWeight: FontWeight.w700,
    height: 1.26,
    letterSpacing: -0.2,
    color: s.heading,
  );
  TextStyle b(double size) => TextStyle(
    fontFamily: Brand.fontFamily,
    fontSize: size,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: -0.2,
    color: s.body,
  );
  final action = TextStyle(
    fontFamily: Brand.fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.26,
    letterSpacing: -0.2,
    color: s.heading,
  );

  final textTheme = TextTheme(
    displayLarge: h(28),
    displayMedium: h(28),
    displaySmall: h(28),
    headlineLarge: h(28), // h1
    headlineMedium: h(26), // h2
    headlineSmall: h(22), // h3
    titleLarge: h(20), // h4
    titleMedium: h(18), // h5 card titles
    titleSmall: h(16), // h6
    bodyLarge: b(16),
    bodyMedium: b(14),
    bodySmall: b(12),
    labelLarge: action,
    labelMedium: action.copyWith(fontSize: 12),
    labelSmall: action.copyWith(fontSize: 12),
  );

  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Brand.radiusButton),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: Brand.fontFamily,
    textTheme: textTheme,
    scaffoldBackgroundColor: page,
    canvasColor: page,
    dividerColor: s.border,
    extensions: [s],
    iconTheme: IconThemeData(color: s.icon),
    appBarTheme: AppBarTheme(
      backgroundColor: page,
      surfaceTintColor: Colors.transparent,
      foregroundColor: s.heading,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: h(18),
      iconTheme: IconThemeData(color: s.icon),
      actionsIconTheme: IconThemeData(color: s.icon),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? Brand.darkCardBottom : Brand.lightCard,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Brand.neverBlue,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => action.copyWith(
          fontSize: 12,
          color: states.contains(WidgetState.selected) ? s.heading : s.body,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? Colors.white : s.icon,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, Brand.buttonHeight)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 20),
        ),
        shape: WidgetStatePropertyAll(buttonShape),
        textStyle: WidgetStatePropertyAll(action),
        elevation: const WidgetStatePropertyAll(0),
        foregroundColor: const WidgetStatePropertyAll(Colors.white),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.pressed) ||
                  states.contains(WidgetState.hovered)
              ? Brand.primaryPressed
              : Brand.primary,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(buttonShape),
        textStyle: WidgetStatePropertyAll(action),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered) && dark
              ? Brand.swwYellow
              : (dark ? Brand.dashAqua : Brand.neverBlue),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: s.subtle,
      selectedColor: Brand.neverBlue,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: action.copyWith(fontSize: 13, color: s.heading),
      secondaryLabelStyle: action.copyWith(fontSize: 13, color: Colors.white),
      checkmarkColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: s.subtle,
      hintStyle: b(14),
      prefixIconColor: s.icon,
      suffixIconColor: s.icon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Brand.radiusMd),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Brand.radiusMd),
        borderSide: const BorderSide(color: Brand.neverBlue, width: 1.5),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelStyle: action,
      unselectedLabelStyle: action,
      labelColor: s.heading,
      unselectedLabelColor: s.body,
      indicatorColor: Brand.neverBlue,
      dividerColor: s.border,
      indicatorSize: TabBarIndicatorSize.label,
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? Brand.primary : s.subtle,
      ),
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? Brand.darkCardBottom : Brand.lightPage,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: s.body,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(Brand.radiusCard),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? Brand.darkCardBottom : Brand.lightPage,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Brand.radiusCard),
      ),
      titleTextStyle: h(20),
      contentTextStyle: b(14),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: dark ? Brand.darkSubtle : Brand.lightPage,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Brand.radiusMd),
      ),
      textStyle: action.copyWith(color: s.heading),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? Brand.darkSubtle : Brand.lightHeading,
      contentTextStyle: b(14).copyWith(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Brand.radiusMd),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: s.icon,
      titleTextStyle: action.copyWith(fontSize: 16),
      subtitleTextStyle: b(14),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: const WidgetStatePropertyAll(BorderSide.none),
        backgroundColor: WidgetStateProperty.resolveWith(
          (st) =>
              st.contains(WidgetState.selected) ? Brand.neverBlue : s.subtle,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? Colors.white : s.heading,
        ),
        textStyle: WidgetStatePropertyAll(action),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Brand.neverBlue,
    ),
  );
}
