import 'package:flutter/material.dart';

/// Envuelve una pantalla que puede llegar a ser la raíz de la navegación
/// (sin nada debajo a lo que volver dentro de la app -- ej. DetalleNegocio,
/// NegociosScreen, ContadoresScreen o DespachosScreen justo después del
/// login) para que, cuando de verdad sea la raíz, la flecha/gesto de volver
/// -- o el botón "atrás" del navegador en Flutter Web -- no se propague
/// fuera de la aplicación.
///
/// Sin esto, en la raíz `Navigator.maybePop()` no tiene nada que hacer y el
/// framework deja pasar la navegación de vuelta al navegador real, que sale
/// de la SPA (a la página anterior, o a una pantalla en blanco) -- eso se
/// sentía como "se sale del sistema" con uno o dos toques de la flecha de
/// volver desde cualquier pantalla interna (ej. Inventario), sin haber
/// cerrado sesión realmente. Cuando esta MISMA pantalla se abre empujada
/// sobre otra (ej. DetalleNegocio desde Resumen Fiscal), `Navigator.canPop`
/// es true y este widget no interviene: el volver normal sigue funcionando.
class BloqueoSalidaRaiz extends StatelessWidget {
  final Widget child;
  const BloqueoSalidaRaiz({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final bool esRaiz = !Navigator.canPop(context);
    return PopScope(
      canPop: !esRaiz,
      child: child,
    );
  }
}
