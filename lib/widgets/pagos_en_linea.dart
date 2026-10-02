import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_service.dart';
import '../formato.dart';
import '../theme/app_theme.dart';

/// Pagos en línea (paso 1): cada factura a crédito tiene una página pública
/// de pago con los datos de SINPE/transferencia del negocio, donde el
/// cliente sube el comprobante (la IA lo lee). Acá: la configuración de los
/// datos de pago, los pagos reportados (confirmar/rechazar) y el aviso del
/// dashboard. Ver gestion/pagos_en_linea.py en el backend.

/// Ventana "Datos de pago" del negocio. Devuelve los datos guardados o null.
Future<Map<String, dynamic>?> configurarDatosPago(BuildContext context, {required int negocioId}) async {
  Map<String, dynamic> datos = {};
  try {
    final r = await ApiService.get('/datos-pago/?negocio=$negocioId');
    if (r.statusCode == 200) datos = Map<String, dynamic>.from(json.decode(utf8.decode(r.bodyBytes)) as Map);
  } catch (_) {}
  if (!context.mounted) return null;
  final campos = {
    'sinpe_numero': TextEditingController(text: datos['sinpe_numero'] ?? ''),
    'sinpe_titular': TextEditingController(text: datos['sinpe_titular'] ?? ''),
    'banco': TextEditingController(text: datos['banco'] ?? ''),
    'iban': TextEditingController(text: datos['iban'] ?? ''),
    'titular_cuenta': TextEditingController(text: datos['titular_cuenta'] ?? ''),
    'instrucciones': TextEditingController(text: datos['instrucciones'] ?? ''),
  };
  var autoconfirmar = datos['autoconfirmar'] == true;
  var enCorreos = datos['enlace_en_correos'] != false;

  Widget campo(String clave, String etiqueta, {String? ayuda, TextInputType? tipo, int lineas = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: campos[clave],
          keyboardType: tipo,
          maxLines: lineas,
          decoration: InputDecoration(labelText: etiqueta, helperText: ayuda, isDense: true, border: const OutlineInputBorder()),
        ),
      );

  final guardar = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text("Datos de pago"),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Salen en la página de pago de tus facturas a crédito. Tu cliente paga y sube el comprobante; la IA lo lee y te avisa.",
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
                const SizedBox(height: 14),
                const Text("SINPE Móvil", style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                campo('sinpe_numero', "Número", tipo: TextInputType.phone),
                campo('sinpe_titular', "A nombre de"),
                const SizedBox(height: 4),
                const Text("Transferencia bancaria", style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                campo('banco', "Banco"),
                campo('iban', "Cuenta IBAN", ayuda: "Ej. CR05 0152 0200 1026 2840 66"),
                campo('titular_cuenta', "A nombre de"),
                campo('instrucciones', "Indicaciones para el cliente (opcional)", lineas: 2),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Confirmar solo si el comprobante coincide"),
                  subtitle: const Text("Si el monto leído es igual al saldo, se registra el abono sin esperar tu revisión."),
                  value: autoconfirmar,
                  onChanged: (v) => set(() => autoconfirmar = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Botón \"Pagar\" en los correos"),
                  subtitle: const Text("En el correo de la factura a crédito y en los recordatorios."),
                  value: enCorreos,
                  onChanged: (v) => set(() => enCorreos = v),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Guardar")),
        ],
      ),
    ),
  );
  if (guardar != true) return null;
  final cuerpo = {
    for (final e in campos.entries) e.key: e.value.text.trim(),
    'autoconfirmar': autoconfirmar,
    'enlace_en_correos': enCorreos,
  };
  try {
    final r = await ApiService.patch('/datos-pago/?negocio=$negocioId', cuerpo);
    if (r.statusCode >= 300) throw Exception(utf8.decode(r.bodyBytes));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Datos de pago guardados."), backgroundColor: Colors.green));
    }
    return Map<String, dynamic>.from(json.decode(utf8.decode(r.bodyBytes)) as Map);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo guardar: $e"), backgroundColor: Colors.red));
    }
    return null;
  }
}

