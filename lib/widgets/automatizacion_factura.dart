import 'dart:convert';

import 'package:flutter/material.dart';

import '../api_service.dart';
import '../factura.dart';
import '../formato.dart';
import '../theme/app_theme.dart';

/// Tarjeta "Automático" del detalle de una factura (ver
/// gestion/automatizaciones.py en el backend):
/// - Repetir automáticamente: la factura se vuelve a emitir sola cada
///   semana/15 días/mes/trimestre/año (alquileres, mensualidades).
/// - Cobro automático (solo facturas a crédito): recordatorios por correo al
///   cliente antes y después de que venza.
class AutomatizacionFactura extends StatefulWidget {
  final Factura factura;
  const AutomatizacionFactura({super.key, required this.factura});

  @override
  State<AutomatizacionFactura> createState() => _AutomatizacionFacturaState();
}

const _frecuencias = {
  'semanal': 'Cada semana',
  'quincenal': 'Cada 15 días',
  'mensual': 'Cada mes',
  'trimestral': 'Cada 3 meses',
  'anual': 'Cada año',
};

const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'set', 'oct', 'nov', 'dic'];

String _fecha(String? iso) {
  final f = DateTime.tryParse(iso ?? '');
  return f == null ? '' : "${f.day} ${_meses[f.month - 1]} ${f.year}";
}

String _iso(DateTime f) => "${f.year}-${f.month.toString().padLeft(2, '0')}-${f.day.toString().padLeft(2, '0')}";

class _AutomatizacionFacturaState extends State<AutomatizacionFactura> {
  Map<String, dynamic>? _datos;
  bool _cargando = true;
  bool _guardando = false;

