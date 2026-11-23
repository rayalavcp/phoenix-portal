import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Phoenix Portal visual identity: ember and gold on deep ink, light + dark.
/// The remote admin UI's CSS carries the same values (remote-ui/static/app.css).
///
///   ember       #F26A1B  primary (the mark's flame core)
///   gold        #F5A623  secondary accent (the flame tip)
///   iris        #8C9BFF  tertiary, a cool counterweight to the warm brand
///   mint        #3CCB8C  success
///   rose        #FF6B6B  error / danger
///   light bg    #F7F5F2  warm paper
///   dark bg     #0F1115  deep ink
///
/// Dark is the kiosk's home: exact palette values sit on it with comfortable
/// contrast. On the light background each accent is deepened just enough to
/// stay legible as text: same hue, deeper tone.
// Calmer since 2026.12.19: the same warm hues, a step softer, so no
// screen shouts.
const _ember = Color(0xFFDB7B4E);
const _emberOnLight = Color(0xFFB4572E);

/// Brand constants other screens reach for directly.
abstract final class Phx {
  static const ember = _ember;
  static const emberOnLight = _emberOnLight;
  static const gold = Color(0xFFE3B261);
  static const iris = Color(0xFF9AA5E8);
  static const mint = Color(0xFF5DBE96);
  static const rose = Color(0xFFE88A86);

  /// The flame: the logo's gradient, used for hero accents and primary fills
  /// that should glow rather than sit flat.
  static const flame = LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: [Color(0xFFB8502F), Color(0xFFDB7B4E), Color(0xFFE3B261)],
    stops: [0, 0.55, 1],
  );

  /// Category badge gradients for the settings rail and tiles, in rail
  /// order. Each pair runs deep to bright so a white glyph reads on both ends.
  static const badges = <List<Color>>[
    [Color(0xFFB4553A), Color(0xFFD98C5E)], // ember
    [Color(0xFFC99545), Color(0xFFE3BC74)], // gold
    [Color(0xFF6573C9), Color(0xFF9AA5E8)], // iris
    [Color(0xFF3A9874), Color(0xFF74C4A0)], // mint
    [Color(0xFFC2617A), Color(0xFFE39AAA)], // rose
    [Color(0xFF3F86B8), Color(0xFF7DB6DD)], // sky
  ];
}

/// The brand green for success states (kept under its old name for callers).
const ksSage = Phx.mint;
const ksSageOnLight = Color(0xFF128A5A);
const _lightBg = Color(0xFFF7F5F2);
const _darkBg = Color(0xFF0F1115);

/// The shared spacing and shape scale. Every screen draws from these instead
/// of inventing its own values; if a number is not on this scale it should
/// not appear in layout code.
abstract final class Ks {
  /// Outer padding of every settings/content page.
  static const pagePadding = EdgeInsets.fromLTRB(20, 16, 20, 24);

  /// The one left inset shared by everything that sits in a card column:
  /// section headings, row content, dividers, hint rows, group notes.
  static const double inset = 20;

  /// Vertical gap between a card and the next section heading.
  static const double cardGap = 16;

  /// Cards, dialogs and other primary surfaces.
  static const double radiusCard = 26;

  /// Row ink splashes and small tappable surfaces inside a card.
  static const double radiusRow = 16;

  /// Text fields and other input controls.
  static const double radiusControl = 14;

  /// The one typeface for every piece of app text: page titles, dialog
  /// titles, list rows, buttons, body copy and the clock faces alike. Inter's
  /// variable cut (wght + opsz) is bundled in the APK, so it renders the same
  /// on every device and stays crisp at tablet sizes.
  static const String displayFont = 'Inter';

  /// Motion: one duration and curve pair for every transition the app draws
  /// itself, so pages, sheets and fades feel like one system.
  static const Duration motion = Duration(milliseconds: 320);
  static const Curve motionIn = Curves.easeOutCubic;
  static const Curve motionOut = Curves.easeInCubic;

  /// Height of the fade-out an [EdgeFade] paints over a scroll edge that
  /// still hides content. The remote admin's --fade-size matches.
  static const double fadeEdge = 28;
}

