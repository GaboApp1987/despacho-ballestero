import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'theme/app_theme.dart';
import 'api_service.dart';
import 'negocio.dart';
import 'factura.dart';
import 'export_service.dart'; // 👈 Importamos el servicio de exportación
import 'formato.dart';

/// Abre WhatsApp (wa.me) con el mensaje ya escrito para ese número --
/// compartido entre el recordatorio individual (por cliente) y el masivo
/// (lista de vencidos/próximos a vencer). Nunca envía nada solo: el negocio
/// tiene que tocar "Enviar" dentro de WhatsApp.
Future<void> abrirWhatsApp(BuildContext context, String telefono, String mensaje) async {
  // wa.me necesita el numero completo con codigo de pais y sin espacios ni
  // guiones -- en Costa Rica los numeros locales tienen 8 digitos, así que
  // si viene así se le antepone 506 (si ya trae código de país se respeta).
  final soloDigitos = telefono.replaceAll(RegExp(r'[^0-9]'), '');
  final numero = soloDigitos.length == 8 ? '506$soloDigitos' : soloDigitos;
  final uri = Uri.parse('https://wa.me/$numero?text=${Uri.encodeComponent(mensaje)}');
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No se pudo abrir WhatsApp.")),
      );
    }
  }
}

class CuentasPorCobrarScreen extends StatefulWidget {
  final Negocio negocio;
  const CuentasPorCobrarScreen({super.key, required this.negocio});

  @override
  State<CuentasPorCobrarScreen> createState() => _CuentasPorCobrarScreenState();
}

class _CuentasPorCobrarScreenState extends State<CuentasPorCobrarScreen> {
  bool _isLoading = true;
  bool _generandoRecordatorios = false;
  List<Map<String, dynamic>> _saldosClientes = [];

  double get _totalGeneral => _saldosClientes.fold(
        0.0,
        (sum, item) => sum + (double.tryParse(item['saldo'].toString()) ?? 0.0),
      );

  @override
  void initState() {
    super.initState();
    _cargarSaldos();
  }

  Future<void> _cargarSaldos() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.get('/clientes/saldos/?negocio=${widget.negocio.id}');
      if (response.statusCode == 200) {
        final List data = json.decode(utf8.decode(response.bodyBytes));
        if (mounted) {
          setState(() {
            _saldosClientes = data.cast<Map<String, dynamic>>();
            _isLoading = false;
          });
        }
      } else {
        throw Exception("Error del servidor: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al cargar saldos: $e")),
        );
      }
    }
  }

  /// Le pide a Claude un mensaje de cobro para cada cliente cuya factura a
  /// crédito más antigua sin pagar ya venció o está por vencer (backend:
  /// ClienteViewSet.mensajes_cobro_pendientes), y abre una pantalla donde el
  /// negocio revisa/edita cada mensaje y lo manda por WhatsApp uno por uno
  /// -- WhatsApp no permite mandar varios de una sola vez sin su API de
  /// negocios, así que esto arma la fila lista para ir enviando.
  Future<void> _enviarRecordatorios() async {
    setState(() => _generandoRecordatorios = true);
    try {
      final response = await ApiService.get('/clientes/mensajes-cobro-pendientes/?negocio=${widget.negocio.id}');
      final data = json.decode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200) {
        throw Exception(data['error'] ?? data['detail'] ?? 'Error desconocido');
      }
      final lista = (data as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      if (lista.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No hay cuentas vencidas ni próximas a vencer.")),
        );
        return;
      }
      await Navigator.push(context, MaterialPageRoute(builder: (_) => _RecordatoriosCobroScreen(mensajes: lista)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("No se pudieron generar los recordatorios: $e"), backgroundColor: Colors.red, duration: const Duration(seconds: 5)),
        );
      }
    } finally {
      if (mounted) setState(() => _generandoRecordatorios = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.monetization_on_outlined, color: AppColors.primary),
                    SizedBox(width: 10),
                    Text(
                      "Cuentas por Cobrar",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Row(
                  children: [
                    _generandoRecordatorios
                        ? const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : TextButton.icon(
                            onPressed: _saldosClientes.isEmpty ? null : _enviarRecordatorios,
                            icon: const Icon(Icons.campaign_outlined, color: Colors.green),
                            label: const Text("Enviar Recordatorios", style: TextStyle(color: Colors.green)),
                          ),
                    IconButton(
                      icon: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
                      tooltip: "Exportar PDF",
                      onPressed: _saldosClientes.isEmpty ? null : () => ExportService.exportSaldosToPdf(_saldosClientes, widget.negocio.nombreComercial),
                    ),
                    IconButton(
                      icon: const Icon(Icons.table_chart, color: Colors.green),
                      tooltip: "Exportar Excel",
                      onPressed: _saldosClientes.isEmpty ? null : () => ExportService.exportSaldosToExcel(_saldosClientes),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _cargarSaldos,
                    ),
                  ],
                )
              ],
            ),
          ),

          if (!_isLoading && _saldosClientes.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              color: AppColors.surfaceSubtle,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Total General por Cobrar",
                    style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary),
                  ),
                  Text(
                    formatearColones(_totalGeneral),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primary),
                  ),
                ],
              ),
            ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _saldosClientes.isEmpty
                    ? const Center(child: Text("No hay cuentas pendientes por cobrar."))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _saldosClientes.length,
                        itemBuilder: (context, index) {
                          final item = _saldosClientes[index];
                          final double saldo = double.tryParse(item['saldo'].toString()) ?? 0.0;
                          
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primary.withOpacity(0.1),
                                child: Text(item['nombre'][0].toUpperCase(), style: TextStyle(color: AppColors.primary)),
                              ),
                              title: Text(item['nombre'], style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text("Cédula: ${item['cedula']}"),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text("Saldo Pendiente", style: TextStyle(fontSize: 10, color: Colors.grey)),
                                  Text(
                                    formatearColones(saldo),
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 16),
                                  ),
                                ],
                              ),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => DetalleCuentaClienteScreen(
                                      clienteId: item['id'],
                                      clienteNombre: item['nombre'],
                                      negocioId: widget.negocio.id,
                                      negocioNombre: widget.negocio.nombreComercial,
                                    ),
                                  ),
                                );
                                _cargarSaldos(); 
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class DetalleCuentaClienteScreen extends StatefulWidget {
  final int clienteId;
  final String clienteNombre;
  final int negocioId;
  final String negocioNombre; // 👈 Agregamos el nombre del negocio para el reporte

  const DetalleCuentaClienteScreen({
    super.key,
    required this.clienteId,
    required this.clienteNombre,
    required this.negocioId,
    required this.negocioNombre,
  });

  @override
  State<DetalleCuentaClienteScreen> createState() => _DetalleCuentaClienteScreenState();
}

