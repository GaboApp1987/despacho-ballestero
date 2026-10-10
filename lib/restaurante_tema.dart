import 'package:flutter/material.dart';

/// Colores del modo restaurante: un terracota cálido para que se note que
/// se está en el módulo de restaurante (el resto de Equilibra sigue en azul)
/// y violeta para lo que pide atención del mesero (llama, pide la cuenta,
/// pidió desde el QR), que así no se confunde con el ámbar de la cocina.
const colorResto = Color(0xFFEA580C);
const colorRestoOscuro = Color(0xFFC2410C);
const colorLlamado = Color(0xFF8B5CF6);

/// El tema de la app con el terracota como color principal: botones,
/// pestañas, interruptores y barra superior de las pantallas del módulo.
ThemeData temaResto(BuildContext context) {
  final base = Theme.of(context);
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: colorResto,
      onPrimary: Colors.white,
      secondary: colorResto,
      onSecondary: Colors.white,
      primaryContainer: colorResto.withValues(alpha: 0.18),
      onPrimaryContainer: colorRestoOscuro,
      secondaryContainer: colorResto.withValues(alpha: 0.18),
      onSecondaryContainer: base.brightness == Brightness.dark ? Colors.white : colorRestoOscuro,
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: colorResto,
      foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white),
      actionsIconTheme: const IconThemeData(color: Colors.white),
      titleTextStyle: (base.appBarTheme.titleTextStyle ?? base.textTheme.titleLarge ?? const TextStyle())
          .copyWith(color: Colors.white, fontWeight: FontWeight.w700),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: colorResto),
  );
}

/// Envuelve una pantalla del módulo con el tema de restaurante.
class ConTemaResto extends StatelessWidget {
  final Widget child;
  const ConTemaResto({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Theme(data: temaResto(context), child: child);
}