/// The ground of a full screen overlay (the app launcher, the intercom):
/// the theme surface as an unmistakable vertical gradient, lit at the top
/// and settling deeper below, in both themes. The light theme pins its
/// own endpoints instead of offsetting the surface: the paper tone sits
/// so close to white that a relative lift clamps flat and the screen read
/// as a plain sheet.
LinearGradient ksGroundGradient(Color surface, Brightness brightness) {
  final hsl = HSLColor.fromColor(surface);
  final dark = brightness == Brightness.dark;
  HSLColor tone(double lightness) =>
      hsl.withLightness(lightness.clamp(0.0, 1.0));
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: dark
        ? [
            tone(hsl.lightness + 0.08).toColor(),
            tone(hsl.lightness - 0.06).toColor(),
          ]
        : [tone(0.99).toColor(), tone(0.78).toColor()],
  );
}

ColorScheme _lightScheme() =>
    ColorScheme.fromSeed(
      seedColor: _ember,
      brightness: Brightness.light,
    ).copyWith(
      primary: _emberOnLight, // deepened so it carries text on paper
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFFFE1D6),
      onPrimaryContainer: const Color(0xFF4A1405),
      secondary: const Color(0xFFA8660A), // gold, deepened
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFFFE9C7),
      onSecondaryContainer: const Color(0xFF3A2200),
      tertiary: const Color(0xFF4757D6), // iris, deepened
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFE1E5FF),
      onTertiaryContainer: const Color(0xFF141C5C),
      error: const Color(0xFFC2362F),
      onError: Colors.white,
      errorContainer: const Color(0xFFFFDAD6),
      onErrorContainer: const Color(0xFF410002),
      surface: _lightBg,
      onSurface: const Color(0xFF1B1D22),
      onSurfaceVariant: const Color(0xFF5B606B),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFFCFBF9),
      surfaceContainer: Colors.white,
      surfaceContainerHigh: const Color(0xFFF1EEEA),
      surfaceContainerHighest: const Color(0xFFE9E5E0),
      outline: const Color(0xFFC9C5BE),
      outlineVariant: const Color(0xFFE9E5DF),
    );

ColorScheme _darkScheme() =>
    ColorScheme.fromSeed(
      seedColor: _ember,
      brightness: Brightness.dark,
    ).copyWith(
      primary: _ember, // exact brand values carry the dark theme
      onPrimary: const Color(0xFF2A0A00),
      primaryContainer: const Color(0xFF4A1E10),
      onPrimaryContainer: const Color(0xFFFFDBCF),
      secondary: Phx.gold,
      onSecondary: const Color(0xFF2B1A00),
      secondaryContainer: const Color(0xFF4A3510),
      onSecondaryContainer: const Color(0xFFFFE3B5),
      tertiary: Phx.iris,
      onTertiary: const Color(0xFF0E1550),
      tertiaryContainer: const Color(0xFF283066),
      onTertiaryContainer: const Color(0xFFDDE1FF),
      error: Phx.rose,
      onError: const Color(0xFF3A0606),
      errorContainer: const Color(0xFF5C1A1A),
      onErrorContainer: const Color(0xFFFFDAD6),
      surface: _darkBg,
      onSurface: const Color(0xFFECEEF2),
      onSurfaceVariant: const Color(0xFFA3A9B6),
      surfaceContainerLowest: const Color(0xFF0B0D10),
      surfaceContainerLow: const Color(0xFF14171C),
      surfaceContainer: const Color(0xFF181B21),
      surfaceContainerHigh: const Color(0xFF20242C),
      surfaceContainerHighest: const Color(0xFF282D37),
      outline: const Color(0xFF3E4552),
      outlineVariant: const Color(0xFF262B34),
    );

/// The page transition every pushed route uses: the incoming page fades in
/// while drifting a few percent from the right and settling from a hair above
/// full scale; the page underneath dims back slightly. Opacity and transform
/// only, so it stays on the GPU's cheap path even on a 2018 Portal.
class PhoenixPageTransitionsBuilder extends PageTransitionsBuilder {
  const PhoenixPageTransitionsBuilder();