class _DetalleCuentaClienteScreenState extends State<DetalleCuentaClienteScreen> {
  bool _isLoading = true;
  bool _generandoMensaje = false;
  List<dynamic> _historial = [];

  double get _totalPendiente {
    double total = 0.0;
    for (final entry in _historial) {
      final double monto = double.tryParse(entry['monto'].toString()) ?? 0.0;
      total += entry['tipo'] == 'FACTURA' ? monto : -monto;
    }
    return total;
  }

  String _formatFecha(String raw) {
    final DateTime? fecha = DateTime.tryParse(raw);
    if (fecha == null) return raw;
    final local = fecha.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return "$dd/$mm/${local.year} $hh:$min";
  }

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
  }

  Future<void> _cargarHistorial() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.get('/clientes/${widget.clienteId}/historial-credito/?negocio=${widget.negocioId}');
      if (response.statusCode == 200) {
        if (mounted) {
          final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
          data.sort((a, b) {
            final DateTime? fechaA = DateTime.tryParse(a['fecha'].toString());
            final DateTime? fechaB = DateTime.tryParse(b['fecha'].toString());
            if (fechaA == null || fechaB == null) return 0;
            return fechaA.compareTo(fechaB);
          });
          setState(() {
            _historial = data;
            _isLoading = false;
          });
        }
      } else {
        throw Exception("Error al cargar historial: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<Factura>> _cargarFacturasPendientes() async {
    final response = await ApiService.get(
      '/facturas/?negocio=${widget.negocioId}&cliente=${widget.clienteId}&condicion_venta=02&pagada=false',
    );
    if (response.statusCode == 200) {
      final List data = json.decode(utf8.decode(response.bodyBytes));
      return data.map((j) => Factura.fromJson(j)).toList();
    }
    return [];
  }

  void _mostrarDialogoAbono() async {
    final montoController = TextEditingController();
    final facturasPendientes = await _cargarFacturasPendientes();
    Factura? facturaSeleccionada;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text("Registrar Abono"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: montoController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: "Monto del Abono",
                  prefixText: "₡ ",
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              if (facturasPendientes.isNotEmpty) ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<Factura?>(
                  value: facturaSeleccionada,
                  decoration: const InputDecoration(
                    labelText: "¿Paga una factura de crédito específica?",
                    border: OutlineInputBorder(),
                    helperText: "Genera el Recibo Electrónico de Pago (REP), obligatorio por ley.",
                    helperMaxLines: 2,
                  ),
                  items: [
                    const DropdownMenuItem<Factura?>(value: null, child: Text("Abono general (sin REP)")),
                    ...facturasPendientes.map((f) => DropdownMenuItem<Factura?>(
                          value: f,
                          child: Text("F-${f.consecutivo} · ${formatearColones(f.totalFactura)}", overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: (v) => setStateDialog(() => facturaSeleccionada = v),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
            ElevatedButton(
              onPressed: () {
                final String montoStr = montoController.text;
                final facturaId = facturaSeleccionada?.id;
                Navigator.pop(ctx);
                _registrarAbono(montoStr, facturaId);
              },
              child: const Text("Guardar"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _registrarAbono(String montoStr, [int? facturaId]) async {
    final double? monto = double.tryParse(montoStr.replaceAll(',', '.'));
    if (monto == null || monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ingrese un monto válido")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await ApiService.post(
        '/clientes/${widget.clienteId}/registrar-abono/?negocio=${widget.negocioId}',
        {
          'negocio': widget.negocioId,
          'monto': monto,
          if (facturaId != null) 'factura': facturaId,
        },
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Abono registrado con éxito"), backgroundColor: Colors.green),
          );
          _cargarHistorial();
        }
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: $e"), 
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// Le pide a Claude (backend: ClienteViewSet.mensaje_cobro) que redacte un
  /// mensaje de cobro para este cliente y abre un diálogo para revisarlo,
  /// editarlo y mandarlo por WhatsApp -- nunca se envía nada automático.
  Future<void> _cobrarPorWhatsApp() async {
    setState(() => _generandoMensaje = true);
    try {
      final response = await ApiService.get('/clientes/${widget.clienteId}/mensaje-cobro/?negocio=${widget.negocioId}');
      final data = json.decode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200) {
        throw Exception(data['error'] ?? data['detail'] ?? 'Error desconocido');
      }
      if (mounted) {
        await _mostrarDialogoCobro(data['mensaje'] as String, data['telefono'] as String?);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("No se pudo generar el mensaje: $e"), backgroundColor: Colors.red, duration: const Duration(seconds: 5)),
        );
      }
    } finally {
      if (mounted) setState(() => _generandoMensaje = false);
    }
  }

  Future<void> _mostrarDialogoCobro(String mensajeInicial, String? telefono) async {
    final ctrl = TextEditingController(text: mensajeInicial);
    final sinTelefono = telefono == null || telefono.trim().isEmpty;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Mensaje de cobro"),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (sinTelefono)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    "Este cliente no tiene teléfono registrado: agregalo en su ficha para poder enviarlo por WhatsApp, o copiá el mensaje manualmente.",
                    style: TextStyle(color: Colors.orange[800], fontSize: 13),
                  ),
                ),
              TextField(
                controller: ctrl,
                maxLines: 6,
                autofocus: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: "Mensaje (podés editarlo antes de enviar)",
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton.icon(
            onPressed: sinTelefono
                ? null
                : () {
                    Navigator.pop(ctx);
                    abrirWhatsApp(context, telefono, ctrl.text);
                  },
            icon: const Icon(Icons.send, size: 18),
            label: const Text("Enviar por WhatsApp"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Historial: ${widget.clienteNombre}"),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
        actions: [
          IconButton(
            icon: _generandoMensaje
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chat_outlined, color: Colors.green),
            tooltip: "Cobrar por WhatsApp",
            onPressed: (_isLoading || _generandoMensaje || _totalPendiente <= 0) ? null : _cobrarPorWhatsApp,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: "Exportar Historial PDF",
            onPressed: _historial.isEmpty ? null : () => ExportService.exportHistorialToPdf(widget.clienteNombre, _historial, widget.negocioNombre),
          ),
          IconButton(
            icon: const Icon(Icons.table_chart),
            tooltip: "Exportar Historial Excel",
            onPressed: _historial.isEmpty ? null : () => ExportService.exportHistorialToExcel(widget.clienteNombre, _historial),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_isLoading && _historial.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: AppColors.surfaceSubtle,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Saldo Pendiente",
                    style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary),
                  ),
                  Text(
                    formatearColones(_totalPendiente),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.primary),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _historial.isEmpty
                  ? const Center(child: Text("Sin movimientos registrados."))
                  : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _historial.length,
                    itemBuilder: (context, index) {
                      final entry = _historial[index];
                      final String tipo = entry['tipo'];
                      final bool esFactura = tipo == 'FACTURA';
                      final bool esNotaCredito = tipo == 'NOTA_CREDITO';

                      final IconData icono = esFactura
                          ? Icons.description_outlined
                          : esNotaCredito
                              ? Icons.assignment_return_outlined
                              : Icons.payments_outlined;
                      final Color color = esFactura ? Colors.orange : (esNotaCredito ? Colors.blue : Colors.green);
                      final String titulo = esFactura
                          ? "Factura #${entry['numero']}"
                          : esNotaCredito
                              ? "Nota de Crédito NC-${entry['numero']}"
                              : "Abono / Pago";

                      return Card(
                        child: ListTile(
                          leading: Icon(icono, color: color),
                          title: Text(titulo),
                          subtitle: Text(_formatFecha(entry['fecha'].toString())),
                          trailing: Text(
                            "${esFactura ? '+' : '-'} ${formatearColones(double.parse(entry['monto'].toString()))}",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: esFactura ? Colors.red : color,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _mostrarDialogoAbono,
        label: const Text("REGISTRAR ABONO", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        icon: const Icon(Icons.add, color: Colors.white),
        backgroundColor: Colors.green,
      ),
    );
  }
}

class _RecordatorioCobro {
  final int clienteId;
  final String nombre;
  final String? telefono;
  final double saldo;
  final int diasAtraso;
  final TextEditingController controller;
  bool enviado = false;

  _RecordatorioCobro({
    required this.clienteId,
    required this.nombre,
    required this.telefono,
    required this.saldo,
    required this.diasAtraso,
    required String mensaje,
  }) : controller = TextEditingController(text: mensaje);
}

/// Fila de recordatorios de cobro (vencidos y próximos a vencer) que el
/// negocio revisa/edita y manda uno por uno por WhatsApp -- ver
/// _CuentasPorCobrarScreenState._enviarRecordatorios.
class _RecordatoriosCobroScreen extends StatefulWidget {
  final List<Map<String, dynamic>> mensajes;
  const _RecordatoriosCobroScreen({required this.mensajes});

  @override
  State<_RecordatoriosCobroScreen> createState() => _RecordatoriosCobroScreenState();
}

class _RecordatoriosCobroScreenState extends State<_RecordatoriosCobroScreen> {
  late final List<_RecordatorioCobro> _items;

  @override
  void initState() {
    super.initState();
    _items = widget.mensajes.map((m) {
      return _RecordatorioCobro(
        clienteId: m['cliente_id'],
        nombre: m['nombre'] ?? '',
        telefono: m['telefono'] as String?,
        saldo: double.tryParse(m['saldo'].toString()) ?? 0.0,
        diasAtraso: (m['dias_atraso'] as num?)?.toInt() ?? 0,
        mensaje: m['mensaje'] ?? '',
      );
    }).toList();
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Recordatorios de Cobro (${_items.length})")),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          final sinTelefono = item.telefono == null || item.telefono!.trim().isEmpty;
          final String estadoTexto = item.diasAtraso > 0
              ? "Vencido hace ${item.diasAtraso} día(s)"
              : item.diasAtraso == 0
                  ? "Vence hoy"
                  : "Vence en ${-item.diasAtraso} día(s)";
          final Color estadoColor = item.diasAtraso >= 0 ? Colors.red : Colors.orange;

          return Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(item.nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis),
                      ),
                      if (item.enviado)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.check_circle, color: Colors.green, size: 18),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: estadoColor.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                        child: Text(estadoTexto, style: TextStyle(color: estadoColor, fontWeight: FontWeight.w600, fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text("Saldo pendiente: ${formatearColones(item.saldo)}", style: TextStyle(color: Colors.grey[700])),
                  const SizedBox(height: 10),
                  TextField(
                    controller: item.controller,
                    maxLines: 4,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  ),
                  if (sinTelefono)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        "Sin teléfono registrado: agregalo en la ficha del cliente para poder enviarlo.",
                        style: TextStyle(color: Colors.orange[800], fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: sinTelefono
                          ? null
                          : () async {
                              await abrirWhatsApp(context, item.telefono!, item.controller.text);
                              if (mounted) setState(() => item.enviado = true);
                            },
                      icon: const Icon(Icons.send, size: 16),
                      label: Text(item.enviado ? "Reenviar" : "Enviar por WhatsApp"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
