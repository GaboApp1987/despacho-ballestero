import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_service.dart';
import 'formato.dart';
import 'negocio.dart';
import 'theme/app_theme.dart';

/// Insumos (arroz, pollo, vasos...) y recetas de los productos: al vender se
/// descuentan solos (ver gestion/recetas.py). En tablet/compu se ven las dos
/// listas lado a lado; en celular se cambia entre una y otra.
class InsumosRecetas extends StatefulWidget {
  final Negocio negocio;
  const InsumosRecetas({super.key, required this.negocio});

  @override
  State<InsumosRecetas> createState() => _InsumosRecetasState();
}

const _unidades = {'kg': 'kg', 'g': 'g', 'l': 'L', 'ml': 'ml', 'unid': 'unidad'};

double _num(dynamic v) => double.tryParse('${v ?? 0}') ?? 0;

String _cantidad(double v) {
  final s = v.toStringAsFixed(3);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

class _InsumosRecetasState extends State<InsumosRecetas> {
  List<Map<String, dynamic>>? _insumos;
  List<Map<String, dynamic>>? _recetas;
  String _vista = 'insumos';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _aviso(String texto) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _cargar() async {
    try {
      final rs = await Future.wait([
        ApiService.get('/insumos/?negocio=${widget.negocio.id}'),
        ApiService.get('/recetas/?negocio=${widget.negocio.id}'),
      ]);
      List<Map<String, dynamic>> lista(int i) =>
          rs[i].statusCode == 200 ? (json.decode(utf8.decode(rs[i].bodyBytes)) as List).cast<Map<String, dynamic>>() : [];
      if (mounted) {
        setState(() {
          _insumos = lista(0);
          _recetas = lista(1);
        });
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------- Insumos

  Future<void> _editarInsumo([Map<String, dynamic>? insumo]) async {
    final nombre = TextEditingController(text: insumo?['nombre'] ?? '');
    final costo = TextEditingController(text: insumo == null ? '' : _cantidad(_num(insumo['costo_unitario'])));
    final minimo = TextEditingController(text: insumo == null ? '' : _cantidad(_num(insumo['minimo'])));
    final inicial = TextEditingController();
    var unidad = (insumo?['unidad'] ?? 'kg') as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(insumo == null ? "Nuevo insumo" : "Editar insumo"),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: nombre, autofocus: true, textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: "Nombre", hintText: "Arroz, pollo, vasos...", border: OutlineInputBorder())),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: unidad,
                  decoration: const InputDecoration(labelText: "Se mide en", border: OutlineInputBorder()),
                  items: [for (final u in _unidades.entries) DropdownMenuItem(value: u.key, child: Text(u.value))],
                  onChanged: (v) => setD(() => unidad = v ?? unidad),
                ),
                const SizedBox(height: 10),
                TextField(controller: costo, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: "Costo por ${_unidades[unidad]}", prefixText: "₡ ", border: const OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: minimo, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: "Avisar cuando queden", suffixText: _unidades[unidad], border: const OutlineInputBorder())),
                if (insumo == null) ...[
                  const SizedBox(height: 10),
                  TextField(controller: inicial, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: "Cuánto hay ahora (opcional)", suffixText: _unidades[unidad], border: const OutlineInputBorder())),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Guardar")),
          ],
        ),
      ),
    );
    if (ok != true || nombre.text.trim().isEmpty) return;
    final datos = {
      'negocio': widget.negocio.id,
      'nombre': nombre.text.trim(),
      'unidad': unidad,
      'costo_unitario': _num(costo.text.replaceAll(',', '.')),
      'minimo': _num(minimo.text.replaceAll(',', '.')),
    };
    final r = insumo == null ? await ApiService.post('/insumos/', datos) : await ApiService.patch('/insumos/${insumo['id']}/', datos);
    if (r.statusCode >= 300) {
      if (mounted) _aviso("No se pudo guardar: ${ApiService.mensajeError(r)}");
      return;
    }
    final cuanto = _num(inicial.text.replaceAll(',', '.'));
    if (insumo == null && cuanto > 0) {
      final id = json.decode(utf8.decode(r.bodyBytes))['id'];
      await ApiService.post('/insumos/$id/movimiento/', {'tipo': 'entrada', 'cantidad': cuanto, 'nota': 'Existencia inicial'});
    }
    _cargar();
  }

  Future<void> _movimiento(Map<String, dynamic> insumo, String tipo) async {
    final cantidad = TextEditingController();
    final costo = TextEditingController();
    final nota = TextEditingController();
    final unidad = _unidades[insumo['unidad']] ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tipo == 'entrada' ? "Entrada de ${insumo['nombre']}" : "Conteo de ${insumo['nombre']}"),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Hay ${_cantidad(_num(insumo['stock']))} $unidad según el sistema.", style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 12),
            TextField(
              controller: cantidad,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,-]'))],
              decoration: InputDecoration(
                labelText: tipo == 'entrada' ? "Cuánto entró" : "Cuánto hay contado",
                suffixText: unidad,
                border: const OutlineInputBorder(),
              ),
            ),
            if (tipo == 'entrada') ...[
              const SizedBox(height: 10),
              TextField(
                controller: costo,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: "Costo por $unidad (opcional)", prefixText: "₡ ",
                    helperText: "Si lo ponés, el costo se promedia con lo que ya había.", border: const OutlineInputBorder()),
              ),
            ],
            const SizedBox(height: 10),
            TextField(controller: nota, maxLength: 200,
                decoration: InputDecoration(labelText: "Nota (opcional)", hintText: tipo == 'entrada' ? "Ej: compra en el mercado" : "Ej: conteo del viernes", border: const OutlineInputBorder())),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Guardar")),
        ],
      ),
    );
    if (ok != true || cantidad.text.trim().isEmpty) return;
    final valor = _num(cantidad.text.replaceAll(',', '.'));
    final r = await ApiService.post('/insumos/${insumo['id']}/movimiento/', {
      'tipo': tipo,
      if (tipo == 'entrada') 'cantidad': valor else 'stock': valor,
      if (tipo == 'entrada' && costo.text.trim().isNotEmpty) 'costo_unitario': _num(costo.text.replaceAll(',', '.')),
      'nota': nota.text.trim(),
    });
    if (r.statusCode != 200 && mounted) _aviso(ApiService.mensajeError(r));
    _cargar();
  }

  Future<void> _historial(Map<String, dynamic> insumo) async {
    final r = await ApiService.get('/insumos/${insumo['id']}/movimientos/');
    if (r.statusCode != 200 || !mounted) return;
    final movs = (json.decode(utf8.decode(r.bodyBytes)) as List).cast<Map<String, dynamic>>();
    final unidad = _unidades[insumo['unidad']] ?? '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Historial · ${insumo['nombre']}"),
        content: SizedBox(
          width: 440,
          height: 380,
          child: movs.isEmpty
              ? Center(child: Text("Sin movimientos todavía.", style: TextStyle(color: AppColors.textMuted)))
              : ListView.separated(
                  itemCount: movs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final m = movs[i];
                    final c = _num(m['cantidad']);
                    return ListTile(
                      dense: true,
                      title: Text("${m['tipo_texto']}${(m['nota'] ?? '').toString().isEmpty ? '' : ' · ${m['nota']}'}"),
                      subtitle: Text("${(m['fecha'] ?? '').toString().split('T').first}${(m['usuario'] ?? '').toString().isEmpty ? '' : ' · ${m['usuario']}'}"),
                      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text("${c > 0 ? '+' : ''}${_cantidad(c)} $unidad",
                            style: TextStyle(fontWeight: FontWeight.w700, color: c >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626))),
                        Text("Quedó ${_cantidad(_num(m['stock_resultante']))}", style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      ]),
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cerrar"))],
      ),
    );
  }

  Future<void> _quitarInsumo(Map<String, dynamic> insumo) async {
    final r = await ApiService.delete('/insumos/${insumo['id']}/');
    if (r.statusCode >= 300 && mounted) _aviso(ApiService.mensajeError(r));
    _cargar();
  }

  Widget _listaInsumos() {
    final insumos = _insumos!;
    final bajos = insumos.where((i) => i['por_agotarse'] == true).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(children: [
          Expanded(
            child: Text(bajos > 0 ? "$bajos por agotarse" : "${insumos.length} insumos",
                style: TextStyle(color: bajos > 0 ? const Color(0xFFB45309) : AppColors.textMuted, fontWeight: bajos > 0 ? FontWeight.w700 : null)),
          ),
          FilledButton.icon(onPressed: () => _editarInsumo(), icon: const Icon(Icons.add, size: 18), label: const Text("Agregar insumo")),
        ]),
        const SizedBox(height: 10),
        if (insumos.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text("Agregá lo que usás para preparar: arroz, frijoles, pollo, vasos...",
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
          ),
        for (final i in insumos)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: AppColors.surface,
            child: ListTile(
              leading: Icon(
                _num(i['stock']) < 0 ? Icons.error_outline : (i['por_agotarse'] == true ? Icons.warning_amber_rounded : Icons.inventory_2_outlined),
                color: _num(i['stock']) < 0 ? const Color(0xFFDC2626) : (i['por_agotarse'] == true ? const Color(0xFFF59E0B) : AppColors.textMuted),
              ),
              title: Text(i['nombre'], style: TextStyle(color: AppColors.textStrong, fontWeight: FontWeight.w600)),
              subtitle: Text(
                "${formatearColones(_num(i['costo_unitario']), decimales: 0)} / ${_unidades[i['unidad']]}"
                "${(i['en_recetas'] ?? 0) > 0 ? ' · en ${i['en_recetas']} receta${i['en_recetas'] == 1 ? '' : 's'}' : ''}",
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
              ),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text("${_cantidad(_num(i['stock']))} ${_unidades[i['unidad']]}",
                    style: TextStyle(fontWeight: FontWeight.w800, color: _num(i['stock']) < 0 ? const Color(0xFFDC2626) : AppColors.textStrong)),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    switch (v) {
                      case 'entrada': _movimiento(i, 'entrada');
                      case 'ajuste': _movimiento(i, 'ajuste');
                      case 'historial': _historial(i);
                      case 'editar': _editarInsumo(i);
                      case 'quitar': _quitarInsumo(i);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'entrada', child: Text("Registrar entrada / compra")),
                    PopupMenuItem(value: 'ajuste', child: Text("Ajustar por conteo")),
                    PopupMenuItem(value: 'historial', child: Text("Ver historial")),
                    PopupMenuItem(value: 'editar', child: Text("Editar")),
                    PopupMenuItem(value: 'quitar', child: Text("Quitar")),
                  ],
                ),
              ]),
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------- Recetas

  Future<void> _editarReceta(Map<String, dynamic> receta) async {
    final insumos = _insumos ?? [];
    if (insumos.isEmpty) {
      _aviso("Primero agregá insumos.");
      return;
    }
    final filas = [
      for (final it in (receta['items'] as List).cast<Map<String, dynamic>>())
        (insumo: it['insumo'] as int, ctrl: TextEditingController(text: _cantidad(_num(it['cantidad'])))),
    ];
    final porId = {for (final i in insumos) i['id'] as int: i};
    final precio = _num(receta['precio']);
    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final costo = filas.fold(0.0, (s, f) => s + _num(f.ctrl.text.replaceAll(',', '.')) * _num(porId[f.insumo]?['costo_unitario']));
        final margen = precio > 0 && filas.isNotEmpty ? (precio - costo) / precio * 100 : null;
        final usados = filas.map((f) => f.insumo).toSet();
        final libres = insumos.where((i) => !usados.contains(i['id'])).toList();
        return AlertDialog(
          title: Text("Receta · ${receta['nombre']}"),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Cuánto lleva UNA unidad de este producto.", style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              const SizedBox(height: 10),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final f in filas)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Expanded(child: Text(porId[f.insumo]?['nombre'] ?? '?', style: TextStyle(color: AppColors.textStrong, fontWeight: FontWeight.w600))),
                        SizedBox(
                          width: 130,
                          child: TextField(
                            controller: f.ctrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setD(() {}),
                            decoration: InputDecoration(isDense: true, suffixText: _unidades[porId[f.insumo]?['unidad']], border: const OutlineInputBorder()),
                          ),
                        ),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => setD(() => filas.remove(f))),
                      ]),
                    ),
                ]),
              ),
              if (libres.isNotEmpty)
                PopupMenuButton<int>(
                  onSelected: (id) => setD(() => filas.add((insumo: id, ctrl: TextEditingController()))),
                  itemBuilder: (_) => [for (final i in libres) PopupMenuItem(value: i['id'] as int, child: Text(i['nombre']))],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.add, color: AppColors.primary, size: 18),
                      const SizedBox(width: 4),
                      Text("Agregar insumo", style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              const Divider(),
              Wrap(spacing: 16, runSpacing: 4, children: [
                Text("Costo: ${formatearColones(costo)}", style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong)),
                Text("Precio: ${formatearColones(precio)}", style: TextStyle(color: AppColors.textMuted)),
                if (margen != null)
                  Text("Margen: ${margen.toStringAsFixed(1)}%",
                      style: TextStyle(fontWeight: FontWeight.w700, color: margen < 30 ? const Color(0xFFDC2626) : const Color(0xFF16A34A))),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Guardar")),
          ],
        );
      }),
    );
    if (guardar != true) return;
    final r = await ApiService.put('/recetas/${receta['producto']}/', {
      'items': [
        for (final f in filas)
          if (_num(f.ctrl.text.replaceAll(',', '.')) > 0) {'insumo': f.insumo, 'cantidad': _num(f.ctrl.text.replaceAll(',', '.'))},
      ],
    });
    if (r.statusCode != 200 && mounted) _aviso("No se pudo guardar: ${ApiService.mensajeError(r)}");
    _cargar();
  }

  Widget _listaRecetas() {
    final recetas = _recetas!;
    final conReceta = recetas.where((r) => (r['items'] as List).isNotEmpty).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text("$conReceta de ${recetas.length} productos con receta. Al venderlos se descuentan sus insumos.",
            style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        const SizedBox(height: 10),
        for (final r in recetas)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: AppColors.surface,
            child: ListTile(
              onTap: () => _editarReceta(r),
              leading: Icon((r['items'] as List).isEmpty ? Icons.receipt_outlined : Icons.menu_book_outlined, color: AppColors.textMuted),
              title: Text(r['nombre'], style: TextStyle(color: AppColors.textStrong, fontWeight: FontWeight.w600)),
              subtitle: Text(
                (r['items'] as List).isEmpty
                    ? "Sin receta"
                    : (r['items'] as List).map((i) => "${_cantidad(_num(i['cantidad']))} ${_unidades[i['unidad']]} ${i['nombre']}").join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
              ),
              trailing: (r['items'] as List).isEmpty
                  ? Icon(Icons.chevron_right, color: AppColors.textMuted)
                  : Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(formatearColones(_num(r['costo']), decimales: 0), style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong)),
                      if (r['margen'] != null)
                        Text("${_num(r['margen']).toStringAsFixed(0)}% margen",
                            style: TextStyle(fontSize: 11.5, color: _num(r['margen']) < 30 ? const Color(0xFFDC2626) : const Color(0xFF16A34A))),
                    ]),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_insumos == null || _recetas == null) return const Center(child: CircularProgressIndicator());
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 900) {
        Widget titulo(String t) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Text(t, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textStrong)),
            );
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(children: [titulo("Insumos"), Expanded(child: _listaInsumos())])),
          VerticalDivider(width: 1, color: AppColors.border),
          Expanded(child: Column(children: [titulo("Recetas"), Expanded(child: _listaRecetas())])),
        ]);
      }
      return Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'insumos', icon: Icon(Icons.inventory_2_outlined), label: Text("Insumos")),
              ButtonSegment(value: 'recetas', icon: Icon(Icons.menu_book_outlined), label: Text("Recetas")),
            ],
            selected: {_vista},
            onSelectionChanged: (s) => setState(() => _vista = s.first),
          ),
        ),
        Expanded(child: _vista == 'insumos' ? _listaInsumos() : _listaRecetas()),
      ]);
    });
  }
}
