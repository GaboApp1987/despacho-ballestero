import 'dart:convert';

import 'package:flutter/material.dart';

import 'api_service.dart';
import 'formato.dart';
import 'negocio.dart';
import 'theme/app_theme.dart';

/// Órdenes de producción (gestion/produccion.py): para quien fabrica por
/// lotes y guarda el producto antes de venderlo. El lote gasta los insumos
/// de la receta y suma producto terminado al costo real; desde ahí, al
/// vender ese producto se rebaja el producto y no los insumos.

double _num(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;
String _cant(double c) => formatearNumero(c, decimales: c % 1 == 0 ? 0 : 3);
double? _leer(String t) => double.tryParse(t.trim().replaceAll(',', '.'));
String _fecha(DateTime d) => "${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}";
String _codigo(Map o) => "OP-${(o['numero'] ?? 0).toString().padLeft(5, '0')}";

String textoEstadoLote(String e) => const {'borrador': 'Borrador', 'terminada': 'Terminado', 'anulada': 'Anulado'}[e] ?? e;
Color colorEstadoLote(String e) => switch (e) {
      'terminada' => Colors.green,
      'anulada' => Colors.red,
      _ => Colors.grey,
    };

class _Chip extends StatelessWidget {
  final String estado;
  const _Chip(this.estado);

  @override
  Widget build(BuildContext context) {
    final c = colorEstadoLote(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(textoEstadoLote(estado), style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w700)),
    );
  }
}

class ProduccionTab extends StatefulWidget {
  final Negocio negocio;
  const ProduccionTab({super.key, required this.negocio});

  @override
  State<ProduccionTab> createState() => _ProduccionTabState();
}

