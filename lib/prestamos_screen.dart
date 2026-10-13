import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_service.dart';
import 'cliente.dart';
import 'cuentas_por_cobrar_screen.dart' show abrirWhatsApp;
import 'formato.dart';
import 'negocio.dart';
import 'theme/app_theme.dart';

/// Módulo de préstamos: ventas de vehículos a plazo y préstamos personales,
/// con cuotas mensuales. Backend: gestion/prestamos.py.
class PrestamosScreen extends StatefulWidget {
  final Negocio negocio;
  const PrestamosScreen({super.key, required this.negocio});

  @override
  State<PrestamosScreen> createState() => _PrestamosScreenState();
}

double _n(dynamic v) => double.tryParse('${v ?? 0}') ?? 0;

String _dinero(dynamic v, String moneda, {int decimales = 0}) =>
    moneda == 'USD' ? formatearDolares(_n(v), decimales: decimales == 0 ? 2 : decimales) : formatearColones(_n(v), decimales: decimales);

String _fecha(String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  if (d == null) return '';
  const meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'set', 'oct', 'nov', 'dic'];
  return "${d.day} ${meses[d.month - 1]} ${d.year}";
}

const _verde = Color(0xFF16A34A);
const _ambar = Color(0xFFD97706);
const _rojo = Color(0xFFDC2626);
const _metodos = {
  'frances': ('Cuota fija', 'La misma cuota todos los meses; al inicio paga más interés y al final más capital.'),
  'saldo': ('Interés sobre saldo', 'Capital fijo cada mes más el interés del saldo: la cuota va bajando.'),
  'plano': ('Interés plano', 'El interés se calcula siempre sobre el monto original: cuota fija, sale más caro.'),
  'solo_interes': ('Solo intereses', 'Cada mes solo intereses y el capital completo en la última cuota.'),
};
const _medios = {'04': 'Transferencia', '06': 'SINPE Móvil', '01': 'Efectivo', '02': 'Tarjeta', '03': 'Cheque'};

Color _colorAtraso(int dias) => dias == 0 ? _verde : (dias <= 30 ? _ambar : _rojo);

/// Confirma (registra el pago, con el monto editable) o rechaza un pago que
/// el deudor reportó desde su enlace. Devuelve true si se resolvió.
Future<bool> _resolverReporte(BuildContext context, Map rep, String accion) async {
  final moneda = '${rep['moneda']}';
  final monto = TextEditingController(text: _n(rep['monto_detectado'] ?? rep['monto_reportado']).toStringAsFixed(2));
  final nota = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(accion == 'confirmar' ? "Confirmar pago" : "Rechazar pago"),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (accion == 'confirmar') ...[
            Text("Se registra como pago del préstamo #${rep['numero']} y se aplica a mora, intereses y capital.",
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 10),
            TextField(
              controller: monto,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: "Monto recibido", prefixText: moneda == 'USD' ? '\$ ' : '₡ ', border: const OutlineInputBorder()),
            ),
          ] else
            TextField(controller: nota, decoration: const InputDecoration(labelText: "Motivo (opcional)", border: OutlineInputBorder())),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
        FilledButton(
          style: accion == 'confirmar' ? null : FilledButton.styleFrom(backgroundColor: _rojo),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(accion == 'confirmar' ? "Confirmar" : "Rechazar"),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    ApiService.verificar(await ApiService.post('/prestamos-reportes/${rep['id']}/', {
      'accion': accion,
      if (accion == 'confirmar') 'monto': monto.text.trim().replaceAll(',', '.'),
      'nota': nota.text.trim(),
    }));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(accion == 'confirmar' ? "Pago registrado." : "Pago rechazado.")));
    }
    return true;
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    return false;
  }
}

/// Un pago reportado por el deudor: monto que leyó la IA del comprobante,
/// si coincide con lo que debía, y los botones para resolverlo.
class _TarjetaReporte extends StatelessWidget {
  final Map rep;
  final VoidCallback onResuelto;
  final VoidCallback? onAbrirPrestamo;
  const _TarjetaReporte({required this.rep, required this.onResuelto, this.onAbrirPrestamo});