  @override
  Duration get transitionDuration => Ks.motion;

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 260);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final enter = CurvedAnimation(
      parent: animation,
      curve: Ks.motionIn,
      reverseCurve: Ks.motionOut,
    );
    final under = CurvedAnimation(parent: secondaryAnimation, curve: Ks.motionIn);
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.92).animate(under),
      child: FadeTransition(
        opacity: enter,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.04, 0),
            end: Offset.zero,
          ).animate(enter),
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.015, end: 1).animate(enter),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// [barsShown] is true while a Hide status bar or Hide navigation bar setting
/// keeps a system bar up (see applySystemBars in main.dart).
ThemeData buildTheme(Brightness brightness, {bool barsShown = false}) {
  final dark = brightness == Brightness.dark;
  final scheme = dark ? _darkScheme() : _lightScheme();
  // Pill-shaped, compact One UI buttons. Filled carries the affirmative
  // action, text the quiet one; both share the same metrics so dialog action
  // rows line up.
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(100),
  );
  const buttonPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 12);
  const buttonText = TextStyle(
    fontFamily: Ks.displayFont,
    fontSize: 14.5,
    fontWeight: FontWeight.w600,
  );
  // A shared floor keeps dialog action pairs balanced: "Save" never renders
  // visibly narrower than the "Cancel" beside it.
  const buttonMinSize = Size(96, 44);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    // Smooth on old GPUs: the classic ripple instead of Material 3's shader
    // sparkle, and one transition for every platform.
    splashFactory: InkRipple.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PhoenixPageTransitionsBuilder(),
        TargetPlatform.iOS: PhoenixPageTransitionsBuilder(),
        TargetPlatform.linux: PhoenixPageTransitionsBuilder(),
        TargetPlatform.macOS: PhoenixPageTransitionsBuilder(),
        TargetPlatform.windows: PhoenixPageTransitionsBuilder(),
        TargetPlatform.fuchsia: PhoenixPageTransitionsBuilder(),
      },
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: dark ? scheme.surfaceContainerHighest : const Color(0xFF1B1D22),
      contentTextStyle: TextStyle(
        fontFamily: Ks.displayFont,
        fontSize: 14.5,
        color: dark ? scheme.onSurface : Colors.white,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Ks.radiusRow),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
      circularTrackColor: Colors.transparent,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? scheme.onPrimary : scheme.outline,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.surfaceContainerHighest,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.transparent : scheme.outline,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: dark ? scheme.surfaceContainerHighest : const Color(0xFF1B1D22),
        borderRadius: BorderRadius.circular(10),
      ),
      textStyle: TextStyle(
        fontFamily: Ks.displayFont,
        fontSize: 13,
        color: dark ? scheme.onSurface : Colors.white,
      ),
    ),
    // Every text theme style inherits Rubik. Theme-level TextStyles below
    // that replace the text theme rather than merge with it (list rows,
    // buttons) name the family explicitly so nothing falls back to Roboto.
    fontFamily: Ks.displayFont,
    scaffoldBackgroundColor: scheme.surface,
    // Flat: nothing floats, nothing tints on scroll. Depth comes from surface
    // tone and hairline outlines, not shadows.
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      // Light bar icons in both themes while the bars are up: they sit over
      // the black window background, not over the app bar, and a light
      // theme's dark icons would vanish there.
      systemOverlayStyle: barsShown ? SystemUiOverlayStyle.light : null,
      // The title sits right after the back arrow, as it does in the wide
      // settings pane, instead of Material's 16 further along: every bar
      // here is a pushed page with a leading arrow, and on a phone the
      // default gap read as a hole between the arrow and the page glyph.
      titleSpacing: 0,
      // One UI-weight headers: bold titles carry the hierarchy.
      titleTextStyle: TextStyle(
        fontFamily: Ks.displayFont,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: scheme.onSurface,
      ),
    ),
    // Borderless rounded section masks, One UI style: cards read as soft
    // panels lifted from the background by tone alone.
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainer,
      margin: const EdgeInsets.only(bottom: Ks.cardGap),
      // A hairline edge on dark lifts the panel off the ink without a shadow.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Ks.radiusCard),
        side: dark
            ? BorderSide(color: scheme.outlineVariant)
            : BorderSide.none,
      ),
    ),
    dialogTheme: DialogThemeData(
      elevation: 0,
      backgroundColor: dark ? scheme.surfaceContainerHigh : scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Ks.radiusCard + 2),
      ),
      titleTextStyle: TextStyle(
        fontFamily: Ks.displayFont,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    // One UI list rhythm: taller rows, a readable medium-weight title over a
    // clearly quieter subtitle. The weight gap is what makes rows scannable.
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Ks.inset,
        vertical: 4,
      ),
      titleTextStyle: TextStyle(
        fontFamily: Ks.displayFont,
        fontSize: 17,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: scheme.onSurface,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: Ks.displayFont,
        fontSize: 13,
        height: 1.35,
        color: scheme.onSurfaceVariant,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? scheme.surfaceContainerHigh : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Ks.radiusControl),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Ks.radiusControl),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Ks.radiusControl),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        minimumSize: buttonMinSize,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: buttonMinSize,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: buttonMinSize,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: buttonText,
        side: BorderSide(color: scheme.outline),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    ),
  );
}
