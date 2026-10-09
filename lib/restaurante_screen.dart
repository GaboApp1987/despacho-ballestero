import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';

import 'api_service.dart';
import 'formato.dart';
import 'negocio.dart';
import 'restaurante_orden_screen.dart';
import 'theme/app_theme.dart';

/// Módulo de restaurante: el salón (mesas con su cuenta abierta y pedidos
/// para llevar), la pantalla de cocina y la configuración de mesas. Se
/// actualiza solo cada pocos segundos para que varios meseros y la cocina
/// vean lo mismo. Funciona igual en celular y en tablet.
class RestauranteScreen extends StatefulWidget {
  final Negocio negocio;
  final String? rolEmpleado;
  const RestauranteScreen({super.key, required this.negocio, this.rolEmpleado});

  @override
  State<RestauranteScreen> createState() => _RestauranteScreenState();
}

const colorLibre = Color(0xFF94A3B8);
const colorOcupada = Color(0xFF3B82F6);
const colorListo = Color(0xFF16A34A);
const colorCuenta = Color(0xFFF59E0B);

String minutosDesde(String? iso) {
  final fecha = DateTime.tryParse(iso ?? '');
  if (fecha == null) return '';
  final m = DateTime.now().difference(fecha.toLocal()).inMinutes;
  if (m < 1) return 'recién';
  if (m < 60) return '$m min';
  return '${m ~/ 60} h ${m % 60} min';
}

class _RestauranteScreenState extends State<RestauranteScreen> with SingleTickerProviderStateMixin {
  String _cocina = 'pantalla';
  bool _cargado = false;

  bool get _esCajero => widget.rolEmpleado == 'cajero';
  bool get _conPantallaCocina => _cocina != 'impresora';

  @override
  void initState() {
    super.initState();
    _cargarConfig();
  }

  Future<void> _cargarConfig() async {
    try {
      final r = await ApiService.get('/restaurante/config/?negocio=${widget.negocio.id}');
      if (r.statusCode == 200) _cocina = (json.decode(utf8.decode(r.bodyBytes))['cocina'] ?? 'pantalla') as String;
    } catch (_) {}
    if (mounted) setState(() => _cargado = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_cargado) return const Center(child: CircularProgressIndicator());
    final pestanas = [
      (const Tab(icon: Icon(Icons.table_restaurant_outlined, size: 20), text: "Salón"), _Salon(negocio: widget.negocio)),
      if (_conPantallaCocina) (const Tab(icon: Icon(Icons.soup_kitchen_outlined, size: 20), text: "Cocina"), _Cocina(negocio: widget.negocio)),
      if (!_esCajero)
        (
          const Tab(icon: Icon(Icons.tune, size: 20), text: "Mesas"),
          _ConfigMesas(negocio: widget.negocio, cocina: _cocina, onCocina: (c) => setState(() => _cocina = c)),
        ),
    ];
    return DefaultTabController(
      key: ValueKey(pestanas.length),
      length: pestanas.length,
      child: Container(
        color: AppColors.surfaceSubtle,
        child: Column(
          children: [
            Material(
              color: AppColors.surface,
              child: TabBar(
                tabs: [for (final p in pestanas) p.$1],
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textMuted,
                indicatorColor: AppColors.primary,
              ),
            ),
            Expanded(child: TabBarView(physics: const NeverScrollableScrollPhysics(), children: [for (final p in pestanas) p.$2])),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ Salón

class _Salon extends StatefulWidget {
  final Negocio negocio;
  const _Salon({required this.negocio});

  @override
  State<_Salon> createState() => _SalonState();
}

class _SalonState extends State<_Salon> with AutomaticKeepAliveClientMixin {
  Map<String, dynamic>? _datos;
  Timer? _timer;
  bool _abriendo = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _cargar());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final r = await ApiService.get('/restaurante/salon/?negocio=${widget.negocio.id}');
      if (r.statusCode == 200 && mounted) setState(() => _datos = json.decode(utf8.decode(r.bodyBytes)));
    } catch (_) {}
  }

  Future<void> _abrir({int? mesaId, int? ordenId, String nombre = ''}) async {
    if (_abriendo) return;
    setState(() => _abriendo = true);
    try {
      var id = ordenId;
      if (id == null) {
        final r = await ApiService.post('/restaurante/ordenes/', {
          'negocio': widget.negocio.id,
          if (mesaId != null) 'mesa': mesaId,
          if (nombre.isNotEmpty) 'nombre': nombre,
        });
        if (r.statusCode != 200 && r.statusCode != 201) throw Exception(ApiService.mensajeError(r));
        id = json.decode(utf8.decode(r.bodyBytes))['id'] as int;
      }
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => RestauranteOrdenScreen(negocio: widget.negocio, ordenId: id!)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo abrir: $e")));
    }
    if (mounted) setState(() => _abriendo = false);
    _cargar();
  }

  Future<void> _paraLlevar() async {
    final ctrl = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Pedido para llevar"),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: "A nombre de", border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text("Abrir")),
        ],
      ),
    );
    if (nombre != null) _abrir(nombre: nombre);
  }

