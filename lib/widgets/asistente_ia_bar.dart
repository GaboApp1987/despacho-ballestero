import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'soporte_chat.dart';

/// Acceso al asistente de IA ("Equilibra") desde el dashboard de cada
/// perfil (negocio, contador, despacho y administrador).
///
/// El asistente es su propia pantalla, estilo Claude/Gemini (ver
/// abrirAsistentePantalla en soporte_chat.dart): se abre SOLO apenas la
/// persona inicia sesión -- es lo primero que ve -- y desde ahí pasa al
/// panel con "Ir al panel". En el dashboard queda solo este acceso
/// compacto para volver a abrirlo (o hablarle directo con el micrófono).
///
/// La IA contesta con los datos reales y las acciones que ya tiene
/// (consultar ventas y saldos, preparar facturas y productos...) y puede
/// llevar a la sección correcta del panel (`secciones` / `onNavegar` y la
/// marca [[ABRIR:...]] en el backend).
class AsistenteIABar extends StatefulWidget {
  final int? negocioId;
  /// Secciones de ESTE perfil que la IA puede proponer abrir: clave ->
  /// "Nombre: qué hay ahí".
  final Map<String, String> secciones;
  final void Function(String clave) onNavegar;
  /// Sugerencias tocables (ícono, texto que se manda tal cual).
  final List<(IconData, String)> sugerencias;
  /// Ejemplos que van rotando en el acceso.
  final List<String> ejemplos;
  final String? saludo;

  const AsistenteIABar({
    super.key,
    this.negocioId,
    required this.secciones,
    required this.onNavegar,
    required this.sugerencias,
    this.ejemplos = const [],
    this.saludo,
  });

  /// El primer dashboard que se construye después de iniciar sesión abre
  /// el asistente en pantalla completa una vez. Login lo vuelve a armar
  /// (ver login.dart) para el próximo ingreso.
  static bool _abrirAlEntrar = true;
  static void abrirAlProximoIngreso() => _abrirAlEntrar = true;

  @override
  State<AsistenteIABar> createState() => _AsistenteIABarState();
}

class _AsistenteIABarState extends State<AsistenteIABar> with SingleTickerProviderStateMixin {
  static const _cianSuave = Color(0xFF67E8F9);

  late final AnimationController _brillo = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  Timer? _rotarEjemplo;
  int _ejemplo = 0;

  List<String> get _pistas => ['Hola, soy Equilibra. ¿Qué querés que hagamos hoy?', ...widget.ejemplos];