  @override
  Widget build(BuildContext context) {
    final moneda = '${rep['moneda']}';
    final monto = rep['monto_detectado'] ?? rep['monto_reportado'];
    final coincide = rep['coincide'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: onAbrirPrestamo,
            child: Row(children: [
              Icon(Icons.receipt_long_outlined, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text("${rep['cliente']}", style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong)),
                  Text(monto == null ? "Sin monto" : _dinero(monto, moneda, decimales: 2),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
                  Text(
                    [
                      "Préstamo #${rep['numero']}",
                      _fecha(rep['creado']),
                      if ('${rep['referencia'] ?? ''}'.isNotEmpty) "Ref. ${rep['referencia']}",
                    ].join(' · '),
                    style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Icon(coincide ? Icons.check_circle_outline : Icons.info_outline, size: 16, color: coincide ? _verde : _ambar),
            const SizedBox(width: 4),
            Expanded(
              child: Text(coincide ? "Coincide con lo que debía" : "Revisá el monto: no coincide con la cuota",
                  style: TextStyle(fontSize: 12, color: coincide ? _verde : _ambar, fontWeight: FontWeight.w600)),
            ),
          ]),
          Wrap(alignment: WrapAlignment.end, spacing: 4, children: [
            if (rep['comprobante'] != null)
              TextButton.icon(
                onPressed: () => launchUrl(Uri.parse('${rep['comprobante']}'), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.image_outlined, size: 18),
                label: const Text("Comprobante"),
              ),
            TextButton(
              onPressed: () async {
                if (await _resolverReporte(context, rep, 'rechazar')) onResuelto();
              },
              child: const Text("Rechazar", style: TextStyle(color: _rojo)),
            ),
            FilledButton(
              onPressed: () async {
                if (await _resolverReporte(context, rep, 'confirmar')) onResuelto();
              },
              child: const Text("Confirmar"),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _PrestamosScreenState extends State<PrestamosScreen> {
  bool _cargando = true;
  Map<String, dynamic> _cartera = {};
  List<Map<String, dynamic>> _prestamos = [];
  List<Map<String, dynamic>> _reportes = [];
  String _busqueda = '';
  String _estado = 'activo';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final rs = await Future.wait([
        ApiService.get('/prestamos-cartera/?negocio=${widget.negocio.id}'),
        ApiService.get('/prestamos/?negocio=${widget.negocio.id}${_estado.isEmpty ? '' : '&estado=$_estado'}'),
        ApiService.get('/prestamos-reportes/?negocio=${widget.negocio.id}'),
      ]);
      _cartera = json.decode(utf8.decode(ApiService.verificar(rs[0]).bodyBytes)) as Map<String, dynamic>;
      _prestamos = (json.decode(utf8.decode(ApiService.verificar(rs[1]).bodyBytes)) as List).cast<Map<String, dynamic>>();
      _reportes = (json.decode(utf8.decode(ApiService.verificar(rs[2]).bodyBytes)) as List).cast<Map<String, dynamic>>();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _nuevo() async {
    final creado = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _NuevoPrestamo(negocio: widget.negocio)));
    if (creado == true) _cargar();
  }

  Future<void> _ajustesCobro() async {
    Map<String, dynamic> c;
    try {
      c = json.decode(utf8.decode(ApiService.verificar(await ApiService.get('/prestamos-config/?negocio=${widget.negocio.id}')).bodyBytes))
          as Map<String, dynamic>;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
      return;
    }
    if (!mounted) return;
    bool recordatorios = c['recordatorios'] != false;
    final diasAntes = TextEditingController(text: '${c['dias_antes'] ?? 3}');
    final mora = TextEditingController(text: '${c['tasa_mora_anual'] ?? 0}');
    final gracia = TextEditingController(text: '${c['dias_gracia'] ?? 0}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text("Ajustes de cobro"),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: recordatorios,
                  onChanged: (v) => set(() => recordatorios = v),
                  title: const Text("Recordatorios por correo"),
                  subtitle: const Text("Antes de cada cuota, el día que vence y a los 1, 7, 15 y 30 días de atraso, con el enlace para pagar."),
                ),
                if (recordatorios)
                  TextField(
                    controller: diasAntes,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Días antes del vencimiento", border: OutlineInputBorder()),
                  ),
                const SizedBox(height: 12),
                Text("Para préstamos nuevos", style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: mora,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: "Mora % anual", border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: gracia,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "Días de gracia", border: OutlineInputBorder()),
                    ),
                  ),
                ]),
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
    if (ok != true) return;
    try {
      ApiService.verificar(await ApiService.patch('/prestamos-config/?negocio=${widget.negocio.id}', {
        'recordatorios': recordatorios,
        'dias_antes': int.tryParse(diasAntes.text.trim()) ?? 3,
        'tasa_mora_anual': mora.text.trim().replaceAll(',', '.'),
        'dias_gracia': int.tryParse(gracia.text.trim()) ?? 0,
      }));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ajustes guardados.")));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    }
  }

  Future<void> _abrir(int id) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => _DetallePrestamo(negocio: widget.negocio, prestamoId: id)));
    _cargar();
  }