String _monto(Map p, dynamic colones) {
  final v = double.tryParse('${colones ?? ''}');
  if (v == null) return "—";
  final tc = double.tryParse('${p['factura_tipo_cambio'] ?? 1}') ?? 1;
  return p['factura_moneda'] == 'USD' && tc > 1 ? formatearDolares(v / tc) : formatearColones(v);
}

/// Un pago reportado con sus acciones. `onCambio` se llama después de
/// confirmarlo o rechazarlo.
class PagoReportadoTile extends StatefulWidget {
  final Map<String, dynamic> pago;
  final VoidCallback onCambio;
  final bool mostrarFactura;
  const PagoReportadoTile({super.key, required this.pago, required this.onCambio, this.mostrarFactura = true});

  @override
  State<PagoReportadoTile> createState() => _PagoReportadoTileState();
}

class _PagoReportadoTileState extends State<PagoReportadoTile> {
  bool _trabajando = false;

  Future<void> _accion(String accion) async {
    String? nota;
    if (accion == 'rechazar') {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Rechazar pago"),
          content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: "Motivo (opcional)")),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Rechazar")),
          ],
        ),
      );
      if (ok != true) return;
      nota = ctrl.text.trim();
    }
    setState(() => _trabajando = true);
    try {
      final r = await ApiService.post('/pagos-reportados/${widget.pago['id']}/$accion/', {if (nota != null) 'nota': nota});
      if (r.statusCode >= 300) {
        final d = json.decode(utf8.decode(r.bodyBytes));
        throw Exception(d is Map ? (d['detail'] ?? d) : d);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(accion == 'confirmar' ? "Pago confirmado: abono registrado y recibo enviado a Hacienda." : "Pago rechazado."),
          backgroundColor: accion == 'confirmar' ? Colors.green : null,
        ));
      }
      widget.onCambio();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pago;
    final pendiente = p['estado'] == 'pendiente';
    final coincide = p['coincide'] == true;
    final fecha = DateTime.tryParse('${p['creado']}')?.toLocal();
    final color = pendiente ? (coincide ? Colors.green : Colors.orange) : (p['estado'] == 'confirmado' ? Colors.green : Colors.grey);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: pendiente ? color.withValues(alpha: 0.5) : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_rounded, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.mostrarFactura ? "${p['cliente'] ?? 'Cliente'} · ${p['factura_consecutivo']}" : (p['nombre_pagador']?.toString().isNotEmpty == true ? p['nombre_pagador'] : "Pago reportado"),
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                child: Text(
                  pendiente ? (coincide ? "Coincide" : "Revisar") : "${p['estado_texto']}",
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "Comprobante: ${_monto(p, p['monto_detectado'])} · saldo: ${_monto(p, p['saldo'])}"
            "${p['referencia']?.toString().isNotEmpty == true ? ' · ref. ${p['referencia']}' : ''}"
            "${fecha != null ? ' · ${fecha.day}/${fecha.month} ${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}' : ''}",
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          ),
          if (!pendiente && (p['nota'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text("${p['nota']}", style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontStyle: FontStyle.italic)),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (p['comprobante_url'] != null)
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse(p['comprobante_url']), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.visibility_outlined, size: 17),
                  label: const Text("Ver comprobante"),
                ),
              if (pendiente) ...[
                FilledButton.icon(
                  onPressed: _trabajando ? null : () => _accion('confirmar'),
                  icon: _trabajando
                      ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_rounded, size: 18),
                  label: const Text("Confirmar"),
                ),
                TextButton(onPressed: _trabajando ? null : () => _accion('rechazar'), child: const Text("Rechazar")),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Lista de pagos reportados del negocio (por confirmar primero).
class PagosReportadosScreen extends StatefulWidget {
  final int negocioId;
  const PagosReportadosScreen({super.key, required this.negocioId});

  @override
  State<PagosReportadosScreen> createState() => _PagosReportadosScreenState();
}

