import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../api_service.dart';
import '../theme/app_theme.dart';

/// Guía de "Primeros pasos" arriba del Dashboard del negocio -- para que
/// quien se acaba de registrar sepa qué hacer primero y llegue rápido a su
/// primera factura. Los pasos los calcula el backend con datos reales
/// (NegocioViewSet.primeros_pasos): se marcan solos al completarlos, la
/// guía desaparece sola al terminar y solo la ve el dueño del negocio.
///
/// Cada vez que se vuelve al Dashboard se reconstruye este widget y se
/// vuelve a consultar, así el progreso siempre está al día.
class PrimerosPasosCard extends StatefulWidget {
  final int negocioId;
  /// Lleva a la sección del panel donde se hace el paso (ver
  /// _DetalleNegocioState._cambiarSeccion).
  final void Function(int seccion) onIrASeccion;
  /// El paso "Emití tu primera factura" abre directo el formulario.
  final Future<void> Function() onNuevaFactura;

  const PrimerosPasosCard({super.key, required this.negocioId, required this.onIrASeccion, required this.onNuevaFactura});

  @override
  State<PrimerosPasosCard> createState() => _PrimerosPasosCardState();
}

class _PrimerosPasosCardState extends State<PrimerosPasosCard> {
  Map<String, dynamic>? _datos;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final r = await ApiService.get('/negocios/${widget.negocioId}/primeros-pasos/');
      if (r.statusCode == 200 && mounted) setState(() => _datos = json.decode(utf8.decode(r.bodyBytes)));
    } catch (_) {
      // Sin guía si falla -- el resto del Dashboard sigue normal.
    }
  }

  Future<void> _ocultar() async {
    setState(() => _datos = {...?_datos, 'mostrar': false});
    try {
      await ApiService.post('/negocios/${widget.negocioId}/primeros-pasos/', {'ocultar': true});
    } catch (_) {}
  }

  Future<void> _abrirPaso(Map<String, dynamic> paso) async {
    if (paso['id'] == 'factura') {
      await widget.onNuevaFactura();
      _cargar();
    } else {
      widget.onIrASeccion((paso['seccion'] as num).toInt());
    }
  }

  static const _iconos = {
    'hacienda': Icons.verified_user_outlined,
    'productos': Icons.inventory_2_outlined,
    'clientes': Icons.people_alt_outlined,
    'factura': Icons.receipt_long_outlined,
    'logo': Icons.image_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final datos = _datos;
    if (datos == null || datos['mostrar'] != true) return const SizedBox.shrink();
    final pasos = ((datos['pasos'] as List?) ?? []).cast<Map<String, dynamic>>();
    final completados = (datos['completados'] as num).toInt();
    final total = (datos['total'] as num).toInt();
    final siguiente = pasos.indexWhere((p) => p['completado'] != true);

    return Container(
      margin: const EdgeInsets.only(bottom: 25),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.35)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary.withOpacity(0.12), AppColors.surface, AppColors.surface],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 12, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- encabezado: anillo de progreso + título + cerrar
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AnilloProgreso(completados: completados, total: total),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("🚀 Primeros pasos", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
                      const SizedBox(height: 4),
                      Text(
                        siguiente == -1
                            ? "¡Todo listo!"
                            : "Completá estos pasos y empezá a facturar hoy. Te quedan ${total - completados}.",
                        style: TextStyle(fontSize: 13.5, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: "Ocultar la guía",
                  icon: Icon(Icons.close, size: 20, color: AppColors.textMuted),
                  onPressed: _ocultar,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: total == 0 ? 0 : completados / total),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => LinearProgressIndicator(
                    value: v,
                    minHeight: 6,
                    backgroundColor: AppColors.border.withOpacity(0.6),
                    valueColor: AlwaysStoppedAnimation(AppColors.primary),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            // --- pasos: en fila en pantallas anchas, uno debajo del otro en celular
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: LayoutBuilder(builder: (context, c) {
                final ancho = c.maxWidth;
                final columnas = ancho >= 1100 ? 5 : (ancho >= 760 ? 3 : 1);
                final separacion = 12.0;
                final anchoTarjeta = (ancho - separacion * (columnas - 1)) / columnas;
                return Wrap(
                  spacing: separacion,
                  runSpacing: separacion,
                  children: [
                    for (var i = 0; i < pasos.length; i++)
                      SizedBox(
                        width: anchoTarjeta,
                        child: _TarjetaPaso(
                          numero: i + 1,
                          paso: pasos[i],
                          icono: _iconos[pasos[i]['id']] ?? Icons.flag_outlined,
                          esSiguiente: i == siguiente,
                          compacta: columnas == 1,
                          onTap: () => _abrirPaso(pasos[i]),
                        ),
                      ),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnilloProgreso extends StatelessWidget {
  final int completados;
  final int total;
  const _AnilloProgreso({required this.completados, required this.total});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: total == 0 ? 0 : completados / total),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => SizedBox(
        width: 56,
        height: 56,
        child: CustomPaint(
          painter: _PintorAnillo(progreso: v, color: AppColors.primary, fondo: AppColors.border),
          child: Center(
            child: Text(
              "$completados/$total",
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textStrong),
            ),
          ),
        ),
      ),
    );
  }
}

class _PintorAnillo extends CustomPainter {
  final double progreso;
  final Color color;
  final Color fondo;
  _PintorAnillo({required this.progreso, required this.color, required this.fondo});

  @override
  void paint(Canvas canvas, Size size) {
    const grosor = 6.0;
    final rect = Offset.zero & size;
    final area = rect.deflate(grosor / 2);
    canvas.drawArc(area, 0, math.pi * 2, false, Paint()
      ..color = fondo
      ..style = PaintingStyle.stroke
      ..strokeWidth = grosor);
    canvas.drawArc(area, -math.pi / 2, math.pi * 2 * progreso, false, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = grosor
      ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_PintorAnillo old) => old.progreso != progreso || old.color != color;
}

class _TarjetaPaso extends StatefulWidget {
  final int numero;
  final Map<String, dynamic> paso;
  final IconData icono;
  final bool esSiguiente;
  final bool compacta;
  final VoidCallback onTap;

  const _TarjetaPaso({
    required this.numero,
    required this.paso,
    required this.icono,
    required this.esSiguiente,
    required this.compacta,
    required this.onTap,
  });

  @override
  State<_TarjetaPaso> createState() => _TarjetaPasoState();
}

class _TarjetaPasoState extends State<_TarjetaPaso> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final hecho = widget.paso['completado'] == true;
    final verde = Colors.green.shade400;
    final borde = widget.esSiguiente
        ? AppColors.primary
        : (_hover && !hecho ? AppColors.primary.withOpacity(0.5) : AppColors.border);

    final circulo = AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hecho ? verde.withOpacity(0.16) : (widget.esSiguiente ? AppColors.primary : AppColors.primary.withOpacity(0.10)),
      ),
      child: Icon(
        hecho ? Icons.check_rounded : widget.icono,
        size: 20,
        color: hecho ? verde : (widget.esSiguiente ? Colors.black : AppColors.primary),
      ),
    );

    final textos = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "Paso ${widget.numero}",
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: hecho ? verde : AppColors.primary),
        ),
        const SizedBox(height: 3),
        Text(
          widget.paso['titulo'] ?? '',
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: hecho ? AppColors.textMuted : AppColors.textStrong,
            decoration: hecho ? TextDecoration.lineThrough : null,
            decorationColor: AppColors.textMuted,
          ),
        ),
        if (!hecho) ...[
          const SizedBox(height: 4),
          Text(widget.paso['descripcion'] ?? '', style: TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.textMuted)),
        ],
      ],
    );

    final accion = hecho
        ? Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.check_circle, size: 16, color: verde),
            const SizedBox(width: 4),
            Text("Listo", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: verde)),
          ])
        : (widget.esSiguiente
            ? FilledButton(
                onPressed: widget.onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text("Empezar", style: TextStyle(fontWeight: FontWeight.w800)),
              )
            : TextButton(
                onPressed: widget.onTap,
                child: Row(mainAxisSize: MainAxisSize.min, children: const [Text("Ir"), SizedBox(width: 2), Icon(Icons.arrow_forward, size: 16)]),
              ));

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borde, width: widget.esSiguiente ? 1.6 : 1),
          boxShadow: widget.esSiguiente ? [BoxShadow(color: AppColors.primary.withOpacity(0.18), blurRadius: 18, offset: const Offset(0, 6))] : null,
        ),
        child: InkWell(
          onTap: hecho ? null : widget.onTap,
          borderRadius: BorderRadius.circular(14),
          child: widget.compacta
              // Celular: una fila (círculo · textos · acción).
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    circulo,
                    const SizedBox(width: 12),
                    Expanded(child: textos),
                    const SizedBox(width: 8),
                    accion,
                  ],
                )
              // Pantalla ancha: tarjeta vertical de alto parejo.
              : SizedBox(
                  height: 200,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      circulo,
                      const SizedBox(height: 12),
                      Expanded(child: textos),
                      Align(alignment: Alignment.centerLeft, child: accion),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
