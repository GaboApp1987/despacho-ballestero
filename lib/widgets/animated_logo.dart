import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Logo animado de Equilibra para fondos oscuros fijos (ver login.dart,
/// panel de marca): dibuja el trazo blanco y luego el cian (con leve
/// solape), con un pequeño rebote de escala al entrar; al terminar de
/// dibujarse dispara un destello y se asienta en un brillo cian pulsante
/// continuo. Es la versión "más impactante" del logo animado del landing
/// (que usa CSS sobre el SVG) -- acá se dibuja a mano con un CustomPainter
/// porque Flutter no anima stroke-dasharray de un SVG cargado como imagen.
class AnimatedLogoEquilibra extends StatefulWidget {
  final double height;
  const AnimatedLogoEquilibra({super.key, this.height = 56});

  @override
  State<AnimatedLogoEquilibra> createState() => _AnimatedLogoEquilibraState();
}

class _AnimatedLogoEquilibraState extends State<AnimatedLogoEquilibra> with TickerProviderStateMixin {
  late final AnimationController _drawCtrl;
  late final AnimationController _glowCtrl;
  late final AnimationController _flashCtrl;

  @override
  void initState() {
    super.initState();
    _drawCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _glowCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
    _flashCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _drawCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) _flashCtrl.forward(from: 0);
    });
    _drawCtrl.forward();
  }

  @override
  void dispose() {
    _drawCtrl.dispose();
    _glowCtrl.dispose();
    _flashCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_drawCtrl, _glowCtrl, _flashCtrl]),
      builder: (context, _) {
        final drawT = Curves.easeOutCubic.transform(_drawCtrl.value);
        final bounce = Curves.easeOutBack.transform(_drawCtrl.value);
        // El destello decae rapido desde 1.0 apenas termina de dibujarse.
        final flash = 1.0 - Curves.easeOut.transform(_flashCtrl.value);

        return Opacity(
          opacity: (_drawCtrl.value / 0.2).clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.72 + 0.28 * bounce,
            child: CustomPaint(
              size: Size(widget.height * (382 / 142), widget.height),
              painter: _LogoPainter(drawT: drawT, glow: _glowCtrl.value, flash: flash),
            ),
          ),
        );
      },
    );
  }
}

class _LogoPainter extends CustomPainter {
  final double drawT;
  final double glow;
  final double flash;

  _LogoPainter({required this.drawT, required this.glow, required this.flash});

  static const double _vbW = 382, _vbH = 142;

  Path _trazoBlanco() {
    final p = Path()
      ..moveTo(74.14, 94.14)
      ..arcToPoint(const Offset(80, 80), radius: const Radius.circular(20), largeArc: true, clockwise: true)
      ..moveTo(40, 80)
      ..lineTo(80, 80)
      ..addOval(Rect.fromCircle(center: const Offset(112, 80), radius: 20))
      ..moveTo(132, 60)
      ..lineTo(132, 130)
      ..moveTo(148, 60)
      ..lineTo(148, 80)
      ..moveTo(148, 80)
      ..arcToPoint(const Offset(188, 80), radius: const Radius.circular(20), clockwise: false)
      ..moveTo(188, 60)
      ..lineTo(188, 100)
      ..moveTo(204, 60)
      ..lineTo(204, 100);
    return p;
  }

  Path _trazoCian() {
    final p = Path()
      ..moveTo(220, 36)
      ..lineTo(220, 100)
      ..moveTo(236, 60)
      ..lineTo(236, 100)
      ..moveTo(252, 36)
      ..lineTo(252, 100)
      ..addOval(Rect.fromCircle(center: const Offset(272, 80), radius: 20))
      ..moveTo(306, 60)
      ..lineTo(306, 100)
      ..moveTo(306, 76)
      ..arcToPoint(const Offset(322, 60), radius: const Radius.circular(16), clockwise: true)
      ..addOval(Rect.fromCircle(center: const Offset(354, 80), radius: 20))
      ..moveTo(374, 60)
      ..lineTo(374, 100);
    return p;
  }

  /// Revela una fracción `t` (0..1) del largo total de `source`, contorno
  /// por contorno -- la técnica estándar en Flutter para animar un "dibujo"
  /// de trazo progresivo (no hay stroke-dasharray nativo).
  Path _revelar(Path source, double t) {
    if (t <= 0) return Path();
    final metrics = source.computeMetrics().toList();
    final total = metrics.fold<double>(0, (a, m) => a + m.length);
    double restante = total * t.clamp(0.0, 1.0);
    final resultado = Path();
    for (final m in metrics) {
      if (restante <= 0) break;
      final largo = math.min(m.length, restante);
      resultado.addPath(m.extractPath(0, largo), Offset.zero);
      restante -= m.length;
    }
    return resultado;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _vbW, size.height / _vbH);
    // El SVG original envuelve toda la geometría en <g transform="translate(-16,-12)">.
    canvas.translate(-16, -12);

    final progresoBlanco = (drawT / 0.7).clamp(0.0, 1.0);
    final progresoCian = ((drawT - 0.25) / 0.75).clamp(0.0, 1.0);
    final trazoBlanco = _revelar(_trazoBlanco(), progresoBlanco);
    final trazoCian = _revelar(_trazoCian(), progresoCian);

    Paint trazo(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Brillo detrás del trazo: respiración continua + destello al completar.
    if (drawT >= 0.999) {
      final intensidad = (0.16 + 0.34 * glow + 0.7 * flash).clamp(0.0, 1.0);
      final blur = 5 + 9 * glow + 16 * flash;
      canvas.drawPath(
        trazoBlanco,
        trazo(Colors.white.withOpacity(intensidad * 0.5))..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
      );
      canvas.drawPath(
        trazoCian,
        trazo(const Color(0xFF6BD4EA).withOpacity(intensidad))..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
      );
    }

    canvas.drawPath(trazoBlanco, trazo(Colors.white));
    canvas.drawPath(trazoCian, trazo(const Color(0xFF6BD4EA)));

    if (progresoBlanco >= 0.999) {
      canvas.drawCircle(const Offset(204, 46), 4.5, Paint()..color = Colors.white);
    }
    if (progresoCian >= 0.999) {
      canvas.drawCircle(const Offset(236, 46), 4.5, Paint()..color = const Color(0xFF6BD4EA));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LogoPainter oldDelegate) =>
      oldDelegate.drawT != drawT || oldDelegate.glow != glow || oldDelegate.flash != flash;
}