  Widget _tarjeta(String titulo, String valor, IconData icono, Color color, {String? pie}) => Container(
        width: 200,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icono, size: 18, color: color),
            const SizedBox(width: 6),
            Expanded(child: Text(titulo, style: TextStyle(color: AppColors.textMuted, fontSize: 12.5))),
          ]),
          const SizedBox(height: 6),
          Text(valor, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
          if (pie != null) Text(pie, style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
        ]),
      );

  Widget _resumenMoneda(String moneda, Map m) {
    final tramos = (m['tramos'] as Map?) ?? {};
    Widget tramo(String clave, String texto, Color color) {
      final n = (tramos[clave] ?? 0) as int;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: n > 0 ? 0.14 : 0.05), borderRadius: BorderRadius.circular(10)),
        child: Text("$texto: $n", style: TextStyle(color: n > 0 ? color : AppColors.textMuted, fontWeight: FontWeight.w700, fontSize: 12)),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if ((_cartera['por_moneda'] as Map).length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(moneda == 'USD' ? "En dólares" : "En colones", style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textStrong)),
        ),
      Wrap(spacing: 10, runSpacing: 10, children: [
        _tarjeta("Saldo prestado", _dinero(m['saldo_capital'], moneda), Icons.account_balance_wallet_outlined, AppColors.primary,
            pie: "${m['prestamos']} préstamo${m['prestamos'] == 1 ? '' : 's'} activos"),
        _tarjeta("Cobrado este mes", _dinero(m['cobrado_mes'], moneda), Icons.south_west, _verde,
            pie: "Intereses: ${_dinero(m['intereses_mes'], moneda)}"),
        _tarjeta("Vencido sin pagar", _dinero(_n(m['vencido']) + _n(m['mora']), moneda), Icons.warning_amber_rounded,
            _n(m['vencido']) > 0 ? _rojo : _verde,
            pie: _n(m['mora']) > 0 ? "Incluye mora de ${_dinero(m['mora'], moneda)}" : null),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: [
        tramo('al_dia', "Al día", _verde),
        tramo('1_30', "1-30 días", _ambar),
        tramo('31_60', "31-60", _rojo),
        tramo('61_90', "61-90", _rojo),
        tramo('mas_90', "+90", _rojo),
      ]),
      const SizedBox(height: 14),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final porMoneda = ((_cartera['por_moneda'] as Map?) ?? {}).cast<String, dynamic>();
    final proximos = ((_cartera['proximos'] as List?) ?? []).cast<Map<String, dynamic>>();
    final b = _busqueda.toLowerCase();
    final lista = _prestamos
        .where((p) => b.isEmpty || '${p['cliente_nombre']} ${p['cliente_cedula'] ?? ''} ${p['numero']} ${(p['vehiculo'] as Map?)?['placa'] ?? ''}'
            .toLowerCase()
            .contains(b))
        .toList();
    return Scaffold(
      backgroundColor: AppColors.surfaceSubtle,
      floatingActionButton: FloatingActionButton.extended(onPressed: _nuevo, icon: const Icon(Icons.add), label: const Text("Nuevo préstamo")),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                children: [
                  Row(children: [
                    Icon(Icons.handshake_outlined, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(child: Text("Préstamos", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textStrong))),
                    IconButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _RecordatoriosWhatsApp(negocio: widget.negocio))),
                      icon: const Icon(Icons.chat_outlined),
                      tooltip: "Recordatorios por WhatsApp",
                    ),
                    IconButton(onPressed: _ajustesCobro, icon: const Icon(Icons.tune), tooltip: "Ajustes de cobro"),
                    IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh), tooltip: "Actualizar"),
                  ]),
                  const SizedBox(height: 10),
                  if (_reportes.isNotEmpty) ...[
                    Text("Pagos reportados por confirmar (${_reportes.length})",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
                    Text("Los deudores los mandaron desde su enlace con el comprobante.", style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                    const SizedBox(height: 6),
                    for (final rep in _reportes)
                      _TarjetaReporte(rep: rep, onResuelto: _cargar, onAbrirPrestamo: () => _abrir(rep['prestamo'] as int)),
                    const SizedBox(height: 14),
                  ],
                  if (porMoneda.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text("Todavía no hay préstamos activos. Creá el primero con \"Nuevo préstamo\": una venta de vehículo a plazo o un préstamo personal.",
                          style: TextStyle(color: AppColors.textMuted)),
                    ),
                  for (final e in porMoneda.entries) _resumenMoneda(e.key, e.value as Map),
                  if (proximos.isNotEmpty) ...[
                    Text("Cobros de este mes", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
                    Text("Atrasados primero, después por fecha.", style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                    const SizedBox(height: 6),
                    for (final c in proximos.take(8))
                      Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        color: AppColors.surface,
                        child: ListTile(
                          dense: true,
                          onTap: () => _abrir(c['prestamo'] as int),
                          leading: Icon(Icons.event_outlined, color: _colorAtraso(c['dias_atraso'] as int)),
                          title: Text('${c['cliente']}', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong)),
                          subtitle: Text(
                            (c['dias_atraso'] as int) > 0
                                ? "Atrasado ${c['dias_atraso']} días · préstamo #${c['numero_prestamo']}"
                                : "Vence ${_fecha(c['vencimiento'])}",
                            style: TextStyle(color: _colorAtraso(c['dias_atraso'] as int), fontSize: 12.5),
                          ),
                          trailing: Text(_dinero(c['monto'], '${c['moneda']}'), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textStrong)),
                        ),
                      ),
                    const SizedBox(height: 14),
                  ],
                  Row(children: [
                    Expanded(child: Text("Todos los préstamos", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textStrong))),
                    DropdownButton<String>(
                      value: _estado,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(value: 'activo', child: Text("Activos")),
                        DropdownMenuItem(value: 'cancelado', child: Text("Cancelados")),
                        DropdownMenuItem(value: '', child: Text("Todos")),
                      ],
                      onChanged: (v) {
                        setState(() => _estado = v ?? 'activo');
                        _cargar();
                      },
                    ),
                  ]),
                  TextField(
                    decoration: InputDecoration(
                      hintText: "Buscar por cliente, cédula, número o placa...",
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
                    ),
                    onChanged: (v) => setState(() => _busqueda = v.trim()),
                  ),
                  const SizedBox(height: 8),
                  if (lista.isEmpty)
                    Padding(padding: const EdgeInsets.all(24), child: Text("Nada por aquí.", textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted))),
                  for (final p in lista) _filaPrestamo(p),
                ],
              ),
            ),
    );
  }

  Widget _filaPrestamo(Map<String, dynamic> p) {
    final r = (p['resumen'] as Map?) ?? {};
    final dias = (r['dias_atraso'] ?? 0) as int;
    final vehiculo = (p['vehiculo'] as Map?) ?? {};
    final esVehiculo = p['tipo'] == 'vehiculo';
    final moneda = '${p['moneda']}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: AppColors.surface,
      child: ListTile(
        onTap: () => _abrir(p['id'] as int),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.12),
          child: Icon(esVehiculo ? Icons.directions_car_outlined : Icons.person_outline, color: AppColors.primary),
        ),
        title: Text("${p['cliente_nombre']}", style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong)),
        subtitle: Text(
          [
            "#${p['numero']}",
            if (esVehiculo) [vehiculo['marca'], vehiculo['modelo'], vehiculo['placa']].where((x) => '${x ?? ''}'.isNotEmpty).join(' ') else 'Personal',
            "${r['cuotas_pagadas']}/${r['cuotas_total']} cuotas",
            if (p['estado'] == 'cancelado') 'Cancelado' else if (dias > 0) 'Atrasado $dias días' else 'Al día',
          ].join(' · '),
          style: TextStyle(color: p['estado'] == 'activo' ? _colorAtraso(dias) : AppColors.textMuted, fontSize: 12.5),
        ),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(_dinero(r['saldo_capital'], moneda), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textStrong)),
          Text("saldo", style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ]),
      ),
    );
  }
}

