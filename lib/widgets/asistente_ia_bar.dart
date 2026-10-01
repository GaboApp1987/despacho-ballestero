import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'soporte_chat.dart';

/// Barra "¿Qué querés hacer hoy?" -- lo primero en el dashboard de cada
/// perfil (negocio, contador, despacho y administrador). Lo que se escribe
/// acá lo contesta la IA (mismo asistente del chat de soporte, con acceso a
/// los datos reales y a las acciones que ya tiene: consultar ventas y
/// saldos, preparar facturas y productos...) y además puede llevar a la
/// persona a la sección correcta del panel (ver `secciones` / `onNavegar`
/// y la marca [[ABRIR:...]] en el backend).
///
/// Diseño fijo de marca (degradado oscuro con acentos cian) para que se vea
/// igual de bien en el tema oscuro del negocio y en el claro del contador.
class AsistenteIABar extends StatefulWidget {
  final int? negocioId;
  /// Secciones de ESTE perfil que la IA puede proponer abrir: clave ->
  /// "Nombre: qué hay ahí".
  final Map<String, String> secciones;
  final void Function(String clave) onNavegar;
  /// Sugerencias tocables (ícono, texto que se manda tal cual).
  final List<(IconData, String)> sugerencias;
  /// Ejemplos que van rotando en el campo de texto.
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

  @override
  State<AsistenteIABar> createState() => _AsistenteIABarState();
}

class _AsistenteIABarState extends State<AsistenteIABar> with SingleTickerProviderStateMixin {
  static const _cian = Color(0xFF22D3EE);
  static const _cianSuave = Color(0xFF67E8F9);

  final _ctrl = TextEditingController();
  final _foco = FocusNode();
  late final AnimationController _brillo = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  Timer? _rotarEjemplo;
  int _ejemplo = 0;

  /// Lo que se ve en gris dentro del campo: primero se presenta, después
  /// van rotando ejemplos de lo que se le puede pedir.
  List<String> get _pistas => ['Hola, soy Equilibra. ¿Qué querés que hagamos hoy?', ...widget.ejemplos];

  @override
  void initState() {
    super.initState();
    if (widget.ejemplos.isNotEmpty) {
      _rotarEjemplo = Timer.periodic(const Duration(milliseconds: 3200), (_) {
        if (mounted && _ctrl.text.isEmpty && !_foco.hasFocus) {
          setState(() => _ejemplo = (_ejemplo + 1) % _pistas.length);
        }
      });
    }
    _foco.addListener(() => setState(() {}));
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _rotarEjemplo?.cancel();
    _brillo.dispose();
    _ctrl.dispose();
    _foco.dispose();
    super.dispose();
  }