class _PagosReportadosScreenState extends State<PagosReportadosScreen> {
  List<Map<String, dynamic>>? _pagos;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final r = await ApiService.get('/pagos-reportados/?negocio=${widget.negocioId}');
      if (r.statusCode == 200) {
        final d = json.decode(utf8.decode(r.bodyBytes));
        final lista = (d is Map ? d['results'] : d) as List;
        final pagos = lista.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          ..sort((a, b) => (a['estado'] == 'pendiente' ? 0 : 1).compareTo(b['estado'] == 'pendiente' ? 0 : 1));
        if (mounted) setState(() => _pagos = pagos);
      }
    } catch (_) {
      if (mounted) setState(() => _pagos = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pagos reportados"),
        actions: [
          IconButton(
            tooltip: "Datos de pago",
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => configurarDatosPago(context, negocioId: widget.negocioId),
          ),
        ],
      ),
      body: _pagos == null
          ? const Center(child: CircularProgressIndicator())
          : _pagos!.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      "Todavía no hay pagos reportados. Cuando un cliente pague desde el enlace de su factura y suba el comprobante, aparece acá.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [for (final p in _pagos!) PagoReportadoTile(pago: p, onCambio: _cargar)],
                  ),
                ),
    );
  }
}

/// Aviso del dashboard: "N pagos por confirmar" (no se muestra si no hay).
class AvisoPagosPorConfirmar extends StatefulWidget {
  final int negocioId;
  const AvisoPagosPorConfirmar({super.key, required this.negocioId});

  @override
  State<AvisoPagosPorConfirmar> createState() => _AvisoPagosPorConfirmarState();
}

class _AvisoPagosPorConfirmarState extends State<AvisoPagosPorConfirmar> {
  int _cantidad = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final r = await ApiService.get('/pagos-reportados/?negocio=${widget.negocioId}&estado=pendiente');
      if (r.statusCode == 200) {
        final d = json.decode(utf8.decode(r.bodyBytes));
        final lista = (d is Map ? d['results'] : d) as List;
        if (mounted) setState(() => _cantidad = lista.length);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_cantidad == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => PagosReportadosScreen(negocioId: widget.negocioId)));
            _cargar();
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.payments_rounded, color: Colors.green),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _cantidad == 1 ? "1 cliente reportó un pago: confirmalo" : "$_cantidad clientes reportaron pagos: confirmalos",
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.green),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bloque "Pago en línea" de la tarjeta Automático de una factura.
class PagoEnLineaFactura extends StatelessWidget {
  final int negocioId;
  final Map<String, dynamic> datos; // "pago_en_linea" de /facturas/<id>/automatizaciones/
  final VoidCallback onCambio;
  const PagoEnLineaFactura({super.key, required this.negocioId, required this.datos, required this.onCambio});

  @override
  Widget build(BuildContext context) {
    final configurado = datos['configurado'] == true;
    final enlace = '${datos['enlace']}';
    final pagos = ((datos['pagos_reportados'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
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
              Icon(Icons.qr_code_2_rounded, size: 19, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(child: Text("Pago en línea", style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textStrong))),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            configurado
                ? "Tu cliente paga por SINPE o transferencia desde este enlace y sube el comprobante; te avisamos para confirmarlo."
                : "Cargá tu SINPE o cuenta IBAN para que tus clientes paguen desde un enlace y te manden el comprobante.",
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.35),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (configurado) ...[
                FilledButton.tonalIcon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: enlace));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enlace de pago copiado.")));
                  },
                  icon: const Icon(Icons.link_rounded, size: 18),
                  label: const Text("Copiar enlace"),
                ),
                OutlinedButton.icon(
                  onPressed: () => Share.share("Podés pagar la factura aquí: $enlace"),
                  icon: const Icon(Icons.share_rounded, size: 17),
                  label: const Text("Compartir"),
                ),
                TextButton(
                  onPressed: () => launchUrl(Uri.parse(enlace), mode: LaunchMode.externalApplication),
                  child: const Text("Ver página"),
                ),
              ],
              TextButton.icon(
                onPressed: () async {
                  if (await configurarDatosPago(context, negocioId: negocioId) != null) onCambio();
                },
                icon: const Icon(Icons.settings_outlined, size: 17),
                label: Text(configurado ? "Datos de pago" : "Configurar datos de pago"),
              ),
            ],
          ),
          if (pagos.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final p in pagos) PagoReportadoTile(pago: p, onCambio: onCambio, mostrarFactura: false),
          ],
        ],
      ),
    );
  }
}
