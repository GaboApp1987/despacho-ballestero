import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'api_service.dart';
import 'negocio.dart';
import 'theme/app_theme.dart';

/// Plano del restaurante: una cuadrícula por zona con las mesas y lo demás
/// (paredes, maceteras, baños, barra...) para que los meseros se ubiquen.
/// [PlanoSalon] lo dibuja en el Salón (solo tocar mesas); [EditorPlano] lo
/// arma arrastrando las piezas.

class EstiloPieza {
  final String nombre;
  final Color color;
  final IconData? icono;
  final int ancho;
  final int alto;
  const EstiloPieza(this.nombre, this.color, this.icono, this.ancho, this.alto);
}

const estilosPlano = <String, EstiloPieza>{
  'pared': EstiloPieza("Pared", Color(0xFF475569), null, 6, 1),
  'maceta': EstiloPieza("Macetera", Color(0xFF16A34A), Icons.local_florist, 1, 1),
  'bano': EstiloPieza("Baños", Color(0xFF0EA5E9), Icons.wc, 3, 3),
  'barra': EstiloPieza("Barra", Color(0xFF92400E), Icons.local_bar_outlined, 6, 2),
  'cocina': EstiloPieza("Cocina", Color(0xFFF97316), Icons.soup_kitchen_outlined, 5, 4),
  'puerta': EstiloPieza("Puerta", Color(0xFFF59E0B), Icons.door_front_door_outlined, 2, 1),
  'caja': EstiloPieza("Caja", Color(0xFF7C3AED), Icons.point_of_sale, 2, 2),
  'ventana': EstiloPieza("Ventana", Color(0xFF7DD3FC), null, 4, 1),
  'texto': EstiloPieza("Letrero", Color(0xFF64748B), Icons.title, 4, 1),
};

/// Una pieza del plano: una mesa (mesaId) o un elemento (tipo).
class PiezaPlano {
  final int? mesaId;
  final String tipo; // 'mesa' o un tipo de estilosPlano
  String nombre;
  String zona;
  int? x;
  int? y;
  int ancho;
  int alto;
  String forma;
  String etiqueta;

  PiezaPlano({
    this.mesaId,
    required this.tipo,
    this.nombre = '',
    this.zona = '',
    this.x,
    this.y,
    this.ancho = 1,
    this.alto = 1,
    this.forma = 'cuadrada',
    this.etiqueta = '',
  });

  bool get esMesa => mesaId != null;
  bool get ubicada => x != null && y != null;

  factory PiezaPlano.mesa(Map<String, dynamic> m) => PiezaPlano(
        mesaId: m['id'] as int,
        tipo: 'mesa',
        nombre: (m['nombre'] ?? '').toString(),
        zona: (m['zona'] ?? '').toString(),
        x: m['x'] as int?,
        y: m['y'] as int?,
        ancho: (m['ancho'] ?? 2) as int,
        alto: (m['alto'] ?? 2) as int,
        forma: (m['forma'] ?? 'cuadrada').toString(),
      );

  factory PiezaPlano.elemento(Map<String, dynamic> e) => PiezaPlano(
        tipo: e['tipo'],
        zona: (e['zona'] ?? '').toString(),
        x: e['x'] as int,
        y: e['y'] as int,
        ancho: e['ancho'] as int,
        alto: e['alto'] as int,
        etiqueta: (e['etiqueta'] ?? '').toString(),
      );
}

/// Dibujo de una pieza que no es mesa.
Widget dibujoElemento(PiezaPlano p, double celda, {bool seleccionada = false}) {
  final e = estilosPlano[p.tipo]!;
  final texto = p.etiqueta.isNotEmpty ? p.etiqueta : (p.tipo == 'pared' || p.tipo == 'ventana' ? '' : e.nombre);
  final borde = seleccionada ? Border.all(color: AppColors.primary, width: 2.5) : null;
  if (p.tipo == 'texto') {
    return Container(
      decoration: BoxDecoration(border: borde ?? Border.all(color: Colors.transparent)),
      alignment: Alignment.center,
      child: FittedBox(
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Text(texto, style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textMuted)),
        ),
      ),
    );
  }
  final redondo = p.tipo == 'maceta';
  final solido = p.tipo == 'pared' || p.tipo == 'barra';
  return Container(
    decoration: BoxDecoration(
      color: solido ? e.color : e.color.withValues(alpha: p.tipo == 'ventana' ? 0.55 : 0.18),
      shape: redondo ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: redondo ? null : BorderRadius.circular(p.tipo == 'pared' ? 2 : 6),
      border: borde ?? (solido ? null : Border.all(color: e.color, width: 1.5)),
    ),
    alignment: Alignment.center,
    child: (texto.isEmpty && e.icono == null) || math.min(p.ancho, p.alto) * celda < 14
        ? null
        : FittedBox(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (e.icono != null) Icon(e.icono, color: solido ? Colors.white : e.color, size: 18),
                if (texto.isNotEmpty && !redondo) ...[
                  if (e.icono != null) const SizedBox(width: 3),
                  Text(texto, style: TextStyle(fontWeight: FontWeight.w700, color: solido ? Colors.white : e.color)),
                ],
              ]),
            ),
          ),
  );
}