class _ProduccionTabState extends State<ProduccionTab> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _lotes = [];
  // Productos con receta (de /recetas/), para elegir qué producir.
  List<Map<String, dynamic>> _recetas = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final r = await Future.wait([
        ApiService.get('/produccion/?negocio=${widget.negocio.id}'),
        ApiService.get('/recetas/?negocio=${widget.negocio.id}'),
      ]);
      if (r[0].statusCode != 200) throw Exception(ApiService.mensajeError(r[0]));
      if (!mounted) return;
      setState(() {
        _lotes = (json.decode(utf8.decode(r[0].bodyBytes)) as List).cast<Map<String, dynamic>>();
        _recetas = r[1].statusCode == 200
            ? (json.decode(utf8.decode(r[1].bodyBytes)) as List)
                .cast<Map<String, dynamic>>()
                .where((p) => (p['items'] as List? ?? []).isNotEmpty)
                .toList()
            : [];
        _error = null;
        _cargando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ApiService.textoError(e);
          _cargando = false;
        });
      }
    }
  }

  Future<void> _dejarDeProducir(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Dejar de producir por lotes"),
        content: Text("Desde ahora, al vender ${p['nombre']} se rebajan otra vez los insumos de la receta. "
            "Lo que quede producido sigue en existencia."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Volver")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Cambiar")),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await ApiService.patch('/productos/${p['producto']}/', {'produccion_por_lote': false});
      if (r.statusCode != 200) throw Exception(ApiService.mensajeError(r));
      _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo cambiar: ${ApiService.textoError(e)}")));
      }
    }
  }

  Future<void> _nuevoLote() async {
    if (_recetas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Primero armá la receta del producto en la pestaña Insumos y recetas.")));
      return;
    }
    int? producto = _recetas.first['producto'];
    final cantidad = TextEditingController();
    final notas = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final elegido = _recetas.firstWhere((p) => p['producto'] == producto);
          return AlertDialog(
            title: const Text("Nuevo lote"),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  DropdownButtonFormField<int>(
                    initialValue: producto,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: "Qué se produce", border: OutlineInputBorder()),
                    items: [for (final p in _recetas) DropdownMenuItem(value: p['producto'] as int, child: Text(p['nombre'] ?? ''))],
                    onChanged: (v) => setD(() => producto = v),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: cantidad,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Cuántas unidades", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notas,
                    decoration: const InputDecoration(labelText: "Notas (opcional)", border: OutlineInputBorder()),
                  ),
                  if (elegido['por_lote'] != true) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "Al terminar el primer lote, ${elegido['nombre']} pasa a venderse desde lo producido: "
                        "al facturarlo se rebaja el producto y ya no los insumos de la receta.",
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Crear lote")),
            ],
          );
        },
      ),
    );
    final unidades = int.tryParse(cantidad.text.trim());
    if (ok != true || producto == null || unidades == null || unidades <= 0) return;
    try {
      final r = await ApiService.post('/produccion/', {
        'negocio': widget.negocio.id,
        'producto': producto,
        'cantidad_planificada': unidades,
        'notas': notas.text.trim(),
      });
      if (r.statusCode != 201) throw Exception(ApiService.mensajeError(r));
      final lote = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => DetalleLoteScreen(loteId: lote['id'])));
      _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("No se pudo crear el lote: ${ApiService.textoError(e)}")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Row(children: [
            Expanded(
              child: Text(
                "Para lo que se fabrica por lotes y se guarda antes de venderlo.",
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(onPressed: _nuevoLote, icon: const Icon(Icons.add), label: const Text("Nuevo lote")),
          ]),
          const SizedBox(height: 12),
          if (_cargando)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Padding(padding: const EdgeInsets.all(24), child: Text("No se pudieron cargar los lotes: $_error"))
          else if (_lotes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(children: [
                Icon(Icons.precision_manufacturing_outlined, size: 48, color: AppColors.textMuted),
                const SizedBox(height: 8),
                Text("Todavía no hay lotes.", style: TextStyle(color: AppColors.textMuted)),
                const SizedBox(height: 4),
                Text(
                  "Un restaurante no lo necesita: ahí la receta rebaja los insumos al vender.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ]),
            )
          else
            for (final l in _lotes)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => DetalleLoteScreen(loteId: l['id'])));
                    _cargar();
                  },
                  title: Text("${_codigo(l)} · ${l['nombre_producto'] ?? ''}", style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text([
                      if (DateTime.tryParse(l['fecha']?.toString() ?? '') != null)
                        _fecha(DateTime.parse(l['fecha'].toString()).toLocal()),
                      l['estado'] == 'terminada'
                          ? "salieron ${l['cantidad_producida']} de ${l['cantidad_planificada']}"
                          : "${l['cantidad_planificada']} unidades",
                    ].join(' · ')),
                    const SizedBox(height: 4),
                    _Chip(l['estado'] ?? 'borrador'),
                  ]),
                  trailing: Text(
                    formatearColones(_num(l['estado'] == 'terminada' ? l['costo_total'] : l['costo_estimado'])),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
          if (!_cargando && _recetas.any((p) => p['por_lote'] == true)) ...[
            const SizedBox(height: 16),
            Text("Se venden desde lo producido", style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text("Al venderlos se rebaja el producto, no los insumos.",
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            for (final p in _recetas.where((p) => p['por_lote'] == true))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(p['nombre'] ?? ''),
                trailing: TextButton(onPressed: () => _dejarDeProducir(p), child: const Text("Dejar de producir")),
              ),
          ],
        ],
      ),
    );
  }
}

class DetalleLoteScreen extends StatefulWidget {
  final int loteId;
  const DetalleLoteScreen({super.key, required this.loteId});

  @override
  State<DetalleLoteScreen> createState() => _DetalleLoteScreenState();
}

