import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'formato.dart';
import 'negocio.dart';
import 'restaurante_insumos.dart';
import 'restaurante_orden_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/campana.dart';

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
      if (!_esCajero) (const Tab(icon: Icon(Icons.kitchen_outlined, size: 20), text: "Insumos"), InsumosRecetas(negocio: widget.negocio)),
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
  // Platos listos por orden en la consulta anterior: si sube, suena la
  // campana y se avisa qué mesa tiene platos para llevar.
  Map<int, int>? _listosAntes;
  // Llamados y pedidos del menú QR ya vistos (para avisar solo lo nuevo).
  Set<String>? _avisosQrAntes;

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
      if (r.statusCode == 200 && mounted) {
        final datos = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        _avisarListos(datos);
        _avisarQr(datos);
        setState(() => _datos = datos);
      }
    } catch (_) {}
  }

  void _avisarQr(Map<String, dynamic> datos) {
    final ahora = <String>{};
    final textos = <String, String>{};
    for (final m in (datos['mesas'] as List)) {
      final llamado = m['llamado'];
      if (llamado != null) {
        final clave = "l${m['id']}-${llamado['en']}";
        ahora.add(clave);
        textos[clave] = "${m['nombre']}: ${llamado['motivo'] == 'cuenta' ? 'pide la cuenta' : 'llama al mesero'}";
      }
      final pedido = ((m['orden'] as Map?)?['pedido_qr'] ?? 0) as int;
      if (pedido > 0) {
        final clave = "p${m['id']}-$pedido";
        ahora.add(clave);
        textos[clave] = "${m['nombre']}: pidió desde el QR";
      }
    }
    final antes = _avisosQrAntes;
    _avisosQrAntes = ahora;
    if (antes == null) return;
    final nuevos = [for (final c in ahora.difference(antes)) textos[c]!];
    if (nuevos.isEmpty) return;
    Campana.sonar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      width: MediaQuery.sizeOf(context).width >= 700 ? 420 : null,
      backgroundColor: colorCuenta,
      content: Text(nuevos.join(' · ')),
    ));
  }

  void _avisarListos(Map<String, dynamic> datos) {
    final ahora = <int, int>{};
    final nombres = <int, String>{};
    for (final m in (datos['mesas'] as List)) {
      final o = m['orden'];
      if (o != null) {
        ahora[o['id'] as int] = (o['listos'] ?? 0) as int;
        nombres[o['id'] as int] = m['nombre'];
      }
    }
    for (final o in (datos['para_llevar'] as List)) {
      ahora[o['id'] as int] = (o['listos'] ?? 0) as int;
      nombres[o['id'] as int] = (o['nombre'] ?? '').toString().isEmpty ? 'Para llevar' : 'Llevar · ${o['nombre']}';
    }
    final antes = _listosAntes;
    _listosAntes = ahora;
    if (antes == null) return; // primera carga: no avisa lo que ya estaba
    final nuevos = [for (final e in ahora.entries) if (e.value > (antes[e.key] ?? 0)) nombres[e.key]!];
    if (nuevos.isEmpty) return;
    Campana.sonar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      width: MediaQuery.sizeOf(context).width >= 700 ? 420 : null,
      backgroundColor: colorListo,
      content: Text("Platos listos: ${nuevos.join(', ')}"),
    ));
  }

  Future<void> _abrir({int? mesaId, int? ordenId, String nombre = '', bool atender = false}) async {
    if (_abriendo) return;
    setState(() => _abriendo = true);
    if (atender && mesaId != null) {
      ApiService.post('/restaurante/salon/atender/', {'negocio': widget.negocio.id, 'mesa': mesaId}).ignore();
    }
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

  Widget _tarjetaMesa({
    required String titulo,
    String subtitulo = '',
    Map<String, dynamic>? orden,
    Map<String, dynamic>? llamado,
    required VoidCallback onTap,
  }) {
    final listos = (orden?['listos'] ?? 0) as int;
    final cuenta = orden?['cuenta_pedida'] == true;
    final pedidoQr = (orden?['pedido_qr'] ?? 0) as int;
    final color = llamado != null || pedidoQr > 0
        ? colorCuenta
        : (orden == null ? colorLibre : (cuenta ? colorCuenta : (listos > 0 ? colorListo : colorOcupada)));
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: orden == null && llamado == null ? AppColors.border : color, width: orden == null && llamado == null ? 1 : 2),
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
              if (llamado != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _chip(llamado['motivo'] == 'cuenta' ? "🧾 Pide la cuenta" : "🙋 Llama al mesero", colorCuenta),
                ),
              if (orden != null) ...[
                Text(formatearColones(orden['total'] ?? 0, decimales: 0),
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong)),
                const SizedBox(height: 4),
                Wrap(spacing: 4, runSpacing: 4, children: [
                  if (pedidoQr > 0) _chip("Pedido QR: $pedidoQr", colorCuenta),
                  if (cuenta && llamado == null) _chip("Pidió la cuenta", colorCuenta),
                  if (listos > 0) _chip("$listos listo${listos == 1 ? '' : 's'}", colorListo),
                  if ((orden['sin_enviar'] ?? 0) - pedidoQr > 0) _chip("${orden['sin_enviar'] - pedidoQr} sin enviar", AppColors.textMuted),
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
                  llamado: m['llamado'],
                  onTap: () => _abrir(mesaId: m['id'], ordenId: (m['orden'] as Map?)?['id'] as int?, atender: m['llamado'] != null),
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
  /// Pantalla completa para la tablet de la cocina: letra más grande.
  final bool grande;
  const _Cocina({required this.negocio, this.grande = false});

  @override
  State<_Cocina> createState() => _CocinaState();
}

class _CocinaState extends State<_Cocina> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>>? _comandas;
  List<Map<String, dynamic>> _estaciones = [];
  int? _estacion; // null = todas
  bool _sonido = true;
  Set<String>? _vistas; // comandas ya vistas (para sonar solo con las nuevas)
  Timer? _timer;

  @override
  bool get wantKeepAlive => true;

  String get _clavePrefs => 'cocina_${widget.negocio.id}';

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _estacion = prefs.getInt('${_clavePrefs}_estacion');
      _sonido = prefs.getBool('${_clavePrefs}_sonido') ?? true;
    } catch (_) {}
    await _cargar();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _cargar());
  }

  Future<void> _guardarPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_estacion == null) {
        await prefs.remove('${_clavePrefs}_estacion');
      } else {
        await prefs.setInt('${_clavePrefs}_estacion', _estacion!);
      }
      await prefs.setBool('${_clavePrefs}_sonido', _sonido);
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final filtro = _estacion == null ? '' : '&estacion=$_estacion';
      final r = await ApiService.get('/restaurante/cocina/?negocio=${widget.negocio.id}$filtro');
      if (r.statusCode == 200 && mounted) {
        final datos = json.decode(utf8.decode(r.bodyBytes));
        final comandas = (datos['comandas'] as List).cast<Map<String, dynamic>>();
        final estaciones = ((datos['estaciones'] as List?) ?? []).cast<Map<String, dynamic>>();
        final claves = {for (final c in comandas) "${c['orden']}-${c['ronda']}-${c['estacion']}"};
        if (_vistas != null && _sonido && claves.difference(_vistas!).isNotEmpty) Campana.sonar();
        _vistas = {...?_vistas, ...claves};
        setState(() {
          _comandas = comandas;
          _estaciones = estaciones;
          if (_estacion != null && !estaciones.any((e) => e['id'] == _estacion)) _estacion = null;
        });
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
    final g = widget.grande ? 1.25 : 1.0;
    final items = (c['items'] as List).cast<Map<String, dynamic>>();
    final pendientes = items.where((i) => i['estado'] == 'en_cocina').map((i) => i['id'] as int).toList();
    final terminada = pendientes.isEmpty;
    final color = terminada ? colorListo : _colorTiempo(c['enviado_en']);
    final donde = (c['mesa'] ?? '').toString().isNotEmpty
        ? c['mesa']
        : ((c['nombre'] ?? '').toString().isNotEmpty ? "Llevar · ${c['nombre']}" : "Para llevar");
    final estacion = (c['estacion'] ?? '').toString();
    return Opacity(
      opacity: terminada ? 0.6 : 1,
      child: Container(
        width: 270 * g,
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
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16 * g)),
                ),
                Text("#${c['numero']}${(c['ronda'] ?? 1) > 1 ? ' · R${c['ronda']}' : ''}",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14 * g)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Text(
                [minutosDesde(c['enviado_en']), if (estacion.isNotEmpty && _estacion == null) estacion].join(' · '),
                style: TextStyle(color: AppColors.textMuted, fontSize: 12 * g),
              ),
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
                        size: 22 * g,
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
                                fontSize: 15 * g,
                                color: i['estado'] == 'anulado' ? const Color(0xFFDC2626) : AppColors.textStrong,
                                decoration: i['estado'] == 'anulado' ? TextDecoration.lineThrough : null,
                              ),
                            ),
                            if ((i['nota'] ?? '').toString().isNotEmpty)
                              Text("→ ${i['nota']}", style: TextStyle(color: const Color(0xFFB45309), fontWeight: FontWeight.w600, fontSize: 14 * g)),
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
                      style: FilledButton.styleFrom(backgroundColor: colorListo, padding: EdgeInsets.symmetric(vertical: 12 * g)),
                      onPressed: () => _marcar(pendientes, 'listo'),
                      icon: const Icon(Icons.done_all, size: 18),
                      label: Text("Todo listo", style: TextStyle(fontSize: 14 * g)),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _barra() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
      child: Row(children: [
        if (_estaciones.isNotEmpty)
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: const Text("Todas"),
                    selected: _estacion == null,
                    onSelected: (_) {
                      setState(() => _estacion = null);
                      _guardarPrefs();
                      _cargar();
                    },
                  ),
                ),
                for (final e in _estaciones)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(e['nombre']),
                      selected: _estacion == e['id'],
                      onSelected: (_) {
                        setState(() => _estacion = e['id'] as int);
                        _guardarPrefs();
                        _cargar();
                      },
                    ),
                  ),
              ]),
            ),
          )
        else
          const Spacer(),
        IconButton(
          tooltip: _sonido ? "Silenciar" : "Activar sonido",
          icon: Icon(_sonido ? Icons.notifications_active_outlined : Icons.notifications_off_outlined),
          onPressed: () {
            setState(() => _sonido = !_sonido);
            _guardarPrefs();
            if (_sonido) Campana.sonar();
          },
        ),
        if (!widget.grande)
          IconButton(
            tooltip: "Pantalla completa",
            icon: const Icon(Icons.fullscreen),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PantallaCocina(negocio: widget.negocio))),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final comandas = _comandas;
    Widget cuerpo;
    if (comandas == null) {
      cuerpo = const Center(child: CircularProgressIndicator());
    } else if (comandas.isEmpty) {
      cuerpo = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.soup_kitchen_outlined, size: 56, color: AppColors.textMuted),
          const SizedBox(height: 10),
          Text("No hay pedidos en cocina.", style: TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text("Se actualiza sola cada pocos segundos.", style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ]),
      );
    } else {
      cuerpo = SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Wrap(spacing: 12, runSpacing: 12, children: [for (final c in comandas) _comanda(c)]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_barra(), Expanded(child: cuerpo)]);
  }
}