/// Fondo con la cuadrícula (solo en el editor).
class _Cuadricula extends CustomPainter {
  final double celda;
  final Color color;
  _Cuadricula(this.celda, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width + 0.1; x += celda) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (var y = 0.0; y <= size.height + 0.1; y += celda) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_Cuadricula old) => old.celda != celda || old.color != color;
}

String nombreZona(String zona) => zona.isEmpty ? "Salón" : zona;

// ------------------------------------------------------------------ Salón

/// El plano en el Salón: mesas con el color de su estado; tocar una mesa
/// abre su cuenta. Se puede acercar con dos dedos.
class PlanoSalon extends StatelessWidget {
  final int columnas;
  final int filas;
  final List<PiezaPlano> piezas; // de una zona
  final Widget Function(PiezaPlano mesa, double celda) dibujarMesa;
  const PlanoSalon({super.key, required this.columnas, required this.filas, required this.piezas, required this.dibujarMesa});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final celda = math.max(22.0, c.maxWidth / columnas);
      final ancho = celda * columnas, alto = celda * filas;
      final lienzo = Container(
        width: ancho,
        height: alto,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Stack(children: [
          for (final p in piezas.where((p) => p.ubicada))
            Positioned(
              left: p.x! * celda,
              top: p.y! * celda,
              width: p.ancho * celda,
              height: p.alto * celda,
              child: Padding(
                padding: EdgeInsets.all(p.tipo == 'pared' ? 0 : 1.5),
                child: p.esMesa ? dibujarMesa(p, celda) : dibujoElemento(p, celda),
              ),
            ),
        ]),
      );
      if (ancho <= c.maxWidth + 0.5) return lienzo;
      // Pantalla angosta (celular): arranca mostrando todo el plano a lo
      // ancho; con dos dedos se acerca para tocar las mesas con comodidad.
      final escala = c.maxWidth / ancho;
      return SizedBox(
        height: alto * escala,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: InteractiveViewer(
            constrained: false,
            minScale: escala,
            maxScale: 2.5,
            transformationController: TransformationController(Matrix4.diagonal3Values(escala, escala, 1)),
            child: lienzo,
          ),
        ),
      );
    });
  }
}

// ------------------------------------------------------------------ Editor

class EditorPlano extends StatefulWidget {
  final Negocio negocio;
  const EditorPlano({super.key, required this.negocio});

  @override
  State<EditorPlano> createState() => _EditorPlanoState();
}