class _DetalleLoteScreenState extends State<DetalleLoteScreen> {
  Map<String, dynamic>? _lote;
  String? _error;
  bool _ocupado = false;
  final _producida = TextEditingController();
  final _otros = TextEditingController();
  final _detalleOtros = TextEditingController();
  final Map<int, TextEditingController> _reales = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _usar(Map<String, dynamic> lote) {
    _lote = lote;
    _producida.text = '${lote['cantidad_producida'] ?? lote['cantidad_planificada']}';
    final otros = _num(lote['otros_costos']);
    _otros.text = otros > 0 ? otros.toStringAsFixed(2) : '';
    _detalleOtros.text = (lote['detalle_otros_costos'] ?? '').toString();
    _reales
      ..clear()
      ..addAll({
        for (final c in (lote['consumos'] as List).cast<Map<String, dynamic>>())
          c['insumo'] as int: TextEditingController(text: _cant(_num(c['cantidad_real'])))
      });
  }

  Future<void> _cargar() async {
    try {
      final r = await ApiService.get('/produccion/${widget.loteId}/');
      if (r.statusCode != 200) throw Exception(ApiService.mensajeError(r));
      if (mounted) setState(() => _usar(json.decode(utf8.decode(r.bodyBytes))));
    } catch (e) {
      if (mounted) setState(() => _error = ApiService.textoError(e));
    }
  }