  void _preguntar([String? texto]) {
    final pregunta = (texto ?? _ctrl.text).trim();
    if (pregunta.isEmpty) {
      _foco.requestFocus();
      return;
    }
    _ctrl.clear();
    _foco.unfocus();
    mostrarSoporteChat(
      context,
      contexto: 'usuario',
      negocioId: widget.negocioId,
      mensajeInicial: pregunta,
      secciones: widget.secciones,
      onNavegar: widget.onNavegar,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.of(context).size.width;
    final compacto = ancho < 600;
    final pistas = _pistas;
    final pista = pistas[_ejemplo % pistas.length];

    return AnimatedBuilder(
      animation: _brillo,
      builder: (context, child) {
        // Un brillo cian que recorre el borde de la tarjeta, muy sutil.
        final t = _brillo.value * 2 * math.pi;
        return Container(
          margin: const EdgeInsets.only(bottom: 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: SweepGradient(
              transform: GradientRotation(t),
              colors: const [Color(0x6622D3EE), Color(0x00312E81), Color(0x664F46E5), Color(0x0022D3EE), Color(0x6622D3EE)],
            ),
            boxShadow: [BoxShadow(color: const Color(0xFF22D3EE).withOpacity(0.10), blurRadius: 30, offset: const Offset(0, 10))],
          ),
          padding: const EdgeInsets.all(1.5),
          child: child,
        );
      },
      child: Container(
        padding: EdgeInsets.fromLTRB(compacto ? 18 : 26, compacto ? 18 : 24, compacto ? 18 : 26, compacto ? 16 : 22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(23),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0B1120), Color(0xFF16193A), Color(0xFF0E2A3A)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _IconoIA(animacion: _brillo),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _InsigniaAsistente(),
                      const SizedBox(height: 8),
                      if (widget.saludo != null)
                        Text("${widget.saludo!} 👋", style: const TextStyle(color: _cianSuave, fontSize: 13, fontWeight: FontWeight.w700)),
                      Text(
                        "Soy Equilibra, ¿qué hacemos hoy?",
                        style: TextStyle(color: Colors.white, fontSize: compacto ? 19 : 23, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Estoy para ayudarte: facturo, reviso tus números y te llevo a donde necesités.",
                        style: TextStyle(color: Colors.white.withOpacity(0.66), fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // --- campo de pregunta
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(_foco.hasFocus ? 0.11 : 0.07),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _foco.hasFocus ? _cian : Colors.white.withOpacity(0.14), width: _foco.hasFocus ? 1.5 : 1),
              ),
              padding: const EdgeInsets.only(left: 16, right: 6),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.55), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        if (_ctrl.text.isEmpty)
                          IgnorePointer(
                            child: AnimatedSwitcher(
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
                                style: TextStyle(color: Colors.white.withOpacity(0.42), fontSize: 15),
                              ),
                            ),
                          ),
                        TextField(
                          controller: _ctrl,
                          focusNode: _foco,
                          onSubmitted: (_) => _preguntar(),
                          textInputAction: TextInputAction.send,
                          cursorColor: _cian,
                          style: const TextStyle(color: Colors.white, fontSize: 15),
                          decoration: const InputDecoration(
                            // El tema general de la app rellena los campos; acá
                            // tiene que ser transparente para ver la pista.
                            filled: false,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            border: InputBorder.none,
                            isCollapsed: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  _BotonEnviar(activo: _ctrl.text.trim().isNotEmpty, onTap: () => _preguntar()),
                ],
              ),
            ),
            if (widget.sugerencias.isNotEmpty) ...[
              const SizedBox(height: 14),
              // En celular, una sola fila que se desliza de lado; en pantalla
              // ancha, todas visibles.
              if (compacto)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final (icono, texto) in widget.sugerencias)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _ChipSugerencia(icono: icono, texto: texto, onTap: () => _preguntar(texto)),
                        ),
                    ],
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (icono, texto) in widget.sugerencias)
                      _ChipSugerencia(icono: icono, texto: texto, onTap: () => _preguntar(texto)),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "● Tu asistente virtual · en línea" -- para que se sienta como alguien
/// del equipo, no como un buscador.
class _InsigniaAsistente extends StatelessWidget {
  const _InsigniaAsistente();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF22D3EE).withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF22D3EE).withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF4ADE80), shape: BoxShape.circle)),
          const SizedBox(width: 6),
          const Text(
            "TU ASISTENTE VIRTUAL · EN LÍNEA",
            style: TextStyle(color: Color(0xFF67E8F9), fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8),
          ),
        ],
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
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              transform: GradientRotation(t * 2 * math.pi),
              colors: const [Color(0xFF22D3EE), Color(0xFF6366F1), Color(0xFFA855F7), Color(0xFF22D3EE)],
            ),
            boxShadow: [BoxShadow(color: const Color(0xFF22D3EE).withOpacity(0.25 + 0.25 * pulso), blurRadius: 14 + 8 * pulso)],
          ),
          padding: const EdgeInsets.all(2),
          child: Container(
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF0F1530)),
            child: Transform.scale(
              scale: 0.92 + 0.12 * pulso,
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 24),
            ),
          ),
        );
      },
    );
  }
}

class _BotonEnviar extends StatelessWidget {
  final bool activo;
  final VoidCallback onTap;
  const _BotonEnviar({required this.activo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: activo
                ? const LinearGradient(colors: [Color(0xFF22D3EE), Color(0xFF6366F1)])
                : LinearGradient(colors: [Colors.white.withOpacity(0.10), Colors.white.withOpacity(0.10)]),
          ),
          child: Icon(Icons.arrow_upward_rounded, color: activo ? Colors.white : Colors.white54, size: 22),
        ),
      ),
    );
  }
}

class _ChipSugerencia extends StatefulWidget {
  final IconData icono;
  final String texto;
  final VoidCallback onTap;
  const _ChipSugerencia({required this.icono, required this.texto, required this.onTap});

  @override
  State<_ChipSugerencia> createState() => _ChipSugerenciaState();
}

class _ChipSugerenciaState extends State<_ChipSugerencia> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(_hover ? 0.14 : 0.07),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _hover ? const Color(0xFF22D3EE) : Colors.white.withOpacity(0.14)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icono, size: 15, color: const Color(0xFF67E8F9)),
              const SizedBox(width: 6),
              Text(widget.texto, style: TextStyle(color: Colors.white.withOpacity(0.88), fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