  Widget _tarjetaMesa({required String titulo, String subtitulo = '', Map<String, dynamic>? orden, required VoidCallback onTap}) {
    final listos = (orden?['listos'] ?? 0) as int;
    final cuenta = orden?['cuenta_pedida'] == true;
    final color = orden == null ? colorLibre : (cuenta ? colorCuenta : (listos > 0 ? colorListo : colorOcupada));
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: orden == null ? AppColors.border : color, width: orden == null ? 1 : 2),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textStrong)),
                ),
                Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              ]),
              const SizedBox(height: 2),
              Text(
                orden == null ? (subtitulo.isEmpty ? "Libre" : subtitulo) : "#${orden['numero']} · ${minutosDesde(orden['abierta_en'])}",
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const Spacer(),
              if (orden != null) ...[
                Text(formatearColones(orden['total'] ?? 0, decimales: 0),
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong)),
                const SizedBox(height: 4),
                Wrap(spacing: 4, runSpacing: 4, children: [
                  if (cuenta) _chip("Pidió la cuenta", colorCuenta),
                  if (listos > 0) _chip("$listos listo${listos == 1 ? '' : 's'}", colorListo),
                  if ((orden['sin_enviar'] ?? 0) > 0) _chip("${orden['sin_enviar']} sin enviar", AppColors.textMuted),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String texto, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
        child: Text(texto, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );

  Widget _grilla(List<Widget> hijos) => GridView.extent(
        maxCrossAxisExtent: 190,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.05,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: hijos,
      );

  Widget _titulo(String texto) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
        child: Text(texto.toUpperCase(),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .6, color: AppColors.textMuted)),
      );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final d = _datos;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final mesas = (d['mesas'] as List).cast<Map<String, dynamic>>();
    final llevar = (d['para_llevar'] as List).cast<Map<String, dynamic>>();
    final zonas = <String, List<Map<String, dynamic>>>{};
    for (final m in mesas) {
      zonas.putIfAbsent((m['zona'] ?? '').toString(), () => []).add(m);
    }
    final ocupadas = mesas.where((m) => m['orden'] != null).length;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(children: [
            Expanded(
              child: Text("$ocupadas de ${mesas.length} mesas ocupadas", style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ),
            FilledButton.tonalIcon(onPressed: _paraLlevar, icon: const Icon(Icons.takeout_dining_outlined, size: 18), label: const Text("Para llevar")),
          ]),
          if (mesas.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text("No hay mesas. Agregalas en la pestaña Mesas.", textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
            ),
          for (final zona in zonas.entries) ...[
            if (zonas.length > 1 || zona.key.isNotEmpty) _titulo(zona.key.isEmpty ? "Sin zona" : zona.key) else const SizedBox(height: 12),
            _grilla([
              for (final m in zona.value)
                _tarjetaMesa(
                  titulo: m['nombre'],
                  subtitulo: "${m['capacidad']} personas",
                  orden: m['orden'],
                  onTap: () => _abrir(mesaId: m['id'], ordenId: (m['orden'] as Map?)?['id'] as int?),
                ),
            ]),
          ],
          if (llevar.isNotEmpty) ...[
            _titulo("Para llevar"),
            _grilla([
              for (final o in llevar)
                _tarjetaMesa(
                  titulo: (o['nombre'] ?? '').toString().isEmpty ? "Para llevar" : o['nombre'],
                  orden: o,
                  onTap: () => _abrir(ordenId: o['id'] as int),
                ),
            ]),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Cocina

class _Cocina extends StatefulWidget {
  final Negocio negocio;
  const _Cocina({required this.negocio});

  @override
  State<_Cocina> createState() => _CocinaState();
}

class _CocinaState extends State<_Cocina> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>>? _comandas;
  Timer? _timer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _cargar());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final r = await ApiService.get('/restaurante/cocina/?negocio=${widget.negocio.id}');
      if (r.statusCode == 200 && mounted) {
        setState(() => _comandas = ((json.decode(utf8.decode(r.bodyBytes))['comandas'] as List).cast<Map<String, dynamic>>()));
      }
    } catch (_) {}
  }

  Future<void> _marcar(List<int> ids, String estado) async {
    if (ids.isEmpty) return;
    // Al instante en pantalla; el servidor confirma en la próxima consulta.
    setState(() {
      for (final c in _comandas ?? []) {
        for (final i in (c['items'] as List)) {
          if (ids.contains(i['id'])) i['estado'] = estado;
        }
      }
    });
    try {
      await ApiService.post('/restaurante/cocina/', {'negocio': widget.negocio.id, 'items': ids, 'estado': estado});
    } catch (_) {}
    _cargar();
  }

  Color _colorTiempo(String? iso) {
    final fecha = DateTime.tryParse(iso ?? '');
    if (fecha == null) return colorOcupada;
    final m = DateTime.now().difference(fecha.toLocal()).inMinutes;
    if (m >= 20) return const Color(0xFFDC2626);
    if (m >= 10) return colorCuenta;
    return colorOcupada;
  }

  Widget _comanda(Map<String, dynamic> c) {
    final items = (c['items'] as List).cast<Map<String, dynamic>>();
    final pendientes = items.where((i) => i['estado'] == 'en_cocina').map((i) => i['id'] as int).toList();
    final terminada = pendientes.isEmpty;
    final color = terminada ? colorListo : _colorTiempo(c['enviado_en']);
    final donde = (c['mesa'] ?? '').toString().isNotEmpty
        ? c['mesa']
        : ((c['nombre'] ?? '').toString().isNotEmpty ? "Llevar · ${c['nombre']}" : "Para llevar");
    return Opacity(
      opacity: terminada ? 0.6 : 1,
      child: Container(
        width: 270,
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: color, width: 2)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              color: color,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(children: [
                Expanded(
                  child: Text("$donde", maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                Text("#${c['numero']}${(c['ronda'] ?? 1) > 1 ? ' · R${c['ronda']}' : ''}",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Text(minutosDesde(c['enviado_en']), style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ),
            for (final i in items)
              InkWell(
                onTap: i['estado'] == 'anulado' ? null : () => _marcar([i['id'] as int], i['estado'] == 'listo' ? 'en_cocina' : 'listo'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        i['estado'] == 'listo' ? Icons.check_circle : (i['estado'] == 'anulado' ? Icons.cancel_outlined : Icons.radio_button_unchecked),
                        size: 22,
                        color: i['estado'] == 'listo' ? colorListo : (i['estado'] == 'anulado' ? const Color(0xFFDC2626) : AppColors.textMuted),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "${i['cantidad']} × ${i['nombre']}${i['estado'] == 'anulado' ? '  (ANULADO)' : ''}",
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: i['estado'] == 'anulado' ? const Color(0xFFDC2626) : AppColors.textStrong,
                                decoration: i['estado'] == 'anulado' ? TextDecoration.lineThrough : null,
                              ),
                            ),
                            if ((i['nota'] ?? '').toString().isNotEmpty)
                              Text("→ ${i['nota']}", style: const TextStyle(color: Color(0xFFB45309), fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: terminada
                  ? const Text("Lista", textAlign: TextAlign.center, style: TextStyle(color: colorListo, fontWeight: FontWeight.w700))
                  : FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: colorListo),
                      onPressed: () => _marcar(pendientes, 'listo'),
                      icon: const Icon(Icons.done_all, size: 18),
                      label: const Text("Todo listo"),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final comandas = _comandas;
    if (comandas == null) return const Center(child: CircularProgressIndicator());
    if (comandas.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.soup_kitchen_outlined, size: 56, color: AppColors.textMuted),
          const SizedBox(height: 10),
          Text("No hay pedidos en cocina.", style: TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text("Se actualiza sola cada pocos segundos.", style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ]),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Wrap(spacing: 12, runSpacing: 12, children: [for (final c in comandas) _comanda(c)]),
    );
  }
}

// ------------------------------------------------------------------ Mesas

class _ConfigMesas extends StatefulWidget {
  final Negocio negocio;
  final String cocina;
  final ValueChanged<String> onCocina;
  const _ConfigMesas({required this.negocio, required this.cocina, required this.onCocina});

  @override
  State<_ConfigMesas> createState() => _ConfigMesasState();
}

class _ConfigMesasState extends State<_ConfigMesas> {
  List<Map<String, dynamic>>? _mesas;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _aviso(String texto) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _cargar() async {
    try {
      final r = await ApiService.get('/restaurante/mesas/?negocio=${widget.negocio.id}');
      if (r.statusCode == 200 && mounted) {
        setState(() => _mesas = (json.decode(utf8.decode(r.bodyBytes)) as List).cast<Map<String, dynamic>>());
      }
    } catch (_) {}
  }

  Future<void> _cambiarCocina(String cocina) async {
    final r = await ApiService.patch('/restaurante/config/?negocio=${widget.negocio.id}', {'cocina': cocina});
    if (r.statusCode == 200) {
      widget.onCocina(cocina);
    } else if (mounted) {
      _aviso("No se pudo guardar: ${ApiService.mensajeError(r)}");
    }
  }

  Future<void> _editar([Map<String, dynamic>? mesa]) async {
    final nombre = TextEditingController(text: mesa?['nombre'] ?? 'Mesa ${(_mesas?.length ?? 0) + 1}');
    final zona = TextEditingController(text: mesa?['zona'] ?? (_mesas?.isNotEmpty == true ? _mesas!.last['zona'] : 'Salón'));
    final capacidad = TextEditingController(text: '${mesa?['capacidad'] ?? 4}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(mesa == null ? "Nueva mesa" : "Editar mesa"),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nombre, autofocus: true, decoration: const InputDecoration(labelText: "Nombre", border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: zona, decoration: const InputDecoration(labelText: "Zona", hintText: "Salón, Terraza, Barra...", border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: capacidad, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Personas", border: OutlineInputBorder())),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Guardar")),
        ],
      ),
    );
    if (ok != true || nombre.text.trim().isEmpty) return;
    final datos = {
      'negocio': widget.negocio.id,
      'nombre': nombre.text.trim(),
      'zona': zona.text.trim(),
      'capacidad': int.tryParse(capacidad.text) ?? 4,
      if (mesa == null) 'orden': (_mesas?.length ?? 0) + 1,
    };
    final r = mesa == null
        ? await ApiService.post('/restaurante/mesas/', datos)
        : await ApiService.patch('/restaurante/mesas/${mesa['id']}/', datos);
    if (r.statusCode >= 300 && mounted) _aviso("No se pudo guardar: ${ApiService.mensajeError(r)}");
    _cargar();
  }

  Future<void> _borrar(Map<String, dynamic> mesa) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("¿Quitar ${mesa['nombre']}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text("Quitar")),
        ],
      ),
    );
    if (ok != true) return;
    final r = await ApiService.delete('/restaurante/mesas/${mesa['id']}/');
    if (r.statusCode >= 300 && mounted) _aviso(ApiService.mensajeError(r));
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final mesas = _mesas;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text("¿Cómo le llegan los pedidos a la cocina?", style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'pantalla', icon: Icon(Icons.tv_outlined), label: Text("Pantalla")),
            ButtonSegment(value: 'impresora', icon: Icon(Icons.print_outlined), label: Text("Impresora")),
            ButtonSegment(value: 'ambas', label: Text("Las dos")),
          ],
          selected: {widget.cocina},
          onSelectionChanged: (s) => _cambiarCocina(s.first),
        ),
        const SizedBox(height: 6),
        Text(
          widget.cocina == 'impresora'
              ? "Al enviar a cocina se imprime la comanda en la impresora de tickets."
              : widget.cocina == 'ambas'
                  ? "Los pedidos salen en la pestaña Cocina y además se imprime la comanda."
                  : "Abrí la pestaña Cocina en una tablet o compu de la cocina: los pedidos aparecen solos.",
          style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
        ),
        const SizedBox(height: 22),
        Row(children: [
          Expanded(child: Text("Mesas", style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong))),
          FilledButton.icon(onPressed: () => _editar(), icon: const Icon(Icons.add, size: 18), label: const Text("Agregar mesa")),
        ]),
        const SizedBox(height: 8),
        if (mesas == null)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
        else
          for (final m in mesas)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: AppColors.surface,
              child: ListTile(
                leading: const Icon(Icons.table_restaurant_outlined),
                title: Text(m['nombre'], style: TextStyle(color: AppColors.textStrong)),
                subtitle: Text("${(m['zona'] ?? '').toString().isEmpty ? 'Sin zona' : m['zona']} · ${m['capacidad']} personas",
                    style: TextStyle(color: AppColors.textMuted)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.edit_outlined), tooltip: "Editar", onPressed: () => _editar(m)),
                  IconButton(icon: const Icon(Icons.delete_outline), tooltip: "Quitar", onPressed: () => _borrar(m)),
                ]),
              ),
            ),
      ],
    );
  }
}