  void _aviso(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  double get _costoEnPantalla {
    var total = 0.0;
    for (final c in (_lote!['consumos'] as List).cast<Map<String, dynamic>>()) {
      final real = _leer(_reales[c['insumo']]?.text ?? '') ?? 0;
      total += real * _num(c['costo_actual']);
    }
    return total + (_leer(_otros.text) ?? 0);
  }

  Future<void> _terminar() async {
    final producida = int.tryParse(_producida.text.trim());
    if (producida == null || producida <= 0) {
      _aviso("Escribí cuántas unidades salieron (enteras).");
      return;
    }
    final faltan = [
      for (final c in (_lote!['consumos'] as List).cast<Map<String, dynamic>>())
        if ((_leer(_reales[c['insumo']]!.text) ?? 0) > _num(c['stock'])) c['nombre']
    ];
    final costo = _costoEnPantalla;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Terminar lote"),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Entran $producida de ${_lote!['nombre_producto']} a ${formatearColones(costo / producida)} cada una "
              "(${formatearColones(costo)} el lote) y salen los insumos usados."),
          if (faltan.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              "Según el sistema no alcanza ${faltan.join(', ')}: la existencia va a quedar en negativo. "
              "Si sí lo tenés, registrá la compra o el conteo.",
              style: const TextStyle(color: Colors.orange),
            ),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Volver")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Terminar")),
        ],
      ),
    );
    if (ok != true) return;
    await _accion('terminar', {
      'cantidad_producida': producida,
      'otros_costos': (_leer(_otros.text) ?? 0).toStringAsFixed(2),
      'detalle_otros_costos': _detalleOtros.text.trim(),
      'consumos': [
        for (final e in _reales.entries) {'insumo': e.key, 'cantidad_real': (_leer(e.value.text) ?? 0).toStringAsFixed(3)}
      ],
    });
  }

  Future<void> _accion(String ruta, [Map<String, dynamic> body = const {}]) async {
    setState(() => _ocupado = true);
    try {
      final r = await ApiService.post('/produccion/${widget.loteId}/$ruta/', body);
      if (r.statusCode != 200) throw Exception(ApiService.mensajeError(r));
      if (mounted) setState(() => _usar(json.decode(utf8.decode(r.bodyBytes))));
    } catch (e) {
      if (mounted) _aviso(ApiService.textoError(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _anular() async {
    final terminado = _lote!['estado'] == 'terminada';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Anular lote"),
        content: Text(terminado
            ? "Los insumos vuelven a la existencia y se rebajan las ${_lote!['cantidad_producida']} unidades del producto."
            : "El lote queda anulado sin mover nada."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Volver")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Anular")),
        ],
      ),
    );
    if (ok == true) _accion('anular');
  }

  Future<void> _borrar() async {
    try {
      final r = await ApiService.delete('/produccion/${widget.loteId}/');
      if (r.statusCode != 204) throw Exception(ApiService.mensajeError(r));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _aviso(ApiService.textoError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _lote;
    final borrador = l?['estado'] == 'borrador';
    return Scaffold(
      appBar: AppBar(
        title: Text(l == null ? "Lote" : "${_codigo(l)} · ${l['nombre_producto']}"),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
        actions: [
          if (l != null && l['estado'] != 'anulada')
            PopupMenuButton<String>(
              onSelected: (v) => v == 'borrar' ? _borrar() : _anular(),
              itemBuilder: (_) => [
                if (borrador) const PopupMenuItem(value: 'borrar', child: Text("Borrar")),
                const PopupMenuItem(value: 'anular', child: Text("Anular")),
              ],
            ),
        ],
      ),
      body: l == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              if (_ocupado) const LinearProgressIndicator(),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text("${l['nombre_producto']}",
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      ),
                      _Chip(l['estado']),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                      l['estado'] == 'terminada'
                          ? "Salieron ${l['cantidad_producida']} de ${l['cantidad_planificada']} planeadas"
                          : "Planeadas: ${l['cantidad_planificada']} · hay ${l['stock_producto']} en existencia",
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                    if ((l['notas'] ?? '').toString().isNotEmpty) ...[const SizedBox(height: 6), Text(l['notas'])],
                    if (l['estado'] == 'terminada') ...[
                      const SizedBox(height: 10),
                      _dato("Costo del lote", formatearColones(_num(l['costo_total']))),
                      if (_num(l['otros_costos']) > 0)
                        _dato("  incluye ${(l['detalle_otros_costos'] ?? '').toString().isEmpty ? 'otros costos' : l['detalle_otros_costos']}",
                            formatearColones(_num(l['otros_costos']))),
                      _dato("Costo por unidad", formatearColones(_num(l['costo_unitario']))),
                      if (l['tiene_asiento'] == true)
                        Text("Ya tiene su asiento contable.", style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              Text(borrador ? "Insumos: lo que manda la receta y lo que se usó" : "Insumos usados",
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              for (final c in (l['consumos'] as List).cast<Map<String, dynamic>>())
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c['nombre'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            [
                              "Receta: ${_cant(_num(c['cantidad_teorica']))} ${c['unidad']}",
                              if (borrador) "hay ${_cant(_num(c['stock']))}",
                              "${formatearColones(_num(borrador ? c['costo_actual'] : c['costo_unitario']))}/${c['unidad']}",
                            ].join(' · '),
                            style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                          ),
                        ]),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 110,
                        child: borrador
                            ? TextField(
                                controller: _reales[c['insumo']],
                                onChanged: (_) => setState(() {}),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(labelText: "Se usó", suffixText: c['unidad'], isDense: true),
                              )
                            : Text("${_cant(_num(c['cantidad_real']))} ${c['unidad']}",
                                textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ),
                ),
              if (borrador) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _producida,
                  onChanged: (_) => setState(() {}),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Unidades que salieron",
                    helperText: "Si salieron menos (merma del proceso), el costo por unidad sube.",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _otros,
                      onChanged: (_) => setState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: "Otros costos", prefixText: "₡ ", border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _detalleOtros,
                      decoration: const InputDecoration(
                          labelText: "De qué (opcional)", hintText: "Mano de obra, gas...", border: OutlineInputBorder()),
                    ),
                  ),
                ]),
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4),
                  child: Text("Lo que no es insumo y querés que forme parte del costo del producto.",
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ),
                const SizedBox(height: 12),
                Builder(builder: (_) {
                  final costo = _costoEnPantalla;
                  final n = int.tryParse(_producida.text.trim()) ?? 0;
                  return Column(children: [
                    _dato("Costo del lote (costos de hoy)", formatearColones(costo)),
                    if (n > 0) _dato("Costo por unidad", formatearColones(costo / n)),
                  ]);
                }),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _ocupado ? null : _terminar,
                  style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                  icon: const Icon(Icons.check),
                  label: const Text("TERMINAR LOTE"),
                ),
              ],
            ]),
    );
  }
}

Widget _dato(String etiqueta, String valor) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(etiqueta)),
        Text(valor, style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
    );