// --------------------------------------------------------------------- Nuevo

class _NuevoPrestamo extends StatefulWidget {
  final Negocio negocio;
  const _NuevoPrestamo({required this.negocio});

  @override
  State<_NuevoPrestamo> createState() => _NuevoPrestamoState();
}

class _NuevoPrestamoState extends State<_NuevoPrestamo> {
  String _tipo = 'vehiculo';
  String _moneda = 'CRC';
  String _metodo = 'frances';
  Cliente? _cliente;
  List<Cliente> _clientes = [];
  DateTime _inicio = DateTime.now();
  int _dia = DateTime.now().day > 28 ? 28 : DateTime.now().day;
  final _precio = TextEditingController();
  final _prima = TextEditingController();
  final _monto = TextEditingController();
  final _tasa = TextEditingController();
  final _plazo = TextEditingController(text: '12');
  final _mora = TextEditingController();
  final _gracia = TextEditingController();
  final _garantia = TextEditingController();
  final _notas = TextEditingController();
  final _vehiculo = {for (final k in ['marca', 'modelo', 'anio', 'placa', 'vin', 'color']) k: TextEditingController()};
  Map<String, dynamic>? _simulacion;
  Timer? _espera;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
    for (final c in [_precio, _prima, _monto, _tasa, _plazo]) {
      c.addListener(_simularLuego);
    }
  }

  @override
  void dispose() {
    _espera?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final rs = await Future.wait([
        ApiService.get('/clientes/?negocio=${widget.negocio.id}'),
        ApiService.get('/prestamos-config/?negocio=${widget.negocio.id}'),
      ]);
      _clientes = (json.decode(utf8.decode(ApiService.verificar(rs[0]).bodyBytes)) as List).map((j) => Cliente.fromJson(j)).toList()
        ..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
      final config = json.decode(utf8.decode(ApiService.verificar(rs[1]).bodyBytes)) as Map<String, dynamic>;
      _mora.text = _n(config['tasa_mora_anual']) == 0 ? '' : '${config['tasa_mora_anual']}';
      _gracia.text = '${config['dias_gracia'] ?? 0}';
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    }
  }

  double _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;

  double get _financiado => _tipo == 'vehiculo' ? (_num(_precio) - _num(_prima)) : _num(_monto);

  void _simularLuego() {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 500), _simular);
  }

  Future<void> _simular() async {
    if (_financiado <= 0 || _num(_plazo) <= 0) {
      if (mounted) setState(() => _simulacion = null);
      return;
    }
    try {
      final r = await ApiService.post('/prestamos-simular/', {
        'monto': _financiado,
        'tasa_anual': _num(_tasa),
        'plazo_meses': _num(_plazo).toInt(),
        'metodo': _metodo,
        'fecha_inicio': _inicio.toIso8601String().substring(0, 10),
        'dia_pago': _dia,
      });
      if (r.statusCode == 200 && mounted) setState(() => _simulacion = json.decode(utf8.decode(r.bodyBytes)));
    } catch (_) {}
  }

  Future<void> _guardar() async {
    if (_cliente == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Elegí el cliente.")));
      return;
    }
    setState(() => _guardando = true);
    String t(TextEditingController c) => c.text.trim().replaceAll(',', '.');
    try {
      final datos = {
        'negocio': widget.negocio.id,
        'cliente': _cliente!.id,
        'tipo': _tipo,
        'moneda': _moneda,
        'fecha_inicio': _inicio.toIso8601String().substring(0, 10),
        'dia_pago': _dia,
        'monto': _financiado.toStringAsFixed(2),
        'tasa_anual': t(_tasa).isEmpty ? '0' : t(_tasa),
        'plazo_meses': _num(_plazo).toInt(),
        'metodo': _metodo,
        if (t(_mora).isNotEmpty) 'tasa_mora_anual': t(_mora),
        if (t(_gracia).isNotEmpty) 'dias_gracia': int.tryParse(t(_gracia)) ?? 0,
        'notas': _notas.text.trim(),
        if (_tipo == 'vehiculo') ...{
          'precio_venta': t(_precio),
          'prima': t(_prima).isEmpty ? '0' : t(_prima),
          'vehiculo': {for (final e in _vehiculo.entries) e.key: e.value.text.trim()},
        } else
          'garantia': _garantia.text.trim(),
      };
      ApiService.verificar(await ApiService.post('/prestamos/', datos));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
    }
    if (mounted) setState(() => _guardando = false);
  }

  Widget _campo(TextEditingController c, String etiqueta, {bool numero = false, String? ayuda, String? prefijo}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: numero ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          inputFormatters: numero ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))] : null,
          decoration: InputDecoration(labelText: etiqueta, helperText: ayuda, prefixText: prefijo, border: const OutlineInputBorder(), isDense: true),
        ),
      );

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
        child: Text(t, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
      );

  @override
  Widget build(BuildContext context) {
    final simbolo = _moneda == 'USD' ? '\$ ' : '₡ ';
    final cuotas = ((_simulacion?['cuotas'] as List?) ?? []).cast<Map>();
    return Scaffold(
      backgroundColor: AppColors.surfaceSubtle,
      appBar: AppBar(title: const Text("Nuevo préstamo"), backgroundColor: AppColors.surface, foregroundColor: AppColors.textStrong),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'vehiculo', icon: Icon(Icons.directions_car_outlined), label: Text("Venta de vehículo")),
              ButtonSegment(value: 'personal', icon: Icon(Icons.person_outline), label: Text("Préstamo personal")),
            ],
            selected: {_tipo},
            onSelectionChanged: (s) {
              setState(() => _tipo = s.first);
              _simularLuego();
            },
          ),
          _titulo("Cliente"),
          Autocomplete<Cliente>(
            displayStringForOption: (c) => "${c.nombre}${c.cedula.isNotEmpty ? ' · ${c.cedula}' : ''}",
            optionsBuilder: (v) {
              final b = v.text.toLowerCase();
              return _clientes.where((c) => b.isEmpty || c.nombre.toLowerCase().contains(b) || c.cedula.contains(b)).take(30);
            },
            onSelected: (c) => setState(() => _cliente = c),
            fieldViewBuilder: (ctx, ctrl, foco, alEnviar) => TextField(
              controller: ctrl,
              focusNode: foco,
              decoration: InputDecoration(
                labelText: "Buscar cliente por nombre o cédula *",
                helperText: _cliente == null ? "Si es nuevo, crealo primero en Clientes." : "Elegido: ${_cliente!.nombre}",
                prefixIcon: const Icon(Icons.person_search_outlined),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          if (_tipo == 'vehiculo') ...[
            _titulo("Vehículo"),
            Row(children: [
              Expanded(child: _campo(_vehiculo['marca']!, "Marca")),
              const SizedBox(width: 10),
              Expanded(child: _campo(_vehiculo['modelo']!, "Modelo")),
            ]),
            Row(children: [
              Expanded(child: _campo(_vehiculo['anio']!, "Año", numero: true)),
              const SizedBox(width: 10),
              Expanded(child: _campo(_vehiculo['placa']!, "Placa")),
            ]),
            Row(children: [
              Expanded(child: _campo(_vehiculo['vin']!, "VIN / chasis")),
              const SizedBox(width: 10),
              Expanded(child: _campo(_vehiculo['color']!, "Color")),
            ]),
          ],
          _titulo("Monto"),
          DropdownButtonFormField<String>(
            initialValue: _moneda,
            decoration: const InputDecoration(labelText: "Moneda", border: OutlineInputBorder(), isDense: true),
            items: const [DropdownMenuItem(value: 'CRC', child: Text("Colones")), DropdownMenuItem(value: 'USD', child: Text("Dólares"))],
            onChanged: (v) => setState(() => _moneda = v ?? 'CRC'),
          ),
          const SizedBox(height: 10),
          if (_tipo == 'vehiculo') ...[
            _campo(_precio, "Precio de venta *", numero: true, prefijo: simbolo),
            _campo(_prima, "Prima", numero: true, prefijo: simbolo,
                ayuda: _financiado > 0 ? "Se financia: ${_dinero(_financiado, _moneda)}" : "Lo que paga de entrada; se financia el resto."),
          ] else ...[
            _campo(_monto, "Monto del préstamo *", numero: true, prefijo: simbolo),
            _campo(_garantia, "Garantía o fiador", ayuda: "Opcional: pagaré, fiador, prenda..."),
          ],
          _titulo("Condiciones"),
          Row(children: [
            Expanded(child: _campo(_tasa, "Tasa anual (%) *", numero: true)),
            const SizedBox(width: 10),
            Expanded(child: _campo(_plazo, "Plazo (meses) *", numero: true)),
          ]),
          DropdownButtonFormField<String>(
            initialValue: _metodo,
            isExpanded: true,
            decoration: InputDecoration(labelText: "Forma de cálculo", helperText: _metodos[_metodo]!.$2, helperMaxLines: 2,
                border: const OutlineInputBorder(), isDense: true),
            items: [for (final e in _metodos.entries) DropdownMenuItem(value: e.key, child: Text(e.value.$1))],
            onChanged: (v) {
              setState(() => _metodo = v ?? 'frances');
              _simularLuego();
            },
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Fecha de inicio"),
                subtitle: Text(_fecha(_inicio.toIso8601String())),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final f = await showDatePicker(context: context, initialDate: _inicio, firstDate: DateTime(2015), lastDate: DateTime(2100));
                  if (f != null) {
                    setState(() => _inicio = f);
                    _simularLuego();
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 140,
              child: DropdownButtonFormField<int>(
                initialValue: _dia,
                decoration: const InputDecoration(labelText: "Día de pago", border: OutlineInputBorder(), isDense: true),
                items: [for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text("$d"))],
                onChanged: (v) {
                  setState(() => _dia = v ?? 1);
                  _simularLuego();
                },
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _campo(_mora, "Interés moratorio anual (%)", numero: true)),
            const SizedBox(width: 10),
            Expanded(child: _campo(_gracia, "Días de gracia", numero: true)),
          ]),
          _campo(_notas, "Notas"),
          if (_simulacion != null) ...[
            _titulo("Así quedarían las cuotas"),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  cuotas.isEmpty ? '' : "Cuota de ${_dinero(cuotas.first['total'], _moneda, decimales: 2)}"
                      "${_metodo == 'saldo' ? ' (va bajando)' : (_metodo == 'solo_interes' ? ' (y el capital al final)' : '')}",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textStrong),
                ),
                const SizedBox(height: 4),
                Text("Intereses en total: ${_dinero(_simulacion!['total_intereses'], _moneda)} · Total a pagar: ${_dinero(_simulacion!['total_a_pagar'], _moneda)}",
                    style: TextStyle(color: AppColors.textMuted)),
                if (cuotas.isNotEmpty)
                  Text("Primera cuota: ${_fecha(cuotas.first['vencimiento'])} · Última: ${_fecha(cuotas.last['vencimiento'])}",
                      style: TextStyle(color: AppColors.textMuted)),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text("Ver todas las cuotas"),
                  children: [
                    for (final c in cuotas)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          SizedBox(width: 30, child: Text("${c['numero']}", style: TextStyle(color: AppColors.textMuted))),
                          Expanded(child: Text(_fecha(c['vencimiento']))),
                          Text(_dinero(c['total'], _moneda, decimales: 2), style: const TextStyle(fontWeight: FontWeight.w700)),
                        ]),
                      ),
                  ],
                ),
              ]),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _guardando ? null : _guardar,
            icon: const Icon(Icons.check),
            label: Text(_guardando ? "Guardando..." : "Crear préstamo"),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- Detalle