  Factura get _f => widget.factura;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final r = await ApiService.get('/facturas/${_f.id}/automatizaciones/');
      if (r.statusCode == 200 && mounted) {
        setState(() => _datos = Map<String, dynamic>.from(json.decode(utf8.decode(r.bodyBytes)) as Map));
      }
    } catch (_) {
      // Sin datos, la tarjeta no se muestra.
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _ejecutar(Future<dynamic> Function() accion, String exito) async {
    setState(() => _guardando = true);
    try {
      final r = await accion();
      if (r.statusCode >= 300) {
        final cuerpo = utf8.decode(r.bodyBytes);
        throw Exception(cuerpo.length > 300 ? cuerpo.substring(0, 300) : cuerpo);
      }
      await _cargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(exito), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo guardar: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // ------------------------------------------------------------ recurrencia

  Future<void> _dialogoRecurrencia({Map<String, dynamic>? actual}) async {
    final hoy = DateUtils.dateOnly(DateTime.now());
    String frecuencia = actual?['frecuencia'] ?? 'mensual';
    DateTime proxima = DateTime.tryParse(actual?['proxima_fecha'] ?? '') ?? DateTime(hoy.year, hoy.month + 1, DateTime.tryParse(_f.fechaEmision)?.day ?? hoy.day);
    if (proxima.isBefore(hoy)) proxima = hoy;
    DateTime? fin = DateTime.tryParse(actual?['fecha_fin'] ?? '');

    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(actual == null ? "Repetir esta factura" : "Cambiar la repetición"),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Se emite sola, con la fecha del día, los mismos productos y precios"
                  "${_f.moneda == 'USD' ? ' (en dólares, al tipo de cambio de ese día)' : ''}, y se envía a Hacienda y al cliente.",
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
                const SizedBox(height: 14),
                const Text("¿Cada cuánto?", style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final e in _frecuencias.entries)
                      ChoiceChip(label: Text(e.value), selected: frecuencia == e.key, onSelected: (_) => set(() => frecuencia = e.key), showCheckmark: false),
                  ],
                ),
                const SizedBox(height: 14),
                _filaFecha(ctx, "Primera emisión", proxima, (d) => set(() => proxima = d), hoy),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: Text("Hasta una fecha", style: TextStyle(color: AppColors.textStrong))),
                    Switch(
                      value: fin != null,
                      onChanged: (v) => set(() => fin = v ? DateTime(proxima.year + 1, proxima.month, proxima.day) : null),
                    ),
                  ],
                ),
                if (fin != null) _filaFecha(ctx, "Última emisión", fin!, (d) => set(() => fin = d), proxima),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Guardar")),
          ],
        ),
      ),
    );
    if (guardar != true) return;
    final datos = {
      'negocio': _f.negocio,
      'plantilla': _f.id,
      'frecuencia': frecuencia,
      'proxima_fecha': _iso(proxima),
      'fecha_fin': fin == null ? null : _iso(fin!),
      'activa': true,
    };
    await _ejecutar(
      () => actual == null ? ApiService.post('/facturas-recurrentes/', datos) : ApiService.patch('/facturas-recurrentes/${actual['id']}/', datos),
      "Listo: esta factura se va a emitir sola, ${_frecuencias[frecuencia]!.toLowerCase()}.",
    );
  }

  Widget _filaFecha(BuildContext ctx, String titulo, DateTime valor, ValueChanged<DateTime> cambiar, DateTime desde) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final d = await showDatePicker(context: ctx, initialDate: valor, firstDate: desde, lastDate: DateTime(desde.year + 5));
          if (d != null) cambiar(d);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(Icons.event_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(titulo)),
              Text(_fecha(_iso(valor)), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 4),
              Icon(Icons.edit_rounded, size: 15, color: AppColors.textMuted),
            ],
          ),
        ),
      );

  Widget _seccionRecurrencia() {
    final rec = _datos?['recurrencia'] as Map?;
    if (rec == null) {
      return _bloque(
        icono: Icons.event_repeat_rounded,
        titulo: "Repetir automáticamente",
        detalle: "Para cobros fijos (alquiler, mensualidad): se emite sola cada mes con la fecha del día.",
        acciones: [FilledButton.tonalIcon(onPressed: _guardando ? null : () => _dialogoRecurrencia(), icon: const Icon(Icons.add_rounded, size: 18), label: const Text("Programar"))],
      );
    }
    final activa = rec['activa'] == true;
    final error = (rec['ultimo_error'] as String?) ?? '';
    return _bloque(
      icono: Icons.event_repeat_rounded,
      titulo: "Se repite ${(rec['frecuencia_texto'] ?? '').toString().toLowerCase()}",
      chip: activa ? ("Activa", Colors.green) : ("Pausada", Colors.orange),
      detalle: [
        if (activa) "Próxima: ${_fecha(rec['proxima_fecha'])}",
        if (rec['fecha_fin'] != null) "hasta ${_fecha(rec['fecha_fin'])}",
        "${rec['emitidas']} emitida${rec['emitidas'] == 1 ? '' : 's'}",
        if (rec['ultima_factura_consecutivo'] != null) "última: ${rec['ultima_factura_consecutivo']}",
      ].join(" · "),
      error: error.isEmpty ? null : "No se pudo emitir la última vez: $error",
      acciones: [
        OutlinedButton(
          onPressed: _guardando
              ? null
              : () => _ejecutar(
                    () => ApiService.patch('/facturas-recurrentes/${rec['id']}/', {'activa': !activa}),
                    activa ? "Repetición pausada." : "Repetición reanudada.",
                  ),
          child: Text(activa ? "Pausar" : "Reanudar"),
        ),
        OutlinedButton(onPressed: _guardando ? null : () => _dialogoRecurrencia(actual: Map<String, dynamic>.from(rec)), child: const Text("Cambiar")),
        TextButton(
          onPressed: _guardando
              ? null
              : () => _ejecutar(() => ApiService.delete('/facturas-recurrentes/${rec['id']}/'), "Ya no se repite."),
          child: const Text("Quitar", style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ cobro

  Future<void> _dialogoCobro(Map<String, dynamic> config) async {
    var c = Map<String, dynamic>.from(config);
    c['activo'] = true;
    Widget opciones(String titulo, String clave, List<int> valores, String Function(int) texto, StateSetter set) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final v in valores)
                  ChoiceChip(label: Text(texto(v)), selected: c[clave] == v, onSelected: (_) => set(() => c[clave] = v), showCheckmark: false),
              ],
            ),
            const SizedBox(height: 12),
          ],
        );
    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text("Cobro automático"),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "A los clientes con facturas a crédito sin pagar les llega un correo con la factura en PDF. "
                    "Vale para todas las facturas a crédito del negocio (cada una se puede apagar aparte).",
                    style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 14),
                  opciones("Antes de vencer", 'dias_antes', [0, 1, 3, 5, 7], (v) => v == 0 ? "No avisar" : "$v día${v == 1 ? '' : 's'} antes", set),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Avisar el día que vence"),
                    value: c['al_vencer'] == true,
                    onChanged: (v) => set(() => c['al_vencer'] = v),
                  ),
                  opciones("Si ya venció, insistir", 'cada_dias_despues', [0, 3, 7, 15], (v) => v == 0 ? "No" : "Cada $v días", set),
                  opciones("Máximo por factura", 'max_recordatorios', [2, 4, 6, 10], (v) => "$v correos", set),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Mandarme copia"),
                    subtitle: const Text("Al correo del negocio"),
                    value: c['copia_al_negocio'] == true,
                    onChanged: (v) => set(() => c['copia_al_negocio'] = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (config['activo'] == true)
              TextButton(
                onPressed: () {
                  c['activo'] = false;
                  Navigator.pop(ctx, true);
                },
                child: const Text("Apagar", style: TextStyle(color: Colors.red)),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Guardar y encender")),
          ],
        ),
      ),
    );
    if (guardar != true) return;
    await _ejecutar(
      () => ApiService.patch('/cobro-automatico/?negocio=${_f.negocio}', c),
      c['activo'] == true ? "Cobro automático encendido." : "Cobro automático apagado.",
    );
  }

  Widget? _seccionCobro() {
    final cobro = _datos?['cobro'] as Map?;
    if (cobro == null || cobro['aplica'] != true) return null;
    final config = Map<String, dynamic>.from(cobro['config'] as Map);
    final saldo = double.tryParse('${cobro['saldo']}') ?? 0;
    final saldoTexto = _f.esEnDolares ? formatearDolares(saldo / _f.tipoCambio) : formatearColones(saldo);
    if (config['activo'] != true) {
      return _bloque(
        icono: Icons.notifications_active_outlined,
        titulo: "Cobro automático",
        chip: ("Apagado", Colors.grey),
        detalle: "Recordatorios por correo al cliente antes y después de que venza esta factura (vence el ${_fecha(cobro['vencimiento'])}).",
        acciones: [FilledButton.tonalIcon(onPressed: _guardando ? null : () => _dialogoCobro(config), icon: const Icon(Icons.power_settings_new_rounded, size: 18), label: const Text("Encender"))],
      );
    }
    final enFactura = cobro['activo_en_factura'] == true;
    final recordatorios = (cobro['recordatorios'] as List?) ?? [];
    final estado = cobro['pagada'] == true
        ? "Pagada: no se mandan recordatorios."
        : cobro['aceptada'] != true
            ? "Se empieza a cobrar cuando Hacienda la acepte."
            : !enFactura
                ? "Apagado solo para esta factura."
                : cobro['proximo'] != null
                    ? "Próximo recordatorio: ${_fecha(cobro['proximo'])}"
                    : "No quedan recordatorios por mandar.";
    return _bloque(
      icono: Icons.notifications_active_outlined,
      titulo: "Cobro automático",
      chip: enFactura ? ("Activo", Colors.green) : ("Apagado aquí", Colors.orange),
      detalle: "Vence el ${_fecha(cobro['vencimiento'])} · saldo $saldoTexto\n$estado",
      extra: recordatorios.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                for (final r in recordatorios.take(5))
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      children: [
                        Icon(r['enviado'] == true ? Icons.mark_email_read_outlined : Icons.error_outline, size: 15, color: r['enviado'] == true ? Colors.green : Colors.orange),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            "${_fecha(r['fecha'])} · ${r['tipo_texto']}${r['enviado'] == true ? ' · ${r['correo']}' : ' · ${r['detalle']}'}",
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
      acciones: [
        if (cobro['pagada'] != true)
          OutlinedButton(
            onPressed: _guardando
                ? null
                : () => _ejecutar(
                      () => ApiService.post('/facturas/${_f.id}/cobro-automatico/', {'activo': !enFactura}),
                      enFactura ? "No se le van a mandar recordatorios por esta factura." : "Recordatorios encendidos para esta factura.",
                    ),
            child: Text(enFactura ? "Apagar en esta factura" : "Encender en esta factura"),
          ),
        TextButton(onPressed: _guardando ? null : () => _dialogoCobro(config), child: const Text("Ajustar")),
      ],
    );
  }

  // ------------------------------------------------------------ diseño

  Widget _bloque({
    required IconData icono,
    required String titulo,
    required String detalle,
    (String, Color)? chip,
    String? error,
    Widget? extra,
    List<Widget> acciones = const [],
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, size: 19, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(titulo, style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textStrong))),
              if (chip != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: chip.$2.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                  child: Text(chip.$1, style: TextStyle(color: chip.$2, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(detalle, style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.35)),
          if (error != null) ...[
            const SizedBox(height: 6),
            Text(error, style: const TextStyle(fontSize: 12, color: Colors.orange)),
          ],
          if (extra != null) extra,
          if (acciones.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: acciones),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando || _datos == null) return const SizedBox.shrink();
    final cobro = _seccionCobro();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Divider(),
        Row(
          children: [
            Text("AUTOMÁTICO", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
            if (_guardando) ...[
              const SizedBox(width: 8),
              const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ],
        ),
        const SizedBox(height: 10),
        _seccionRecurrencia(),
        if (cobro != null) ...[const SizedBox(height: 10), cobro],
      ],
    );
  }
}