  @override
  void initState() {
    super.initState();
    if (widget.ejemplos.isNotEmpty) {
      _rotarEjemplo = Timer.periodic(const Duration(milliseconds: 3200), (_) {
        if (mounted) setState(() => _ejemplo = (_ejemplo + 1) % _pistas.length);
      });
    }
    if (AsistenteIABar._abrirAlEntrar) {
      AsistenteIABar._abrirAlEntrar = false;
      _pendienteAbrir = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _abrirSiCorresponde());
      // El nombre del saludo a veces llega un momento después (perfil del
      // contador); se espera un poco, pero nunca más de 2 segundos.
      _esperaSaludo = Timer(const Duration(seconds: 2), () => _abrirSiCorresponde(forzar: true));
    }
  }

  bool _pendienteAbrir = false;
  Timer? _esperaSaludo;

  void _abrirSiCorresponde({bool forzar = false}) {
    if (!_pendienteAbrir || !mounted) return;
    if (widget.saludo == null && !forzar) return;
    _pendienteAbrir = false;
    _esperaSaludo?.cancel();
    _abrir();
  }

  @override
  void didUpdateWidget(covariant AsistenteIABar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_pendienteAbrir && widget.saludo != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _abrirSiCorresponde());
    }
  }

  @override
  void dispose() {
    _esperaSaludo?.cancel();
    _rotarEjemplo?.cancel();
    _brillo.dispose();
    super.dispose();
  }

  void _abrir({bool empezarGrabando = false}) {
    abrirAsistentePantalla(
      context,
      negocioId: widget.negocioId,
      secciones: widget.secciones,
      onNavegar: widget.onNavegar,
      sugerencias: widget.sugerencias,
      saludo: widget.saludo,
      empezarGrabando: empezarGrabando,
    );
  }

  @override
  Widget build(BuildContext context) {
    final compacto = MediaQuery.of(context).size.width < 600;
    final pistas = _pistas;
    final pista = pistas[_ejemplo % pistas.length];

    return AnimatedBuilder(
      animation: _brillo,
      builder: (context, child) {
        // Un brillo cian que recorre el borde, muy sutil.
        final t = _brillo.value * 2 * math.pi;
        return Container(
          margin: const EdgeInsets.only(bottom: 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: SweepGradient(
              transform: GradientRotation(t),
              colors: const [Color(0x6622D3EE), Color(0x00312E81), Color(0x664F46E5), Color(0x0022D3EE), Color(0x6622D3EE)],
            ),
            boxShadow: [BoxShadow(color: const Color(0xFF22D3EE).withOpacity(0.10), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          padding: const EdgeInsets.all(1.5),
          child: child,
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _abrir,
          borderRadius: BorderRadius.circular(19),
          child: Ink(
            padding: EdgeInsets.fromLTRB(compacto ? 12 : 16, 12, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(19),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0B1120), Color(0xFF16193A), Color(0xFF0E2A3A)],
              ),
            ),
            child: Row(
              children: [
                _IconoIA(animacion: _brillo),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF4ADE80), shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          const Flexible(
                            child: Text(
                              "Equilibra · tu asistente virtual",
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: _cianSuave, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.2),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        transitionBuilder: (c, a) => FadeTransition(
                          opacity: a,
                          child: SlideTransition(position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(a), child: c),
                        ),
                        child: Text(
                          pista,
                          key: ValueKey(pista),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: compacto ? 13.5 : 15),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (!compacto) ...[
                  Text("Abrir", style: TextStyle(color: Colors.white.withOpacity(0.55), fontWeight: FontWeight.w700, fontSize: 13)),
                  Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.55)),
                  const SizedBox(width: 8),
                ],
                _BotonMicrofono(animacion: _brillo, onTap: () => _abrir(empezarGrabando: true)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ícono de "IA": destellos sobre un círculo con degradado que gira.
class _IconoIA extends StatelessWidget {
  final Animation<double> animacion;
  const _IconoIA({required this.animacion});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animacion,
      builder: (context, _) {
        final t = animacion.value;
        final pulso = 0.5 + 0.5 * math.sin(t * 2 * math.pi * 2);
        return Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              transform: GradientRotation(t * 2 * math.pi),
              colors: const [Color(0xFF22D3EE), Color(0xFF6366F1), Color(0xFFA855F7), Color(0xFF22D3EE)],
            ),
            boxShadow: [BoxShadow(color: const Color(0xFF22D3EE).withOpacity(0.25 + 0.25 * pulso), blurRadius: 12 + 6 * pulso)],
          ),
          padding: const EdgeInsets.all(2),
          child: Container(
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF0F1530)),
            child: Transform.scale(
              scale: 0.92 + 0.12 * pulso,
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
            ),
          ),
        );
      },
    );
  }
}

/// Micrófono con degradado y un aro que respira: abre el asistente ya
/// grabando una nota de voz.
class _BotonMicrofono extends StatelessWidget {
  final Animation<double> animacion;
  final VoidCallback onTap;
  const _BotonMicrofono({required this.animacion, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Hablale a Equilibra (nota de voz)',
      child: AnimatedBuilder(
        animation: animacion,
        builder: (context, child) {
          final pulso = 0.5 + 0.5 * math.sin(animacion.value * 2 * math.pi * 3);
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: const Color(0xFF22D3EE).withOpacity(0.20 + 0.30 * pulso), blurRadius: 8 + 10 * pulso)],
            ),
            child: child,
          );
        },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(colors: [Color(0xFF22D3EE), Color(0xFF6366F1)]),
              ),
              child: const Icon(Icons.mic_rounded, color: Colors.white, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}
