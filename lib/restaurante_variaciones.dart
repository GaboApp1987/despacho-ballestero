import 'dart:convert';

import 'package:flutter/material.dart';

import 'api_service.dart';
import 'formato.dart';
import 'negocio.dart';
import 'producto.dart';
import 'restaurante_tema.dart';
import 'theme/app_theme.dart';
import 'widgets/calculadora.dart';

/// Variaciones de los platos (gestion/restaurante.py): "Tamaño" (se elige
/// una) o "Adicionales" (se pueden elegir varias), cada opción con su
/// precio extra. Son de cada plato y se pueden copiar de otro. El plato
/// sigue siendo un solo producto: las opciones suman al precio y salen en
/// la comanda y en el comprobante.

double _n(dynamic v) => double.tryParse('${v ?? 0}'.replaceAll(',', '.')) ?? 0;

String _colones(double v) => formatearColones(v, decimales: 0);

String _extra(double v) => v == 0 ? '' : (v > 0 ? "+${_colones(v)}" : "-${_colones(-v)}");

List<Map<String, dynamic>> _opciones(Map g) => ((g['opciones'] as List?) ?? []).cast<Map<String, dynamic>>();

/// "Grande · + Extra tocineta" (mismo formato que la comanda del backend).
String textoVariaciones(List grupos, List<int> ids) {
  final partes = <String>[];
  for (final g in grupos.cast<Map>()) {
    for (final o in _opciones(g)) {
      if (ids.contains(o['id'])) partes.add(g['tipo'] == 'varias' ? "+ ${o['nombre']}" : "${o['nombre']}");
    }
  }
  return partes.join(' · ');
}

/// Suma de los precio_extra elegidos (sin IVA, como el precio del plato).
double extraVariaciones(List grupos, List<int> ids) {
  var total = 0.0;
  for (final g in grupos.cast<Map>()) {
    for (final o in _opciones(g)) {
      if (ids.contains(o['id'])) total += _n(o['precio_extra']);
    }
  }
  return total;
}

typedef SeleccionVariaciones = ({List<int> opciones, String texto, double extra, String nota, int cantidad});