/// La cocina a pantalla completa (sin el menú de la app), para dejarla
/// abierta en la tablet o compu de la cocina.
class PantallaCocina extends StatelessWidget {
  final Negocio negocio;
  const PantallaCocina({super.key, required this.negocio});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceSubtle,
      appBar: AppBar(title: Text("Cocina · ${negocio.nombreComercial}"), toolbarHeight: 48),
      body: _Cocina(negocio: negocio, grande: true),
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
  bool? _cobrarServicio;
  bool _menuQr = false;
  bool _pedidosQr = false;
  Set<int> _categoriasMenu = {};
  Map<String, dynamic>? _propinas;
  int _diasPropinas = 1;
  List<Map<String, dynamic>> _estaciones = [];
  List<Map<String, dynamic>> _categorias = [];

  @override
  void initState() {
    super.initState();
    _cargar();
    _cargarPropinas();
  }

  void _aviso(String texto) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _cargar() async {
    try {
      final rs = await Future.wait([
        ApiService.get('/restaurante/mesas/?negocio=${widget.negocio.id}'),
        ApiService.get('/restaurante/estaciones/?negocio=${widget.negocio.id}'),
        ApiService.get('/categorias/?negocio=${widget.negocio.id}'),
        ApiService.get('/restaurante/config/?negocio=${widget.negocio.id}'),
      ]);
      List<Map<String, dynamic>> lista(int i) =>
          rs[i].statusCode == 200 ? (json.decode(utf8.decode(rs[i].bodyBytes)) as List).cast<Map<String, dynamic>>() : [];
      if (mounted) {
        setState(() {
          _mesas = lista(0);
          _estaciones = lista(1);
          _categorias = lista(2);
          if (rs[3].statusCode == 200) {
            final config = json.decode(utf8.decode(rs[3].bodyBytes));
            _cobrarServicio = config['cobrar_servicio'] == true;
            _menuQr = config['menu_qr'] == true;
            _pedidosQr = config['pedidos_qr'] == true;
            _categoriasMenu = {...((config['categorias_menu'] as List?) ?? []).cast<int>()};
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _guardarConfig(Map<String, dynamic> datos) async {
    final r = await ApiService.patch('/restaurante/config/?negocio=${widget.negocio.id}', datos);
    if (r.statusCode != 200 && mounted) {
      _aviso("No se pudo guardar: ${ApiService.mensajeError(r)}");
      _cargar();
    }
  }

  Future<void> _imprimirQrMesas() async {
    final mesas = (_mesas ?? []).where((m) => m['url_menu'] != null).toList();
    if (mesas.isEmpty) return;
    final doc = pw.Document();
    const porPagina = 6;
    for (var i = 0; i < mesas.length; i += porPagina) {
      final grupo = mesas.sublist(i, (i + porPagina).clamp(0, mesas.length));
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => pw.GridView(
          crossAxisCount: 2,
          childAspectRatio: 1.25,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          children: [
            for (final m in grupo)
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400), borderRadius: pw.BorderRadius.circular(10)),
                child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
                  pw.Text(widget.negocio.nombreComercial, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                  pw.Text("${m['nombre']}", style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 8),
                  pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: m['url_menu'], width: 130, height: 130),
                  pw.SizedBox(height: 8),
                  pw.Text("Escaneá para ver el menú", style: const pw.TextStyle(fontSize: 11)),
                ]),
              ),
          ],
        ),
      ));
    }
    await Printing.layoutPdf(onLayout: (_) async => doc.save(), name: 'QR_mesas_${widget.negocio.nombreComercial}.pdf');
  }

  Widget _seccionMenuQr() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("Menú QR en las mesas", style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong)),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _menuQr,
        onChanged: (v) {
          setState(() => _menuQr = v);
          _guardarConfig({'menu_qr': v});
        },
        title: Text("Activar el menú QR", style: TextStyle(color: AppColors.textStrong)),
        subtitle: Text("Cada mesa tiene su QR: el cliente ve el menú, llama al mesero o pide la cuenta.",
            style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
      ),
      if (_menuQr) ...[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _pedidosQr,
          onChanged: (v) {
            setState(() => _pedidosQr = v);
            _guardarConfig({'pedidos_qr': v});
          },
          title: Text("Dejar pedir desde el QR", style: TextStyle(color: AppColors.textStrong)),
          subtitle: Text("Lo que pidan queda \"por enviar\" en su mesa y el mesero lo confirma antes de mandarlo a cocina.",
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
        ),
        if (_categorias.isNotEmpty) ...[
          Text(_categoriasMenu.isEmpty ? "Categorías en el menú: todas" : "Categorías en el menú:",
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in _categorias)
              FilterChip(
                label: Text(c['nombre']),
                selected: _categoriasMenu.contains(c['id']),
                onSelected: (v) {
                  setState(() => v ? _categoriasMenu.add(c['id'] as int) : _categoriasMenu.remove(c['id']));
                  _guardarConfig({'categorias_menu': _categoriasMenu.toList()});
                },
              ),
          ]),
          const SizedBox(height: 10),
        ],
        OutlinedButton.icon(
          onPressed: (_mesas ?? []).isEmpty ? null : _imprimirQrMesas,
          icon: const Icon(Icons.qr_code_2),
          label: const Text("Imprimir los QR de las mesas"),
        ),
      ],
    ]);
  }

  Future<void> _cargarPropinas() async {
    try {
      final r = await ApiService.get('/restaurante/propinas/?negocio=${widget.negocio.id}&dias=$_diasPropinas');
      if (r.statusCode == 200 && mounted) setState(() => _propinas = json.decode(utf8.decode(r.bodyBytes)));
    } catch (_) {}
  }

  Widget _seccionPropinas() {
    final p = _propinas;
    final filas = ((p?['por_mesero'] as List?) ?? []).cast<Map<String, dynamic>>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 8, children: [
        Text("Propinas", style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong)),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 1, label: Text("Hoy")),
            ButtonSegment(value: 7, label: Text("7 días")),
            ButtonSegment(value: 30, label: Text("30 días")),
          ],
          selected: {_diasPropinas},
          onSelectionChanged: (s) {
            setState(() => _diasPropinas = s.first);
            _cargarPropinas();
          },
        ),
      ]),
      const SizedBox(height: 4),
      Text("Lo que dejaron de propina voluntaria al cobrar, por mesero. No forma parte de las ventas ante Hacienda.",
          style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
      const SizedBox(height: 8),
      if (p == null)
        const SizedBox.shrink()
      else if (filas.isEmpty)
        Text("Sin propinas en este periodo.", style: TextStyle(color: AppColors.textMuted))
      else
        Card(
          color: AppColors.surface,
          margin: EdgeInsets.zero,
          child: Column(children: [
            for (final f in filas)
              ListTile(
                dense: true,
                leading: const Icon(Icons.person_outline),
                title: Text(f['mesero'], style: TextStyle(color: AppColors.textStrong)),
                subtitle: Text("${f['cobros']} ${f['cobros'] == 1 ? 'cobro' : 'cobros'}", style: TextStyle(color: AppColors.textMuted)),
                trailing: Text(formatearColones(f['total'] ?? 0, decimales: 0), style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong)),
              ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              title: Text("Total", style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong)),
              trailing: Text(formatearColones(p['total'] ?? 0, decimales: 0), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textStrong)),
            ),
          ]),
        ),
    ]);
  }

  Future<void> _editarEstacion([Map<String, dynamic>? estacion]) async {
    final nombre = TextEditingController(text: estacion?['nombre'] ?? (_estaciones.isEmpty ? 'Cocina' : 'Barra'));
    final elegidas = <int>{...((estacion?['categorias'] as List?) ?? []).cast<int>()};
    // Categorías que ya tiene otra estación (al guardar se pasan a esta).
    final deOtra = <int, String>{
      for (final e in _estaciones)
        if (e['id'] != estacion?['id'])
          for (final c in (e['categorias'] as List).cast<int>()) c: e['nombre'] as String,
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(estacion == null ? "Nueva estación" : "Editar estación"),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(controller: nombre, autofocus: true, decoration: const InputDecoration(labelText: "Nombre", hintText: "Cocina, Barra, Parrilla...", border: OutlineInputBorder())),
              const SizedBox(height: 14),
              Text("¿Qué categorías prepara?", style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              const SizedBox(height: 8),
              if (_categorias.isEmpty)
                Text("Todavía no hay categorías de productos. Crealas en Inventario.", style: TextStyle(color: AppColors.textMuted, fontSize: 12.5))
              else
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final c in _categorias)
                    FilterChip(
                      label: Text(deOtra.containsKey(c['id']) && !elegidas.contains(c['id']) ? "${c['nombre']} (${deOtra[c['id']]})" : c['nombre']),
                      selected: elegidas.contains(c['id']),
                      onSelected: (v) => setD(() => v ? elegidas.add(c['id'] as int) : elegidas.remove(c['id'])),
                    ),
                ]),
            ]),
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
      'categorias': elegidas.toList(),
      if (estacion == null) 'orden': _estaciones.length + 1,
    };
    final r = estacion == null
        ? await ApiService.post('/restaurante/estaciones/', datos)
        : await ApiService.patch('/restaurante/estaciones/${estacion['id']}/', datos);
    if (r.statusCode >= 300 && mounted) _aviso("No se pudo guardar: ${ApiService.mensajeError(r)}");
    _cargar();
  }

  Future<void> _borrarEstacion(Map<String, dynamic> estacion) async {
    final r = await ApiService.delete('/restaurante/estaciones/${estacion['id']}/');
    if (r.statusCode >= 300 && mounted) _aviso(ApiService.mensajeError(r));
    _cargar();
  }

  Widget _seccionEstaciones() {
    final nombresCat = {for (final c in _categorias) c['id']: c['nombre']};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text("Estaciones", style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong))),
        OutlinedButton.icon(onPressed: () => _editarEstacion(), icon: const Icon(Icons.add, size: 18), label: const Text("Agregar estación")),
      ]),
      const SizedBox(height: 4),
      Text(
        _estaciones.isEmpty
            ? "Todo va a una sola cocina. Si tenés barra u otra estación, agregalas: cada una recibe solo lo suyo, con su propia pantalla y su comanda."
            : "Lo que no tenga categoría, o una categoría sin estación, va a ${_estaciones.first['nombre']}.",
        style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
      ),
      const SizedBox(height: 8),
      for (final e in _estaciones)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: AppColors.surface,
          child: ListTile(
            leading: const Icon(Icons.soup_kitchen_outlined),
            title: Text(e['nombre'], style: TextStyle(color: AppColors.textStrong)),
            subtitle: Text(
              (e['categorias'] as List).isEmpty ? "Sin categorías" : (e['categorias'] as List).map((id) => nombresCat[id] ?? '?').join(', '),
              style: TextStyle(color: AppColors.textMuted),
            ),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.edit_outlined), tooltip: "Editar", onPressed: () => _editarEstacion(e)),
              IconButton(icon: const Icon(Icons.delete_outline), tooltip: "Quitar", onPressed: () => _borrarEstacion(e)),
            ]),
          ),
        ),
    ]);
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
        const SizedBox(height: 14),
        if (_cobrarServicio != null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _cobrarServicio!,
            onChanged: (v) async {
              setState(() => _cobrarServicio = v);
              final r = await ApiService.patch('/restaurante/config/?negocio=${widget.negocio.id}', {'cobrar_servicio': v});
              if (r.statusCode != 200 && mounted) {
                setState(() => _cobrarServicio = !v);
                _aviso("No se pudo guardar: ${ApiService.mensajeError(r)}");
              }
            },
            title: Text("Cobrar 10% de servicio en las mesas", style: TextStyle(color: AppColors.textStrong)),
            subtitle: Text("Va aparte en el tiquete (Otros cargos ante Hacienda). Nunca en pedidos para llevar.",
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
          ),
        const SizedBox(height: 16),
        _seccionMenuQr(),
        const SizedBox(height: 22),
        _seccionPropinas(),
        const SizedBox(height: 22),
        _seccionEstaciones(),
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
