import 'package:flutter/material.dart';

/// Respaldo para plataformas sin dart:html (móvil/escritorio nativo). El
/// cobro automático con tarjeta hoy solo funciona en la versión web.
class OnvoIframeView extends StatelessWidget {
  final Uri url;
  final void Function(String mensaje) onMensaje;

  const OnvoIframeView({super.key, required this.url, required this.onMensaje});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          "El cobro automático con tarjeta solo está disponible desde la versión web de Equilibra por ahora.",
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