/// Hoja para elegir las variaciones de un plato al pedirlo. `precioBase` sin
/// IVA; los precios se muestran con IVA, como en el menú.
Future<SeleccionVariaciones?> elegirVariaciones(
  BuildContext context, {
  required String plato,
  required double precioBase,
  required double iva,
  required List grupos,
  List<int> inicial = const [],
  String nota = '',
  int cantidad = 1,
  String textoBoton = "Agregar",
}) {
  final elegidas = {...inicial};
  final notaCtrl = TextEditingController(text: nota);
  var cuantos = cantidad;
  final conIva = 1 + iva / 100;
  return showModalBottomSheet<SeleccionVariaciones>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final faltan = [
        for (final g in grupos.cast<Map>())
          if (g['obligatorio'] == true && !_opciones(g).any((o) => elegidas.contains(o['id']))) g['nombre'].toString()
      ];
      final unitario = (precioBase + extraVariaciones(grupos, elegidas.toList())) * conIva;
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.88),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(children: [
                Expanded(child: Text(plato, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textStrong))),
                Text(_colones(precioBase * conIva), style: TextStyle(color: AppColors.textMuted)),
              ]),
            ),
            Flexible(
              child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(12, 0, 12, 8), children: [
                for (final g in grupos.cast<Map>()) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                    child: Row(children: [
                      Text("${g['nombre']}", style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textStrong)),
                      const SizedBox(width: 8),
                      Text(
                        g['tipo'] == 'varias'
                            ? (g['maximo'] != null ? "Hasta ${g['maximo']}" : "Elegí las que querás")
                            : "Elegí una",
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                      const Spacer(),
                      if (g['obligatorio'] == true)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: (faltan.contains(g['nombre']) ? colorResto : AppColors.textMuted).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text("Obligatorio",
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                  color: faltan.contains(g['nombre']) ? colorResto : AppColors.textMuted)),
                        ),
                    ]),
                  ),
                  for (final o in _opciones(g))
                    Builder(builder: (_) {
                      final marcada = elegidas.contains(o['id']);
                      final disponible = o['disponible'] != false;
                      final enGrupo = _opciones(g).where((x) => elegidas.contains(x['id'])).length;
                      final tope = g['tipo'] == 'varias' && g['maximo'] != null && enGrupo >= (g['maximo'] as int) && !marcada;
                      final precio = _n(o['precio_extra']) * conIva;
                      void tocar() => set(() {
                            if (g['tipo'] == 'varias') {
                              marcada ? elegidas.remove(o['id']) : elegidas.add(o['id'] as int);
                            } else {
                              final yaEstaba = marcada;
                              elegidas.removeAll(_opciones(g).map((x) => x['id']));
                              // Tocar de nuevo la elegida la quita (si no es obligatorio).
                              if (!yaEstaba || g['obligatorio'] == true) elegidas.add(o['id'] as int);
                            }
                          });
                      return ListTile(
                        dense: true,
                        enabled: disponible && !tope,
                        onTap: disponible && !tope ? tocar : null,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        tileColor: marcada ? colorResto.withValues(alpha: 0.08) : null,
                        leading: Icon(
                          g['tipo'] == 'varias'
                              ? (marcada ? Icons.check_box : Icons.check_box_outline_blank)
                              : (marcada ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                          color: marcada ? colorResto : AppColors.textMuted,
                        ),
                        title: Text("${o['nombre']}", style: TextStyle(color: AppColors.textStrong, fontSize: 15)),
                        trailing: Text(disponible ? _extra(precio) : "Agotado",
                            style: TextStyle(color: disponible ? AppColors.textStrong : AppColors.textMuted, fontWeight: FontWeight.w600)),
                      );
                    }),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 14, 8, 0),
                  child: TextField(
                    controller: notaCtrl,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: "Nota para la cocina", hintText: "Ej: sin cebolla", border: OutlineInputBorder()),
                  ),
                ),
              ]),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(children: [
                  IconButton.outlined(
                    onPressed: cuantos > 1 ? () => set(() => cuantos--) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text("$cuantos", textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
                  ),
                  IconButton.outlined(onPressed: () => set(() => cuantos++), icon: const Icon(Icons.add)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: colorResto, minimumSize: const Size.fromHeight(48)),
                      onPressed: faltan.isNotEmpty
                          ? null
                          : () {
                              final ids = elegidas.toList();
                              Navigator.pop(ctx, (
                                opciones: ids,
                                texto: textoVariaciones(grupos, ids),
                                extra: extraVariaciones(grupos, ids),
                                nota: notaCtrl.text.trim(),
                                cantidad: cuantos,
                              ));
                            },
                      child: Text(faltan.isNotEmpty ? "Falta: ${faltan.join(', ').toLowerCase()}" : "$textoBoton · ${_colones(unitario * cuantos)}",
                          overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      );
    }),
  );
}

// -------------------------------------------------------------------------
// Pestaña "Variaciones": los platos con un resumen de sus variaciones.

class VariacionesPlatos extends StatefulWidget {
  final Negocio negocio;
  const VariacionesPlatos({super.key, required this.negocio});

  @override
  State<VariacionesPlatos> createState() => _VariacionesPlatosState();
}