class _DetallePrestamo extends StatefulWidget {
  final Negocio negocio;
  final int prestamoId;
  const _DetallePrestamo({required this.negocio, required this.prestamoId});

  @override
  State<_DetallePrestamo> createState() => _DetallePrestamoState();
}

class _DetallePrestamoState extends State<_DetallePrestamo> {
  Map<String, dynamic>? _p;
  bool _trabajando = false;

  String get _base => '/prestamos/${widget.prestamoId}/';
  String get _moneda => '${_p?['moneda'] ?? 'CRC'}';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _aviso(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _cargar() async {
    try {
      final r = ApiService.verificar(await ApiService.get(_base));
      if (mounted) setState(() => _p = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
    } catch (e) {
      if (mounted) _aviso(ApiService.textoError(e));
    }
  }

  Future<void> _accion(String ruta, Map<String, dynamic> datos, String listo) async {
    setState(() => _trabajando = true);
    try {
      final r = ApiService.verificar(await ApiService.post('$_base$ruta/', datos));
      setState(() => _p = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
      _aviso(listo);
    } catch (e) {
      _aviso(ApiService.textoError(e));
    }
    if (mounted) setState(() => _trabajando = false);
  }

  Future<void> _pagar() async {
    final r = (_p!['resumen'] as Map);
    final sugerido = _n(r['para_estar_al_dia']) > 0 ? _n(r['para_estar_al_dia']) : _n((r['proxima'] as Map?)?['monto']);
    final monto = TextEditingController(text: sugerido > 0 ? sugerido.toStringAsFixed(2) : '');
    final referencia = TextEditingController();
    String medio = '04';
    bool aCapital = false;
    DateTime fecha = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text("Registrar pago"),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (_n(r['para_estar_al_dia']) > 0)
                    ActionChip(label: Text("Para estar al día: ${_dinero(r['para_estar_al_dia'], _moneda, decimales: 2)}"),
                        onPressed: () => monto.text = _n(r['para_estar_al_dia']).toStringAsFixed(2)),
                  if (r['proxima'] != null)
                    ActionChip(label: Text("Próxima cuota: ${_dinero((r['proxima'] as Map)['monto'], _moneda, decimales: 2)}"),
                        onPressed: () => monto.text = _n((r['proxima'] as Map)['monto']).toStringAsFixed(2)),
                  ActionChip(label: Text("Cancelar todo: ${_dinero(r['saldo_total'], _moneda, decimales: 2)}"),
                      onPressed: () => monto.text = _n(r['saldo_total']).toStringAsFixed(2)),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: monto,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: "Monto", prefixText: _moneda == 'USD' ? '\$ ' : '₡ ', border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: medio,
                  decoration: const InputDecoration(labelText: "Cómo pagó", border: OutlineInputBorder()),
                  items: [for (final e in _medios.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => set(() => medio = v ?? '04'),
                ),
                const SizedBox(height: 10),
                TextField(controller: referencia, decoration: const InputDecoration(labelText: "Referencia / comprobante", border: OutlineInputBorder())),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Fecha del pago"),
                  subtitle: Text(_fecha(fecha.toIso8601String())),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final f = await showDatePicker(context: ctx, initialDate: fecha, firstDate: DateTime(2015), lastDate: DateTime.now());
                    if (f != null) set(() => fecha = f);
                  },
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: aCapital,
                  onChanged: (v) => set(() => aCapital = v ?? false),
                  title: const Text("Abono extraordinario a capital"),
                  subtitle: const Text("Todo va a capital y bajan las cuotas que faltan. Solo si está al día."),
                ),
                Text("Un pago normal se aplica primero a la mora, después a intereses y después a capital, de la cuota más vieja a la más nueva.",
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Registrar")),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _accion('pagar', {
      'monto': monto.text.trim().replaceAll(',', '.'),
      'medio_pago': medio,
      'referencia': referencia.text.trim(),
      'fecha': fecha.toIso8601String().substring(0, 10),
      'a_capital': aCapital,
    }, "Pago registrado.");
  }

  Future<void> _anularPago(Map pago) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Anular este pago?"),
        content: Text("${_dinero(pago['monto'], _moneda, decimales: 2)} del ${_fecha(pago['fecha'])}. Lo que cubrió vuelve a deberse."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Anular", style: TextStyle(color: _rojo))),
        ],
      ),
    );
    if (ok == true) await _accion('anular-pago', {'pago': pago['id']}, "Pago anulado.");
  }

  Future<void> _copiarEnlace() async {
    await Clipboard.setData(ClipboardData(text: '${_p!['enlace']}'));
    _aviso("Enlace copiado. Mandáselo al cliente: ahí ve su estado de cuenta, cómo pagar y sube el comprobante.");
  }

  Widget _dato(String etiqueta, String valor, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(etiqueta, style: TextStyle(color: AppColors.textMuted))),
          Text(valor, style: TextStyle(fontWeight: FontWeight.w700, color: color ?? AppColors.textStrong)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final r = (p['resumen'] as Map);
    final cuotas = ((p['cuotas'] as List?) ?? []).cast<Map>();
    final pagos = ((p['pagos'] as List?) ?? []).cast<Map>();
    final vehiculo = (p['vehiculo'] as Map?) ?? {};
    final dias = (r['dias_atraso'] ?? 0) as int;
    final ultimoPagoVivo = pagos.where((x) => x['anulado'] != true).firstOrNull;
    final reportes = ((p['reportes'] as List?) ?? []).cast<Map>();
    return Scaffold(
      backgroundColor: AppColors.surfaceSubtle,
      appBar: AppBar(
        title: Text("Préstamo #${p['numero']}"),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
        bottom: _trabajando ? const PreferredSize(preferredSize: Size.fromHeight(3), child: LinearProgressIndicator(minHeight: 3)) : null,
        actions: [
          if (p['enlace'] != null) ...[
            IconButton(
              tooltip: "Mandar recordatorio por WhatsApp",
              icon: const Icon(Icons.chat_outlined),
              onPressed: () => abrirWhatsApp(context, '${p['cliente_telefono'] ?? ''}', '${p['mensaje_whatsapp']}'),
            ),
            IconButton(tooltip: "Copiar enlace de estado de cuenta y pago", icon: const Icon(Icons.link), onPressed: _copiarEnlace),
          ],
        ],
      ),
      floatingActionButton: p['estado'] == 'activo'
          ? FloatingActionButton.extended(onPressed: _trabajando ? null : _pagar, icon: const Icon(Icons.payments_outlined), label: const Text("Registrar pago"))
          : null,
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
          children: [
            Text("${p['cliente_nombre']}", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
            Text(
              [
                if ((p['cliente_cedula'] ?? '').toString().isNotEmpty) "Cédula ${p['cliente_cedula']}",
                if ((p['cliente_telefono'] ?? '').toString().isNotEmpty) "Tel. ${p['cliente_telefono']}",
              ].join(' · '),
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
              child: Column(children: [
                Row(children: [
                  Icon(p['estado'] == 'cancelado' ? Icons.verified_outlined : (dias > 0 ? Icons.warning_amber_rounded : Icons.check_circle_outline),
                      color: p['estado'] == 'cancelado' ? _verde : _colorAtraso(dias)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p['estado'] == 'cancelado'
                          ? "Cancelado"
                          : p['estado'] == 'anulado'
                              ? "Anulado"
                              : (dias > 0 ? "Atrasado $dias días (${r['cuotas_vencidas']} cuota${r['cuotas_vencidas'] == 1 ? '' : 's'})" : "Al día"),
                      style: TextStyle(fontWeight: FontWeight.w800, color: p['estado'] == 'activo' ? _colorAtraso(dias) : AppColors.textStrong),
                    ),
                  ),
                ]),
                const Divider(height: 18),
                _dato("Saldo de capital", _dinero(r['saldo_capital'], _moneda, decimales: 2)),
                if (_n(r['para_estar_al_dia']) > 0)
                  _dato("Para estar al día", _dinero(r['para_estar_al_dia'], _moneda, decimales: 2), color: _rojo),
                if (_n(r['mora']) > 0) _dato("Mora a hoy", _dinero(r['mora'], _moneda, decimales: 2), color: _rojo),
                if (r['proxima'] != null)
                  _dato("Próxima cuota (${_fecha((r['proxima'] as Map)['vencimiento'])})", _dinero((r['proxima'] as Map)['monto'], _moneda, decimales: 2)),
                _dato("Cuotas pagadas", "${r['cuotas_pagadas']} de ${r['cuotas_total']}"),
              ]),
            ),
            const SizedBox(height: 12),
            if (reportes.isNotEmpty) ...[
              Text("Pagos reportados por el cliente", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
              const SizedBox(height: 6),
              for (final rep in reportes) _TarjetaReporte(rep: rep, onResuelto: _cargar),
              const SizedBox(height: 6),
            ],
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text("Condiciones", style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textStrong)),
              children: [
                _dato("Tipo", p['tipo'] == 'vehiculo' ? "Venta de vehículo a plazo" : "Préstamo personal"),
                if (p['tipo'] == 'vehiculo') ...[
                  _dato("Vehículo", [vehiculo['marca'], vehiculo['modelo'], vehiculo['anio']].where((x) => '${x ?? ''}'.isNotEmpty).join(' ')),
                  if ('${vehiculo['placa'] ?? ''}'.isNotEmpty) _dato("Placa", '${vehiculo['placa']}'),
                  if ('${vehiculo['vin'] ?? ''}'.isNotEmpty) _dato("VIN", '${vehiculo['vin']}'),
                  _dato("Precio de venta", _dinero(p['precio_venta'], _moneda)),
                  _dato("Prima", _dinero(p['prima'], _moneda)),
                ],
                if ('${p['garantia'] ?? ''}'.isNotEmpty) _dato("Garantía", '${p['garantia']}'),
                _dato("Financiado", _dinero(p['monto'], _moneda)),
                _dato("Tasa anual", "${p['tasa_anual']}%"),
                _dato("Plazo", "${p['plazo_meses']} meses · día ${p['dia_pago']}"),
                _dato("Forma de cálculo", _metodos[p['metodo']]?.$1 ?? '${p['metodo']}'),
                _dato("Mora", "${p['tasa_mora_anual']}% anual · ${p['dias_gracia']} días de gracia"),
                _dato("Desde", _fecha(p['fecha_inicio'])),
              ],
            ),
            const SizedBox(height: 6),
            Text("Cuotas", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
            const SizedBox(height: 6),
            for (final c in cuotas)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
                child: Row(children: [
                  SizedBox(width: 28, child: Text("${c['numero']}", style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700))),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_fecha(c['vencimiento']), style: TextStyle(color: AppColors.textStrong)),
                      Text("Capital ${_dinero(c['capital'], _moneda)} · Interés ${_dinero(c['interes'], _moneda)}"
                          "${_n(c['mora']) > 0 ? ' · Mora ${_dinero(c['mora'], _moneda)}' : ''}",
                          style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(_dinero(c['total'], _moneda, decimales: 2), style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong)),
                    Text(
                      switch (c['estado']) {
                        'pagada' => "Pagada",
                        'vencida' => "Vencida · falta ${_dinero(c['pendiente'], _moneda)}",
                        'parcial' => "Falta ${_dinero(c['pendiente'], _moneda)}",
                        _ => "Pendiente",
                      },
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: switch (c['estado']) { 'pagada' => _verde, 'vencida' => _rojo, 'parcial' => _ambar, _ => AppColors.textMuted },
                      ),
                      textAlign: TextAlign.end,
                    ),
                  ]),
                  ),
                ]),
              ),
            const SizedBox(height: 14),
            Text("Pagos", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
            if (pagos.isEmpty) Padding(padding: const EdgeInsets.all(8), child: Text("Todavía no hay pagos.", style: TextStyle(color: AppColors.textMuted))),
            for (final g in pagos)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(g['a_capital'] == true ? Icons.trending_down : Icons.south_west, color: g['anulado'] == true ? AppColors.textMuted : _verde),
                title: Text(
                  "${_dinero(g['monto'], _moneda, decimales: 2)}${g['a_capital'] == true ? ' · abono a capital' : ''}",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: g['anulado'] == true ? AppColors.textMuted : AppColors.textStrong,
                    decoration: g['anulado'] == true ? TextDecoration.lineThrough : null,
                  ),
                ),
                subtitle: Text("${_fecha(g['fecha'])} · ${g['medio_pago_nombre']}${'${g['referencia'] ?? ''}'.isNotEmpty ? ' · ${g['referencia']}' : ''}"
                    "${g['anulado'] == true ? ' · anulado' : ''}"),
                trailing: g == ultimoPagoVivo && g['a_capital'] != true && p['estado'] != 'anulado'
                    ? IconButton(tooltip: "Anular este pago", icon: const Icon(Icons.undo), onPressed: _trabajando ? null : () => _anularPago(g))
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- WhatsApp

