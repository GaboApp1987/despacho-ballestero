import 'package:flutter/material.dart';

import 'soporte_chat.dart';

/// Qué asistente abre el botón flotante: lo registra el panel que está
/// abierto (el del contador, o el del negocio en el que se está trabajando)
/// con sus secciones y su función de abrir el asistente en pantalla
/// completa (mismo saludo y sugerencias que su barra del dashboard).
class ConfigAsistente {
  final int? negocioId;
  final Map<String, String> secciones;
  final void Function(String clave) onNavegar;
  final VoidCallback abrirPantallaCompleta;
  const ConfigAsistente({
    this.negocioId,
    required this.secciones,
    required this.onNavegar,
    required this.abrirPantallaCompleta,
  });
}

/// Estrellitas flotantes (tipo ChatGPT) sobre TODAS las pantallas una vez
/// iniciada la sesión: abren un mini chat del asistente en la esquina, que
/// se minimiza de vuelta a las estrellitas sin perder la conversación (o se
/// abre en pantalla completa). Las estrellitas se pueden arrastrar si
/// tapan algo. Va en MaterialApp.builder (ver main.dart).
class AsistenteFlotante extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  const AsistenteFlotante({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  // Pila de configuraciones: el contador registra la suya y, si entra a un
  // negocio, ese negocio pone la propia encima; al salir vuelve la anterior.
  static final ValueNotifier<List<ConfigAsistente>> _pila = ValueNotifier([]);
  // Mientras el asistente en pantalla completa está abierto, nada de esto
  // se muestra.
  static final ValueNotifier<bool> abierto = ValueNotifier(false);

  static void registrar(ConfigAsistente config) =>
      _pila.value = [..._pila.value, config];

  static void quitar(ConfigAsistente config) =>
      _pila.value = [..._pila.value]..remove(config);

  static void limpiar() => _pila.value = [];

  @override
  State<AsistenteFlotante> createState() => _AsistenteFlotanteState();
}

class _AsistenteFlotanteState extends State<AsistenteFlotante> {
  // Distancia de las estrellitas a la esquina inferior derecha.
  Offset _margen = const Offset(18, 92);
  // Mini chat visible (si no, minimizado en las estrellitas).
  bool _chatAbierto = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        ValueListenableBuilder<List<ConfigAsistente>>(
          valueListenable: AsistenteFlotante._pila,
          builder: (context, pila, _) => ValueListenableBuilder<bool>(
            valueListenable: AsistenteFlotante.abierto,
            builder: (context, pantallaCompleta, _) {
              if (pila.isEmpty) {
                _chatAbierto = false;
                return const SizedBox.shrink();
              }
              final config = pila.last;
              final mq = MediaQuery.of(context);
              final tamano = mq.size;
              final teclado = mq.viewInsets.bottom;
              final movil = tamano.width < 600;
              final anchoChat = movil ? tamano.width - 16 : 390.0;
              final double altoChat = movil
                  ? (tamano.height - teclado - 80)
                        .clamp(320.0, 720.0)
                        .toDouble()
                  : (tamano.height - 120).clamp(360.0, 600.0).toDouble();
              final verBoton =
                  !pantallaCompleta && !_chatAbierto && teclado == 0;
              return Stack(
                children: [
                  // El mini chat queda vivo aunque esté minimizado (Offstage),
                  // así la conversación sigue ahí al volver a abrirlo. Uno por
                  // negocio/panel (la clave cambia al entrar a otro negocio).
                  Positioned(
                    right: movil ? 8 : 18,
                    bottom: (movil ? 8 : 18) + teclado,
                    width: anchoChat,
                    height: altoChat,
                    child: Offstage(
                      offstage: !_chatAbierto || pantallaCompleta,
                      child: TickerMode(
                        enabled: _chatAbierto && !pantallaCompleta,
                        child: _VentanaChat(
                          key: ObjectKey(config),
                          config: config,
                          onMinimizar: () =>
                              setState(() => _chatAbierto = false),
                          onMaximizar: () {
                            setState(() => _chatAbierto = false);
                            config.abrirPantallaCompleta();
                          },
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: _margen.dx,
                    bottom: _margen.dy,
                    child: IgnorePointer(
                      ignoring: !verBoton,
                      child: AnimatedScale(
                        scale: verBoton ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutBack,
                        child: GestureDetector(
                          onPanUpdate: (d) => setState(() {
                            _margen = Offset(
                              (_margen.dx - d.delta.dx).clamp(
                                8.0,
                                tamano.width - 60,
                              ),
                              (_margen.dy - d.delta.dy).clamp(
                                8.0,
                                tamano.height - 60,
                              ),
                            );
                          }),
                          child: _BotonAsistente(
                            onTap: () => setState(() => _chatAbierto = true),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// La ventanita: un Navigator propio para que los diálogos del chat
/// (confirmaciones, "dejar mensaje"...) tengan dónde abrirse, ya que todo
/// esto vive por encima del Navigator de la app.
class _VentanaChat extends StatelessWidget {
  final ConfigAsistente config;
  final VoidCallback onMinimizar;
  final VoidCallback onMaximizar;
  const _VentanaChat({
    super.key,
    required this.config,
    required this.onMinimizar,
    required this.onMaximizar,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        // HeroControllerScope.none: el Navigator de la app ya tiene el suyo
        // y no se puede compartir.
        child: HeroControllerScope.none(
          child: Navigator(
            onGenerateRoute: (_) => PageRouteBuilder(
              pageBuilder: (_, __, ___) => Material(
                type: MaterialType.transparency,
                child: MiniChatAsistente(
                  negocioId: config.negocioId,
                  secciones: config.secciones,
                  onNavegar: config.onNavegar,
                  onMinimizar: onMinimizar,
                  onMaximizar: onMaximizar,
                ),
              ),
            ),
          ),
        ),
      ),
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
                  color: const Color(
                    0xFF6366F1,
                  ).withValues(alpha: _encima ? 0.55 : 0.35),
                  blurRadius: _encima ? 18 : 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: AnimatedScale(
              scale: _encima ? 1.08 : 1,
              duration: const Duration(milliseconds: 160),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 23,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