class _VariacionesPlatosState extends State<VariacionesPlatos> {
  List<Producto>? _productos;
  Map<String, dynamic> _variaciones = {};
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final rs = await Future.wait([
        ApiService.get('/productos/?negocio=${widget.negocio.id}'),
        ApiService.get('/restaurante/variaciones/?negocio=${widget.negocio.id}'),
      ]);
      final productos = (json.decode(utf8.decode(ApiService.verificar(rs[0]).bodyBytes)) as List).map((j) => Producto.fromJson(j)).toList()
        ..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
      final variaciones = (json.decode(utf8.decode(ApiService.verificar(rs[1]).bodyBytes))['productos'] as Map).cast<String, dynamic>();
      if (mounted) {
        setState(() {
          _productos = productos;
          _variaciones = variaciones;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _productos ??= []);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
      }
    }
  }

  List _grupos(int productoId) => (_variaciones['$productoId']?['grupos'] as List?) ?? [];

  String _resumen(List grupos) => grupos.cast<Map>().map((g) {
        final ops = _opciones(g);
        final muestra = ops.take(3).map((o) => "${o['nombre']}${_n(o['precio_extra']) != 0 ? ' ${_extra(_n(o['precio_extra']))}' : ''}").join(', ');
        return "${g['nombre']}: $muestra${ops.length > 3 ? '…' : ''}";
      }).join('  ·  ');

  Future<void> _abrir(Producto p) async {
    final guardado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ConTemaResto(
          child: EditorVariaciones(producto: p, grupos: _grupos(p.id), otros: _variaciones),
        ),
      ),
    );
    if (guardado == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final productos = _productos;
    if (productos == null) return const Center(child: CircularProgressIndicator());
    final b = _busqueda.toLowerCase();
    final lista = productos.where((p) => b.isEmpty || p.nombre.toLowerCase().contains(b)).toList()
      ..sort((x, y) => (_grupos(x.id).isEmpty ? 1 : 0).compareTo(_grupos(y.id).isEmpty ? 1 : 0));
    final conVariaciones = productos.where((p) => _grupos(p.id).isNotEmpty).length;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            "$conVariaciones de ${productos.length} platos con variaciones. Tamaños, adicionales (extra tocineta, queso...) "
            "o término: al pedir, el mesero elige y el precio se ajusta solo.",
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 10),
          TextField(
            decoration: InputDecoration(
              hintText: "Buscar plato...",
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
            ),
            onChanged: (v) => setState(() => _busqueda = v.trim()),
          ),
          const SizedBox(height: 10),
          for (final p in lista)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: AppColors.surface,
              child: ListTile(
                onTap: () => _abrir(p),
                leading: Icon(_grupos(p.id).isEmpty ? Icons.restaurant_outlined : Icons.tune, color: _grupos(p.id).isEmpty ? AppColors.textMuted : colorResto),
                title: Text(p.nombre, style: TextStyle(color: AppColors.textStrong, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  _grupos(p.id).isEmpty ? "Sin variaciones" : _resumen(_grupos(p.id)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                ),
                trailing: Icon(Icons.chevron_right, color: AppColors.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------------
// Editor de las variaciones de un plato.

/// Plantillas para arrancar rápido un grupo.
const _plantillas = <String, Map<String, dynamic>>{
  'Tamaño': {'tipo': 'una', 'obligatorio': true, 'opciones': ['Pequeño', 'Mediano', 'Grande']},
  'Adicionales': {'tipo': 'varias', 'obligatorio': false, 'opciones': ['Extra tocineta', 'Extra queso', 'Aguacate']},
  'Término': {'tipo': 'una', 'obligatorio': true, 'opciones': ['Medio', 'Tres cuartos', 'Bien cocido']},
  'Acompañamiento': {'tipo': 'una', 'obligatorio': false, 'opciones': ['Papas', 'Ensalada', 'Arroz']},
};

class EditorVariaciones extends StatefulWidget {
  final Producto producto;
  final List grupos;
  // Las variaciones de los demás platos ({id: {nombre, grupos}}), para copiar.
  final Map<String, dynamic> otros;
  const EditorVariaciones({super.key, required this.producto, required this.grupos, required this.otros});

  @override
  State<EditorVariaciones> createState() => _EditorVariacionesState();
}

class _EditorVariacionesState extends State<EditorVariaciones> {
  late List<Map<String, dynamic>> _grupos;
  bool _cambios = false;
  bool _guardando = false;

  double get _iva => widget.producto.impuesto?.porcentaje ?? 0;

  @override
  void initState() {
    super.initState();
    _grupos = widget.grupos.cast<Map>().map(_copia).toList();
  }

  /// Copia editable (sin ids: al guardar se reemplazan todas).
  Map<String, dynamic> _copia(Map g) => {
        'nombre': g['nombre'] ?? '',
        'tipo': g['tipo'] ?? 'una',
        'obligatorio': g['obligatorio'] == true,
        'maximo': g['maximo'],
        'opciones': _opciones(g)
            .map((o) => {'nombre': o['nombre'] ?? '', 'precio_extra': _n(o['precio_extra']), 'disponible': o['disponible'] != false})
            .toList(),
        '_clave': UniqueKey(),
      };

  void _cambiar(VoidCallback f) => setState(() {
        f();
        _cambios = true;
      });

  void _agregarGrupo(String? plantilla) {
    final p = plantilla == null ? null : _plantillas[plantilla];
    _cambiar(() => _grupos.add({
          'nombre': plantilla ?? '',
          'tipo': p?['tipo'] ?? 'una',
          'obligatorio': p?['obligatorio'] ?? false,
          'maximo': null,
          'opciones': [
            for (final nombre in (p?['opciones'] as List? ?? ['']))
              {'nombre': nombre, 'precio_extra': 0.0, 'disponible': true, '_clave': UniqueKey()}
          ],
          '_clave': UniqueKey(),
        }));
  }

  Future<void> _copiarDeOtro() async {
    final otros = widget.otros.entries.where((e) => e.key != '${widget.producto.id}').toList()
      ..sort((a, b) => '${a.value['nombre']}'.toLowerCase().compareTo('${b.value['nombre']}'.toLowerCase()));
    if (otros.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Todavía ningún otro plato tiene variaciones.")));
      return;
    }
    final elegido = await showDialog<MapEntry<String, dynamic>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text("Copiar variaciones de..."),
        children: [
          for (final e in otros)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, e),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text("${e.value['nombre']}"),
                subtitle: Text(((e.value['grupos'] as List).cast<Map>()).map((g) => g['nombre']).join(' · ')),
              ),
            ),
        ],
      ),
    );
    if (elegido == null) return;
    _cambiar(() => _grupos.addAll((elegido.value['grupos'] as List).cast<Map>().map(_copia)));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Se copiaron las variaciones de ${elegido.value['nombre']}. Ajustalas si hace falta y guardá."),
      ));
    }
  }

  /// Cómo le aparece al mesero (con ids de mentira, sin guardar).
  Future<void> _vistaPrevia() async {
    var id = -1;
    final grupos = [
      for (final g in _grupos)
        {
          ...g,
          'opciones': [for (final o in (g['opciones'] as List)) {...o, 'id': id--}],
        }
    ];
    await elegirVariaciones(context,
        plato: widget.producto.nombre, precioBase: widget.producto.precioUnitario, iva: _iva, grupos: grupos, textoBoton: "Vista previa");
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      final datos = [
        for (final g in _grupos)
          {
            'nombre': '${g['nombre']}'.trim(),
            'tipo': g['tipo'],
            'obligatorio': g['obligatorio'],
            'maximo': g['tipo'] == 'varias' ? g['maximo'] : null,
            'opciones': [
              for (final o in (g['opciones'] as List).cast<Map>())
                {'nombre': '${o['nombre']}'.trim(), 'precio_extra': o['precio_extra'], 'disponible': o['disponible']}
            ],
          }
      ];
      ApiService.verificar(await ApiService.put('/restaurante/variaciones/${widget.producto.id}/', {'grupos': datos}));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    }
    if (mounted) setState(() => _guardando = false);
  }

  Future<bool> _salirSinGuardar() async {
    if (!_cambios) return true;
    final salir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Salir sin guardar?"),
        content: const Text("Los cambios a las variaciones de este plato se van a perder."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Seguir editando")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Salir")),
        ],
      ),
    );
    return salir == true;
  }

  Widget _grupo(int i) {
    final g = _grupos[i];
    final opciones = (g['opciones'] as List).cast<Map<String, dynamic>>();
    final varias = g['tipo'] == 'varias';
    return Card(
      key: g['_clave'] as Key,
      margin: const EdgeInsets.only(bottom: 12),
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: TextFormField(
                initialValue: '${g['nombre']}',
                decoration: const InputDecoration(labelText: "Nombre del grupo", hintText: "Ej: Tamaño, Adicionales"),
                style: const TextStyle(fontWeight: FontWeight.w700),
                onChanged: (v) => _cambiar(() => g['nombre'] = v),
              ),
            ),
            IconButton(
              tooltip: "Subir",
              onPressed: i == 0 ? null : () => _cambiar(() => _grupos.insert(i - 1, _grupos.removeAt(i))),
              icon: const Icon(Icons.arrow_upward, size: 20),
            ),
            IconButton(
              tooltip: "Quitar grupo",
              onPressed: () => _cambiar(() => _grupos.removeAt(i)),
              icon: Icon(Icons.delete_outline, color: AppColors.textMuted),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'una', label: Text("Elige una")),
                ButtonSegment(value: 'varias', label: Text("Varias")),
              ],
              selected: {'${g['tipo']}'},
              showSelectedIcon: false,
              onSelectionChanged: (s) => _cambiar(() => g['tipo'] = s.first),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Switch(value: g['obligatorio'] == true, onChanged: (v) => _cambiar(() => g['obligatorio'] = v)),
              Text("Obligatorio", style: TextStyle(color: AppColors.textStrong)),
            ]),
            if (varias)
              DropdownButton<int?>(
                value: g['maximo'] as int?,
                underline: const SizedBox.shrink(),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text("Sin límite")),
                  for (var n = 1; n <= 10; n++) DropdownMenuItem<int?>(value: n, child: Text("Hasta $n")),
                ],
                onChanged: (v) => _cambiar(() => g['maximo'] = v),
              ),
          ]),
          const SizedBox(height: 6),
          for (var j = 0; j < opciones.length; j++)
            Padding(
              key: (opciones[j]['_clave'] ??= UniqueKey()) as Key,
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    initialValue: '${opciones[j]['nombre']}',
                    decoration: InputDecoration(labelText: "Opción ${j + 1}", isDense: true),
                    onChanged: (v) => _cambiar(() => opciones[j]['nombre'] = v),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    initialValue: _n(opciones[j]['precio_extra']) == 0 ? '' : _n(opciones[j]['precio_extra']).toStringAsFixed(0),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: InputDecoration(
                      labelText: "Precio extra",
                      hintText: "0",
                      prefixText: "₡ ",
                      isDense: true,
                      helperText: _n(opciones[j]['precio_extra']) != 0 && _iva > 0
                          ? "Con IVA ${_extra(_n(opciones[j]['precio_extra']) * (1 + _iva / 100))}"
                          : null,
                    ),
                    onChanged: (v) => _cambiar(() => opciones[j]['precio_extra'] = _n(v)),
                  ),
                ),
                IconButton(
                  tooltip: opciones[j]['disponible'] == false ? "Agotado: tocá para volver a ofrecerlo" : "Marcar agotado",
                  onPressed: () => _cambiar(() => opciones[j]['disponible'] = opciones[j]['disponible'] == false),
                  icon: Icon(
                    opciones[j]['disponible'] == false ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: opciones[j]['disponible'] == false ? colorResto : AppColors.textMuted,
                    size: 20,
                  ),
                ),
                IconButton(
                  tooltip: "Quitar opción",
                  onPressed: opciones.length == 1 ? null : () => _cambiar(() => opciones.removeAt(j)),
                  icon: Icon(Icons.close, size: 20, color: AppColors.textMuted),
                ),
              ]),
            ),
          TextButton.icon(
            onPressed: () => _cambiar(() => opciones.add({'nombre': '', 'precio_extra': 0.0, 'disponible': true, '_clave': UniqueKey()})),
            icon: const Icon(Icons.add, size: 18),
            label: const Text("Agregar opción"),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.producto;
    return PopScope(
      canPop: !_cambios,
      onPopInvokedWithResult: (salio, _) async {
        if (salio) return;
        if (await _salirSinGuardar() && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.surfaceSubtle,
        appBar: AppBar(
          title: Text("Variaciones · ${p.nombre}"),
          actions: [const BotonCalculadora(), 
            IconButton(tooltip: "Así lo ve el mesero", onPressed: _grupos.isEmpty ? null : _vistaPrevia, icon: const Icon(Icons.visibility_outlined)),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            Text(
              "Precio del plato: ${_colones(p.precioUnitario)} sin IVA${_iva > 0 ? ' (${_colones(p.precioUnitario * (1 + _iva / 100))} con IVA)' : ''}. "
              "El precio extra de cada opción va sin IVA y se le suma al plato; lleva el mismo IVA del plato.",
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _grupos.length; i++) _grupo(i),
            if (_grupos.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text("Este plato no tiene variaciones. Agregá un grupo o copiá las de otro plato.",
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
              ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final nombre in _plantillas.keys)
                ActionChip(avatar: const Icon(Icons.add, size: 16), label: Text(nombre), onPressed: () => _agregarGrupo(nombre)),
              ActionChip(avatar: const Icon(Icons.add, size: 16), label: const Text("Otro grupo"), onPressed: () => _agregarGrupo(null)),
              ActionChip(avatar: const Icon(Icons.copy_all_outlined, size: 16), label: const Text("Copiar de otro plato"), onPressed: _copiarDeOtro),
            ]),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: colorResto, minimumSize: const Size.fromHeight(48)),
              onPressed: _guardando ? null : _guardar,
              icon: const Icon(Icons.check),
              label: Text(_guardando ? "Guardando..." : "Guardar variaciones"),
            ),
          ),
        ),
      ),
    );
  }
}