/// Deudores con cuota en los próximos días o atrasados, con el mensaje listo
/// (monto exacto y enlace). Un toque abre WhatsApp; el negocio lo envía.
class _RecordatoriosWhatsApp extends StatefulWidget {
  final Negocio negocio;
  const _RecordatoriosWhatsApp({required this.negocio});

  @override
  State<_RecordatoriosWhatsApp> createState() => _RecordatoriosWhatsAppState();
}

class _RecordatoriosWhatsAppState extends State<_RecordatoriosWhatsApp> {
  List<Map<String, dynamic>>? _filas;
  final Set<int> _enviados = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final r = ApiService.verificar(await ApiService.get('/prestamos-whatsapp/?negocio=${widget.negocio.id}'));
      if (mounted) setState(() => _filas = (json.decode(utf8.decode(r.bodyBytes)) as List).cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) {
        setState(() => _filas = []);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.textoError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filas = _filas;
    return Scaffold(
      backgroundColor: AppColors.surfaceSubtle,
      appBar: AppBar(title: const Text("Recordatorios por WhatsApp"), backgroundColor: AppColors.surface, foregroundColor: AppColors.textStrong),
      body: filas == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Text("Atrasados primero y después las cuotas que vencen en los próximos días. Cada mensaje lleva el monto exacto y el enlace para pagar.",
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  const SizedBox(height: 10),
                  if (filas.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text("Nadie a quien recordarle hoy.", textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
                    ),
                  for (final f in filas)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: AppColors.surface,
                      child: ListTile(
                        leading: Icon(
                          _enviados.contains(f['prestamo']) ? Icons.done_all : Icons.chat_outlined,
                          color: _enviados.contains(f['prestamo']) ? _verde : _colorAtraso(f['dias_atraso'] as int),
                        ),
                        title: Text('${f['cliente']}', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong)),
                        subtitle: Text(
                          [
                            (f['dias_atraso'] as int) > 0 ? "Atrasado ${f['dias_atraso']} días" : "Vence ${_fecha(f['vencimiento'])}",
                            _dinero(f['monto'], '${f['moneda']}', decimales: 2),
                            if ('${f['telefono']}'.isEmpty) "sin teléfono",
                          ].join(' · '),
                          style: TextStyle(fontSize: 12.5, color: _colorAtraso(f['dias_atraso'] as int)),
                        ),
                        trailing: FilledButton.tonal(
                          onPressed: () async {
                            await abrirWhatsApp(context, '${f['telefono']}', '${f['mensaje']}');
                            setState(() => _enviados.add(f['prestamo'] as int));
                          },
                          child: const Text("Enviar"),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
