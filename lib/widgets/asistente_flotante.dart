import 'package:flutter/material.dart';

/// Qué asistente abre el botón flotante: lo registra el panel que está
/// abierto (el del contador, o el del negocio en el que se está trabajando)
/// con su propia función de abrir el asistente (mismo saludo, secciones y
/// sugerencias que su barra del dashboard).
class ConfigAsistente {
  final VoidCallback abrir;
  const ConfigAsistente(this.abrir);
}

/// Botón redondo chico (tipo ChatGPT) que queda sobre TODAS las pantallas
/// una vez iniciada la sesión, para pedirle algo al asistente sin volver
/// al dashboard. Se puede arrastrar si tapa algo. Va en MaterialApp.builder
/// (ver main.dart).
class AsistenteFlotante extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  const AsistenteFlotante({super.key, required this.child, required this.navigatorKey});

  // Pila de configuraciones: el contador registra la suya y, si entra a un
  // negocio, ese negocio pone la propia encima; al salir vuelve la anterior.
  static final ValueNotifier<List<ConfigAsistente>> _pila = ValueNotifier([]);
  // Mientras el asistente está abierto el botón no se muestra.
  static final ValueNotifier<bool> abierto = ValueNotifier(false);

  static void registrar(ConfigAsistente config) => _pila.value = [..._pila.value, config];

  static void quitar(ConfigAsistente config) => _pila.value = [..._pila.value]..remove(config);

  static void limpiar() => _pila.value = [];

  @override
  State<AsistenteFlotante> createState() => _AsistenteFlotanteState();
}

class _AsistenteFlotanteState extends State<AsistenteFlotante> {
  // Distancia desde la esquina inferior derecha (se mueve al arrastrar).
  Offset _margen = const Offset(18, 92);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        ValueListenableBuilder<List<ConfigAsistente>>(
          valueListenable: AsistenteFlotante._pila,
          builder: (context, pila, _) => ValueListenableBuilder<bool>(
            valueListenable: AsistenteFlotante.abierto,
            builder: (context, abierto, _) {
              final visible = pila.isNotEmpty && !abierto && MediaQuery.viewInsetsOf(context).bottom == 0;
              final tamano = MediaQuery.sizeOf(context);
              return Positioned(
                right: _margen.dx,
                bottom: _margen.dy,
                child: IgnorePointer(
                  ignoring: !visible,
                  child: AnimatedScale(
                    scale: visible ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    child: GestureDetector(
                      onPanUpdate: (d) => setState(() {
                        _margen = Offset(
                          (_margen.dx - d.delta.dx).clamp(8.0, tamano.width - 60),
                          (_margen.dy - d.delta.dy).clamp(8.0, tamano.height - 60),
                        );
                      }),
                      child: pila.isEmpty ? const SizedBox.shrink() : _BotonAsistente(onTap: pila.last.abrir),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BotonAsistente extends StatefulWidget {
  final VoidCallback onTap;
  const _BotonAsistente({required this.onTap});

  @override
  State<_BotonAsistente> createState() => _BotonAsistenteState();
}

class _BotonAsistenteState extends State<_BotonAsistente> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    // Sin Tooltip: este botón vive arriba del Navigator (no hay Overlay).
    return Semantics(
      button: true,
      label: 'Asistente Equilibra',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _encima = true),
        onExit: (_) => setState(() => _encima = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF22D3EE)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withValues(alpha: _encima ? 0.55 : 0.35),
                  blurRadius: _encima ? 18 : 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: AnimatedScale(
              scale: _encima ? 1.08 : 1,
              duration: const Duration(milliseconds: 160),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 23),
            ),
          ),
        ),
      ),
    );
  }
}