class _EditorPlanoState extends State<EditorPlano> {
  int _columnas = 30, _filas = 20;
  List<PiezaPlano> _piezas = [];
  String _zona = '';
  PiezaPlano? _sel;
  bool _cargando = true, _guardando = false, _cambios = false;
  Offset _arrastre = Offset.zero;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _aviso(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _cargar() async {
    try {
      final r = await ApiService.get('/restaurante/plano/?negocio=${widget.negocio.id}');
      if (r.statusCode == 200) {
        final d = json.decode(utf8.decode(r.bodyBytes));
        _columnas = d['columnas'];
        _filas = d['filas'];
        _piezas = [
          for (final m in (d['mesas'] as List)) PiezaPlano.mesa(Map<String, dynamic>.from(m)),
          for (final e in (d['elementos'] as List)) PiezaPlano.elemento(Map<String, dynamic>.from(e)),
        ];
        final zonas = _zonas;
        if (zonas.isNotEmpty) _zona = zonas.first;
      }
    } catch (_) {}
    if (mounted) setState(() => _cargando = false);
  }

  List<String> get _zonas {
    final z = <String>[];
    for (final p in _piezas.where((p) => p.esMesa)) {
      if (!z.contains(p.zona)) z.add(p.zona);
    }
    for (final p in _piezas) {
      if (!z.contains(p.zona)) z.add(p.zona);
    }
    return z.isEmpty ? [''] : z;
  }

  List<PiezaPlano> get _deZona => _piezas.where((p) => p.zona == _zona).toList();

  bool _ocupado(int x, int y, int w, int h, {PiezaPlano? salvo}) {
    for (final p in _deZona) {
      if (p == salvo || !p.ubicada) continue;
      if (x < p.x! + p.ancho && p.x! < x + w && y < p.y! + p.alto && p.y! < y + h) return true;
    }
    return false;
  }

  /// Primer lugar libre (de arriba a la izquierda) donde quepa.
  (int, int) _lugarLibre(int w, int h) {
    for (var y = 1; y <= _filas - h; y++) {
      for (var x = 1; x <= _columnas - w; x++) {
        if (!_ocupado(x, y, w, h)) return (x, y);
      }
    }
    return (0, 0);
  }

  void _agregar(String tipo) {
    final e = estilosPlano[tipo]!;
    final (x, y) = _lugarLibre(e.ancho, e.alto);
    final p = PiezaPlano(tipo: tipo, zona: _zona, x: x, y: y, ancho: e.ancho, alto: e.alto);
    setState(() {
      _piezas.add(p);
      _sel = p;
      _cambios = true;
    });
    if (tipo == 'texto') _editarEtiqueta(p);
  }

  void _ubicarMesa(PiezaPlano m) {
    final (x, y) = _lugarLibre(m.ancho, m.alto);
    setState(() {
      m.x = x;
      m.y = y;
      _sel = m;
      _cambios = true;
    });
  }

  void _cambiar(VoidCallback f) {
    setState(() {
      f();
      final p = _sel;
      if (p != null && p.ubicada) {
        p.ancho = p.ancho.clamp(1, p.esMesa ? 8 : _columnas);
        p.alto = p.alto.clamp(1, p.esMesa ? 8 : _filas);
        p.x = p.x!.clamp(0, _columnas - p.ancho);
        p.y = p.y!.clamp(0, _filas - p.alto);
      }
      _cambios = true;
    });
  }

  Future<void> _editarEtiqueta(PiezaPlano p) async {
    final ctrl = TextEditingController(text: p.etiqueta);
    final texto = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Texto"),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(hintText: "Ej: Terraza, Baños, Salida", border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text("Listo")),
        ],
      ),
    );
    if (texto != null) _cambiar(() => p.etiqueta = texto);
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      for (final zona in _zonas) {
        final piezas = _piezas.where((p) => p.zona == zona);
        final r = await ApiService.put('/restaurante/plano/', {
          'negocio': widget.negocio.id,
          'zona': zona,
          'mesas': [
            for (final m in piezas.where((p) => p.esMesa))
              {'id': m.mesaId, 'x': m.x, 'y': m.y, 'ancho': m.ancho, 'alto': m.alto, 'forma': m.forma},
          ],
          'elementos': [
            for (final e in piezas.where((p) => !p.esMesa && p.ubicada))
              {'tipo': e.tipo, 'x': e.x, 'y': e.y, 'ancho': e.ancho, 'alto': e.alto, 'etiqueta': e.etiqueta},
          ],
        });
        if (r.statusCode != 200) throw Exception(ApiService.mensajeError(r));
      }
      _cambios = false;
      if (mounted) {
        _aviso("Plano guardado.");
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) _aviso("No se pudo guardar: $e");
    }
    if (mounted) setState(() => _guardando = false);
  }

  Widget _dibujoMesa(PiezaPlano m, bool seleccionada) {
    final redonda = m.forma == 'redonda';
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        shape: redonda && m.ancho == m.alto ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: redonda && m.ancho == m.alto ? null : BorderRadius.circular(redonda ? 999 : 8),
        border: Border.all(color: seleccionada ? AppColors.primary : AppColors.primary.withValues(alpha: 0.6), width: seleccionada ? 3 : 1.5),
      ),
      alignment: Alignment.center,
      child: FittedBox(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Text(m.nombre, style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textStrong)),
        ),
      ),
    );
  }

  Widget _lienzo(double celda) {
    final ancho = celda * _columnas, alto = celda * _filas;
    return GestureDetector(
      onTap: () => setState(() => _sel = null),
      child: Container(
        width: ancho,
        height: alto,
        decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border)),
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _Cuadricula(celda, AppColors.border.withValues(alpha: 0.6)))),
          for (final p in _deZona.where((p) => p.ubicada))
            Positioned(
              left: p.x! * celda,
              top: p.y! * celda,
              width: p.ancho * celda,
              height: p.alto * celda,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _sel = p),
                onPanStart: (_) => setState(() {
                  _sel = p;
                  _arrastre = Offset(p.x! * celda, p.y! * celda);
                }),
                onPanUpdate: (d) {
                  _arrastre += d.delta;
                  final nx = (_arrastre.dx / celda).round().clamp(0, _columnas - p.ancho);
                  final ny = (_arrastre.dy / celda).round().clamp(0, _filas - p.alto);
                  if (nx != p.x || ny != p.y) {
                    setState(() {
                      p.x = nx;
                      p.y = ny;
                      _cambios = true;
                    });
                  }
                },
                child: Padding(
                  padding: EdgeInsets.all(p.tipo == 'pared' ? 0 : 1.5),
                  child: p.esMesa ? _dibujoMesa(p, p == _sel) : dibujoElemento(p, celda, seleccionada: p == _sel),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _barraSeleccion() {
    final p = _sel;
    if (p == null || !p.ubicada) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text("Arrastrá las piezas para moverlas. Tocá una para cambiar su tamaño, girarla o quitarla.",
            textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
      );
    }
    Widget paso(String texto, VoidCallback menos, VoidCallback mas) => Row(mainAxisSize: MainAxisSize.min, children: [
          Text(texto, style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
          IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.remove_circle_outline), onPressed: menos),
          IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.add_circle_outline), onPressed: mas),
        ]);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(children: [
        Text(p.esMesa ? p.nombre : (estilosPlano[p.tipo]?.nombre ?? ''),
            style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textStrong)),
        const SizedBox(width: 8),
        paso("Ancho", () => _cambiar(() => p.ancho--), () => _cambiar(() => p.ancho++)),
        paso("Alto", () => _cambiar(() => p.alto--), () => _cambiar(() => p.alto++)),
        TextButton.icon(
          onPressed: () => _cambiar(() {
            final w = p.ancho;
            p.ancho = p.alto;
            p.alto = w;
          }),
          icon: const Icon(Icons.rotate_90_degrees_ccw, size: 18),
          label: const Text("Girar"),
        ),
        if (p.esMesa)
          for (final f in const [('cuadrada', Icons.crop_square), ('redonda', Icons.circle_outlined), ('rectangular', Icons.crop_landscape)])
            IconButton(
              tooltip: f.$1,
              isSelected: p.forma == f.$1,
              icon: Icon(f.$2),
              onPressed: () => _cambiar(() {
                p.forma = f.$1;
                if (f.$1 == 'rectangular' && p.ancho == p.alto) p.ancho = p.alto + 1;
                if (f.$1 != 'rectangular' && p.ancho != p.alto) p.ancho = p.alto = math.max(p.ancho, p.alto);
              }),
            ),
        if (!p.esMesa)
          TextButton.icon(onPressed: () => _editarEtiqueta(p), icon: const Icon(Icons.edit_outlined, size: 18), label: const Text("Texto")),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () => _cambiar(() {
            if (p.esMesa) {
              p.x = p.y = null; // vuelve a "sin ubicar"
            } else {
              _piezas.remove(p);
            }
            _sel = null;
          }),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text(p.esMesa ? "Sacar del plano" : "Quitar"),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final zonas = _zonas;
    final sinUbicar = _deZona.where((p) => p.esMesa && !p.ubicada).toList();
    return PopScope(
      canPop: !_cambios,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navegador = Navigator.of(context);
        final salir = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Cambios sin guardar"),
            content: const Text("¿Salir sin guardar el plano?"),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Salir")),
              FilledButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Quedarme")),
            ],
          ),
        );
        if (salir == true) {
          _cambios = false;
          navegador.pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.surfaceSubtle,
        appBar: AppBar(
          title: const Text("Plano del restaurante"),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: _guardando || _cargando ? null : _guardar,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text("Guardar"),
              ),
            ),
          ],
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : Column(children: [
                if (zonas.length > 1)
                  SizedBox(
                    height: 48,
                    child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), children: [
                      for (final z in zonas)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(nombreZona(z)),
                            selected: z == _zona,
                            onSelected: (_) => setState(() {
                              _zona = z;
                              _sel = null;
                            }),
                          ),
                        ),
                    ]),
                  ),
                // Paleta: lo que se puede agregar.
                SizedBox(
                  height: 48,
                  child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 6, 12, 2), children: [
                    for (final t in estilosPlano.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          avatar: Icon(t.value.icono ?? Icons.horizontal_rule, size: 18, color: t.value.color),
                          label: Text(t.value.nombre),
                          onPressed: () => _agregar(t.key),
                        ),
                      ),
                  ]),
                ),
                if (sinUbicar.isNotEmpty)
                  SizedBox(
                    height: 44,
                    child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 4, 12, 2), children: [
                      Center(child: Text("Sin ubicar: ", style: TextStyle(color: AppColors.textMuted, fontSize: 12.5))),
                      for (final m in sinUbicar)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            avatar: const Icon(Icons.add, size: 16),
                            label: Text(m.nombre),
                            onPressed: () => _ubicarMesa(m),
                          ),
                        ),
                    ]),
                  ),
                Expanded(
                  child: LayoutBuilder(builder: (context, c) {
                    final celda = math.max(20.0, math.min((c.maxWidth - 24) / _columnas, (c.maxHeight - 24) / _filas));
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: _lienzo(celda)),
                    );
                  }),
                ),
                Material(color: AppColors.surface, child: SafeArea(top: false, child: _barraSeleccion())),
              ]),
      ),
    );
  }
}
