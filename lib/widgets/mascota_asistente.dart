import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// La mascota del asistente (el botón flotante que abre el mini chat):
/// una gota con los colores de Equilibra que respira y ondula como el
/// "dot" de voz de ChatGPT, pero con cara -- parpadea, mira alrededor (y
/// sigue el mouse en la computadora) y sonríe más cuando la tocás o le
/// pasás el mouse por encima.
class MascotaAsistente extends StatefulWidget {
  final double tamano;
  final VoidCallback? onTap;
  const MascotaAsistente({super.key, this.tamano = 58, this.onTap});

  @override
  State<MascotaAsistente> createState() => _MascotaAsistenteState();
}

class _MascotaAsistenteState extends State<MascotaAsistente> with TickerProviderStateMixin {
  // Reloj continuo: respiración, ondulación del cuerpo y mirada distraída.
  late final AnimationController _reloj = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();
  // Parpadeo (0 = abiertos, 1 = cerrados).
  late final AnimationController _parpadeo = AnimationController(vsync: this, duration: const Duration(milliseconds: 160));
  // Alegría al pasar el mouse / tocar (sonrisa grande + saltito).
  late final AnimationController _alegria = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));

  final _azar = math.Random();
  Offset? _puntero; // posición del mouse relativa al centro (-1..1)
  Timer? _proximoParpadeo;

  @override
  void initState() {
    super.initState();
    _programarParpadeo();
  }

  void _programarParpadeo() {
    _proximoParpadeo = Timer(Duration(milliseconds: 2200 + _azar.nextInt(3200)), () async {
      if (!mounted) return;
      await _parpadeo.forward();
      if (!mounted) return;
      await _parpadeo.reverse();
      // A veces, doble parpadeo.
      if (mounted && _azar.nextDouble() < 0.25) {
        await _parpadeo.forward();
        if (!mounted) return;
        await _parpadeo.reverse();
      }
      if (mounted) _programarParpadeo();
    });
  }

  @override
  void dispose() {
    _proximoParpadeo?.cancel();
    _reloj.dispose();
    _parpadeo.dispose();
    _alegria.dispose();
    super.dispose();
  }

  void _seguir(Offset local) {
    final r = widget.tamano / 2;
    setState(() => _puntero = Offset(((local.dx - r) / r).clamp(-1.0, 1.0), ((local.dy - r) / r).clamp(-1.0, 1.0)));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tamano;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _alegria.forward(),
      onExit: (_) {
        _alegria.reverse();
        setState(() => _puntero = null);
      },
      onHover: (e) => _seguir(e.localPosition),
      child: GestureDetector(
        onTapDown: (_) => _alegria.forward(),
        onTapCancel: () => _alegria.reverse(),
        onTapUp: (_) => _alegria.reverse(),
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: Listenable.merge([_reloj, _parpadeo, _alegria]),
          builder: (context, _) {
            final fase = _reloj.value * 2 * math.pi;
            final alegria = Curves.easeOutBack.transform(_alegria.value.clamp(0.0, 1.0));
            // Respira (~4 s por ciclo) y salta un poquito al alegrarse.
            final escala = 1 + 0.04 * math.sin(fase * 3) + 0.08 * alegria;
            final salto = -4 * alegria;
            // Sin mouse: mira de un lado a otro, despacio.
            final mirada = _puntero ?? Offset(0.55 * math.sin(fase), 0.25 * math.sin(fase * 2 + 1));
            return Transform.translate(
              offset: Offset(0, salto),
              child: Transform.scale(
                scale: escala,
                child: SizedBox(
                  width: t,
                  height: t,
                  child: CustomPaint(
                    painter: _PintorMascota(
                      fase: fase,
                      parpadeo: _parpadeo.value,
                      alegria: alegria,
                      mirada: mirada,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PintorMascota extends CustomPainter {
  final double fase;
  final double parpadeo;
  final double alegria;
  final Offset mirada;
  _PintorMascota({required this.fase, required this.parpadeo, required this.alegria, required this.mirada});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 * 0.86;

    // Cuerpo: una gota que ondula suave (suma de senos sobre el contorno).
    final cuerpo = Path();
    const puntos = 72;
    for (var i = 0; i <= puntos; i++) {
      final a = i / puntos * 2 * math.pi;
      final onda = 1 + 0.018 * math.sin(3 * a + fase * 2) + 0.012 * math.sin(5 * a - fase * 3) + 0.01 * math.cos(2 * a + fase);
      final p = c + Offset(math.cos(a), math.sin(a)) * r * onda;
      i == 0 ? cuerpo.moveTo(p.dx, p.dy) : cuerpo.lineTo(p.dx, p.dy);
    }
    cuerpo.close();

    // Sombra suave debajo.
    canvas.drawShadow(cuerpo, const Color(0xFF4F46E5), 6, false);

    // Degradado que gira despacio (índigo -> celeste -> violeta).
    final relleno = Paint()
      ..shader = SweepGradient(
        colors: const [Color(0xFF6366F1), Color(0xFF22D3EE), Color(0xFF8B5CF6), Color(0xFF6366F1)],
        transform: GradientRotation(fase),
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawPath(cuerpo, relleno);

    // Brillo de arriba (volumen).
    final brillo = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.55),
        radius: 0.9,
        colors: [Colors.white.withValues(alpha: 0.45), Colors.white.withValues(alpha: 0.0)],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawPath(cuerpo, brillo);

    // Ojos.
    final separacion = r * 0.36;
    final altoOjos = c.dy - r * 0.12;
    final radioOjo = r * 0.2;
    final cerrado = parpadeo; // 0..1
    final mirar = Offset(mirada.dx * radioOjo * 0.42, mirada.dy * radioOjo * 0.35);
    for (final lado in [-1.0, 1.0]) {
      final centroOjo = Offset(c.dx + lado * separacion + mirar.dx * 0.35, altoOjos + mirar.dy * 0.3);
      final alto = radioOjo * 2 * (1 - 0.9 * cerrado) * (1 - 0.15 * alegria);
      final rectOjo = Rect.fromCenter(center: centroOjo, width: radioOjo * 1.7, height: alto);
      canvas.drawOval(rectOjo, Paint()..color = Colors.white);
      if (cerrado < 0.7) {
        final pupila = centroOjo + mirar;
        canvas.drawCircle(pupila, radioOjo * 0.52 * (1 - cerrado), Paint()..color = const Color(0xFF1E1B4B));
        canvas.drawCircle(pupila + Offset(-radioOjo * 0.18, -radioOjo * 0.2), radioOjo * 0.16 * (1 - cerrado), Paint()..color = Colors.white);
      }
    }

    // Cachetes al alegrarse.
    if (alegria > 0.05) {
      final cachete = Paint()..color = const Color(0xFFF472B6).withValues(alpha: 0.35 * alegria.clamp(0.0, 1.0));
      for (final lado in [-1.0, 1.0]) {
        canvas.drawOval(Rect.fromCenter(center: Offset(c.dx + lado * r * 0.55, c.dy + r * 0.2), width: r * 0.26, height: r * 0.15), cachete);
      }
    }

    // Boca: sonrisa que se agranda y se abre con la alegría.
    final anchoBoca = r * (0.36 + 0.14 * alegria);
    final yBoca = c.dy + r * 0.3;
    final curva = r * (0.12 + 0.16 * alegria);
    final boca = Path()
      ..moveTo(c.dx - anchoBoca / 2, yBoca)
      ..quadraticBezierTo(c.dx, yBoca + curva * 2, c.dx + anchoBoca / 2, yBoca);
    if (alegria > 0.35) {
      // Boca abierta (rellena) cuando está muy contenta.
      final abierta = Path.from(boca)..quadraticBezierTo(c.dx, yBoca + curva * 0.6, c.dx - anchoBoca / 2, yBoca);
      canvas.drawPath(abierta, Paint()..color = const Color(0xFF1E1B4B));
    } else {
      canvas.drawPath(
        boca,
        Paint()
          ..color = const Color(0xFF1E1B4B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.075
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_PintorMascota old) =>
      old.fase != fase || old.parpadeo != parpadeo || old.alegria != alegria || old.mirada != mirada;
}
