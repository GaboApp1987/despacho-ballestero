import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colores semánticos (éxito/advertencia/información) que ColorScheme no
/// trae de fábrica. Se exponen como ThemeExtension para que puedan cambiar
/// junto con el resto del tema al alternar claro/oscuro.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  final Color success;
  final Color onSuccess;
  final Color warning;
  final Color onWarning;
  final Color info;
  final Color onInfo;

  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.info,
    required this.onInfo,
  });

  static const light = AppSemanticColors(
    success: Color(0xFF15803D),
    onSuccess: Colors.white,
    warning: Color(0xFFB45309),
    onWarning: Colors.white,
    info: Color(0xFF0369A1),
    onInfo: Colors.white,
  );

  static const dark = AppSemanticColors(
    success: Color(0xFF0E7490),
    onSuccess: Colors.white,
    warning: Color(0xFFF59E0B),
    onWarning: Colors.black,
    info: Color(0xFF38BDF8),
    onInfo: Colors.black,
  );

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? onWarning,
    Color? info,
    Color? onInfo,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
    );
  }
}

extension AppSemanticColorsX on BuildContext {
  AppSemanticColors get semanticColors =>
      Theme.of(this).extension<AppSemanticColors>() ?? AppSemanticColors.dark;
}

/// Transición compartida por toda la app al navegar entre pantallas: fundido
/// + leve deslizamiento hacia arriba. Reemplaza el "slide desde la derecha"
/// por defecto de Android y el corte seco de escritorio/web, sin tener que
/// tocar cada Navigator.push (MaterialPageRoute ya lee esto del Theme).
class _FadeThroughPageTransitionsBuilder extends PageTransitionsBuilder {
  const _FadeThroughPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  }
}

class _Paleta {
  final Color primary;
  final Color primaryDark;
  final Color background;
  final Color surface;
  final Color surfaceSubtle;
  final Color border;
  final Color textMuted;
  final Color textStrong;

  const _Paleta({
    required this.primary,
    required this.primaryDark,
    required this.background,
    required this.surface,
    required this.surfaceSubtle,
    required this.border,
    required this.textMuted,
    required this.textStrong,
  });
}

// Mismo acento cian/turquesa en claro y oscuro (así lo usa el diseño de
// referencia: el color de marca no cambia entre modos, solo el fondo).
const Color _acento = Color(0xFF22D3EE);
const Color _acentoOscuro = Color(0xFF0E7490);

const _paletaOscura = _Paleta(
  primary: _acento,
  primaryDark: _acentoOscuro,
  background: Color(0xFF0B1120),
  surface: Color(0xFF141B2D),
  surfaceSubtle: Color(0xFF1B2338),
  border: Color(0xFF26314A),
  textMuted: Color(0xFF8B98B8),
  textStrong: Color(0xFFF1F5F9),
);

const _paletaClara = _Paleta(
  primary: _acento,
  primaryDark: _acentoOscuro,
  background: Color(0xFFEEF1FA),
  surface: Color(0xFFFFFFFF),
  surfaceSubtle: Color(0xFFF3F5FC),
  border: Color(0xFFE1E5F5),
  textMuted: Color(0xFF64748B),
  textStrong: Color(0xFF0F172A),
);

/// Paleta azul marino + acento cian (diseño de referencia del negocio, con
/// version clara y oscura del mismo esquema). A diferencia de una paleta
/// fija, estos valores son mutables: ThemeController.toggle() los reasigna
/// via AppColors.setDark(), y como TODAS las pantallas ya leen los colores
/// de AppColors.xxx (no colores sueltos), cambiar estos 8 valores basta para
/// que toda la app cambie de modo en el proximo build -- ver
/// theme/theme_controller.dart, que es quien dispara ese rebuild.
class AppColors {
  static bool isDark = true;

  static Color primary = _paletaOscura.primary;
  static Color primaryDark = _paletaOscura.primaryDark;
  static Color background = _paletaOscura.background;
  static Color surface = _paletaOscura.surface;
  static Color surfaceSubtle = _paletaOscura.surfaceSubtle;
  static Color border = _paletaOscura.border;
  static Color textMuted = _paletaOscura.textMuted;
  static Color textStrong = _paletaOscura.textStrong;

  static void setDark(bool dark) {
    isDark = dark;
    final p = dark ? _paletaOscura : _paletaClara;
    primary = p.primary;
    primaryDark = p.primaryDark;
    background = p.background;
    surface = p.surface;
    surfaceSubtle = p.surfaceSubtle;
    border = p.border;
    textMuted = p.textMuted;
    textStrong = p.textStrong;
  }
}

class AppTheme {
  /// Construye el ThemeData para el modo actual de AppColors -- llamar
  /// AppColors.setDark(...) ANTES de esto para que quede consistente.
  static ThemeData _build({required bool dark}) {
    final base = ThemeData(useMaterial3: true, brightness: dark ? Brightness.dark : Brightness.light);
    final textTheme = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
      bodyColor: AppColors.textStrong,
      displayColor: AppColors.textStrong,
    ).copyWith(
      headlineMedium: GoogleFonts.plusJakartaSans(
        fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.textStrong),
      titleLarge: GoogleFonts.plusJakartaSans(
        fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textStrong),
      titleMedium: GoogleFonts.plusJakartaSans(
        fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textStrong),
      bodyMedium: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppColors.textStrong),
      bodySmall: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textMuted),
      labelLarge: GoogleFonts.plusJakartaSans(
        fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.3),
    );

    // El acento cian es lo bastante claro para que el texto negro tenga
    // buen contraste encima en los dos modos -- por eso los botones usan
    // onPrimary/foregroundColor negro tanto en claro como en oscuro.
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      dividerColor: AppColors.border,
      textTheme: textTheme,
      colorScheme: ColorScheme(
        brightness: dark ? Brightness.dark : Brightness.light,
        primary: AppColors.primary,
        secondary: AppColors.primaryDark,
        surface: AppColors.surface,
        onPrimary: Colors.black,
        onSecondary: Colors.white,
        onSurface: AppColors.textStrong,
        error: dark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
        onError: dark ? Colors.black : Colors.white,
      ),
      extensions: [dark ? AppSemanticColors.dark : AppSemanticColors.light],
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _FadeThroughPageTransitionsBuilder(),
          TargetPlatform.iOS: _FadeThroughPageTransitionsBuilder(),
          TargetPlatform.macOS: _FadeThroughPageTransitionsBuilder(),
          TargetPlatform.windows: _FadeThroughPageTransitionsBuilder(),
          TargetPlatform.linux: _FadeThroughPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.textStrong),
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.textStrong),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
        labelStyle: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w500),
        hintStyle: TextStyle(color: AppColors.textMuted.withOpacity(0.7)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.4),
          animationDuration: const Duration(milliseconds: 180),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return Colors.black.withOpacity(0.12);
            if (states.contains(WidgetState.hovered)) return Colors.black.withOpacity(0.06);
            return null;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
      ),
      iconTheme: IconThemeData(color: AppColors.textMuted),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.black,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.border),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceSubtle,
        labelStyle: TextStyle(color: AppColors.textStrong),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      listTileTheme: ListTileThemeData(iconColor: AppColors.textMuted),
      dividerTheme: DividerThemeData(color: AppColors.border, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceSubtle,
        contentTextStyle: TextStyle(color: AppColors.textStrong),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static ThemeData get dark {
    AppColors.setDark(true);
    return _build(dark: true);
  }

  static ThemeData get light {
    AppColors.setDark(false);
    return _build(dark: false);
  }
}
