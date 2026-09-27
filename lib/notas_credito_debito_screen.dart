import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'theme/app_theme.dart';
import 'api_service.dart';
import 'negocio.dart';
import 'cliente.dart';
import 'compra_model.dart';
import 'factura.dart';
import 'nota_credito.dart';
import 'formato.dart';
import 'export_service.dart';
import 'detalle_factura_screen.dart';
import 'compras_screen.dart';

/// Punto de entrada dedicado para notas de crédito (a clientes, sobre una
/// factura) y notas de débito (de proveedores, sobre una compra) -- antes
/// solo se podían crear entrando primero a la factura/compra puntual; acá
/// se ven todas juntas y se elige cliente/proveedor y luego el documento a
/// acreditar/debitar, sin duplicar la lógica de creación que ya funciona
/// bien en DetalleFacturaScreen y compras_screen.dart.
class NotasCreditoDebitoScreen extends StatefulWidget {
  final Negocio negocio;
  const NotasCreditoDebitoScreen({super.key, required this.negocio});

  @override
  State<NotasCreditoDebitoScreen> createState() => _NotasCreditoDebitoScreenState();
}

class _NotasCreditoDebitoScreenState extends State<NotasCreditoDebitoScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _cargandoCredito = true;
  bool _cargandoDebito = true;
  bool _actualizandoEstados = false;
  final Set<int> _consultandoIndividual = {};
  List<NotaCredito> _notasCredito = [];
  List<Map<String, dynamic>> _notasDebito = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _cargarNotasCredito();
    _cargarNotasDebito();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _cargarNotasCredito() async {
    if (mounted) setState(() => _cargandoCredito = true);
    try {
      final r = await ApiService.get('/notas-credito/?negocio=${widget.negocio.id}');
      if (r.statusCode == 200) {
        final data = json.decode(utf8.decode(r.bodyBytes)) as List;
        _notasCredito = data.map((j) => NotaCredito.fromJson(j)).toList();
      }
    } catch (_) {
      // Si falla, se queda con lo que ya tenía cargado.
    }
    if (mounted) setState(() => _cargandoCredito = false);
  }

  /// Consulta a Hacienda el estado real de UNA nota de crédito puntual
  /// (botón "Consultar estado" de cada tarjeta) y la actualiza en la
  /// lista sin recargar todo.
  Future<void> _consultarEstadoNota(NotaCredito n) async {
    setState(() => _consultandoIndividual.add(n.id));
    try {
      final r = await ApiService.post('/notas-credito/${n.id}/consultar-hacienda/', {});
      if (r.statusCode == 200) {
        final data = json.decode(utf8.decode(r.bodyBytes));
        final actualizada = NotaCredito.fromJson(data);
        if (mounted) {
          setState(() {
            final idx = _notasCredito.indexWhere((x) => x.id == n.id);
            if (idx != -1) _notasCredito[idx] = actualizada;
          });
          // Si ya estaba Aceptada, consultar-hacienda no cambia el estado --
          // el único efecto visible en ese caso es el reenvío del correo
          // (ver correo_info en ConsultarHaciendaView, backend), así que hay
          // que avisarle al usuario con un SnackBar o va a parecer que el
          // botón no hizo nada.
          final correoInfo = data['correo_info'];
          if (correoInfo != null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(correoInfo)));
          }
        }
      } else {
        final data = json.decode(utf8.decode(r.bodyBytes));
        throw Exception(data['detail'] ?? 'Error desconocido');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("No se pudo consultar: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _consultandoIndividual.remove(n.id));
    }
  }

  /// Botón "Actualizar" de arriba: consulta a Hacienda TODAS las notas que
  /// sigan Sin Enviar/Procesando de una sola vez.
  Future<void> _actualizarEstadosNotasCredito() async {
    final pendientes = _notasCredito.where((n) => n.estadoHacienda == '1' || n.estadoHacienda == '2').toList();
    if (pendientes.isEmpty) {
      await _cargarNotasCredito();
      return;
    }
    setState(() => _actualizandoEstados = true);
    for (final n in pendientes) {
      try {
        await ApiService.post('/notas-credito/${n.id}/consultar-hacienda/', {});
      } catch (_) {
        // seguimos con las demás aunque una falle
      }
    }
    await _cargarNotasCredito();
    if (mounted) setState(() => _actualizandoEstados = false);
  }

  Future<void> _cargarNotasDebito() async {
    if (mounted) setState(() => _cargandoDebito = true);
    try {
      final r = await ApiService.get('/compras/notas-debito/?negocio=${widget.negocio.id}');
      if (r.statusCode == 200) {
        final data = json.decode(utf8.decode(r.bodyBytes)) as List;
        _notasDebito = data.cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    if (mounted) setState(() => _cargandoDebito = false);
  }

  /// Nueva Nota de Crédito: primero a qué cliente, luego cuál de sus
  /// facturas -- y de ahí se pasa al detalle de esa factura, donde ya
  /// existe (y funciona bien) el botón "Anular con Nota de Crédito" con
  /// selección de líneas para notas parciales.
  Future<void> _iniciarNuevaNotaCredito() async {
    final clientesResp = await ApiService.get('/clientes/?negocio=${widget.negocio.id}');
    if (!mounted || clientesResp.statusCode != 200) return;
    final clientes = (json.decode(utf8.decode(clientesResp.bodyBytes)) as List).map((j) => Cliente.fromJson(j)).toList();
    if (clientes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Todavía no hay clientes registrados.")));
      return;
    }

    final cliente = await showDialog<Cliente>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text("¿A qué cliente le vas a acreditar?"),
        children: clientes
            .map((c) => SimpleDialogOption(onPressed: () => Navigator.pop(ctx, c), child: Text(c.nombre)))
            .toList(),
      ),
    );
    if (cliente == null || !mounted) return;

    final facturasResp = await ApiService.get('/facturas/?negocio=${widget.negocio.id}&cliente=${cliente.id}');
    if (!mounted || facturasResp.statusCode != 200) return;
    final facturas = (json.decode(utf8.decode(facturasResp.bodyBytes)) as List)
        .map((j) => Factura.fromJson(j))
        .where((f) => !f.anulada && f.estadoHacienda == '3')
        .toList();
    if (facturas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${cliente.nombre} no tiene facturas aceptadas por Hacienda para acreditar.")),
      );
      return;
    }

    final factura = await showDialog<Factura>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text("Facturas de ${cliente.nombre}"),
        children: facturas
            .map((f) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, f),
                  child: Text("F-${f.consecutivo} · ${formatearColones(f.totalFactura)}"),
                ))
            .toList(),
      ),
    );
    if (factura == null || !mounted) return;

    await Navigator.push(context, MaterialPageRoute(builder: (_) => DetalleFacturaScreen(factura: factura)));
    _cargarNotasCredito();
  }

  /// Nueva Nota de Débito: primero qué proveedor, luego cuál compra -- y
  /// ahí se reusa exactamente el mismo diálogo que ya existe en la lista de
  /// Compras (mostrarDialogoNotaDebito).
  Future<void> _iniciarNuevaNotaDebito() async {
    final provResp = await ApiService.get('/proveedores/?negocio=${widget.negocio.id}');
    if (!mounted || provResp.statusCode != 200) return;
    final proveedores = (json.decode(utf8.decode(provResp.bodyBytes)) as List).map((j) => Proveedor.fromJson(j)).toList();
    if (proveedores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Todavía no hay proveedores registrados.")));
      return;
    }

    final proveedor = await showDialog<Proveedor>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text("¿De qué proveedor es la nota de débito?"),
        children: proveedores
            .map((p) => SimpleDialogOption(onPressed: () => Navigator.pop(ctx, p), child: Text(p.nombre)))
            .toList(),
      ),
    );
    if (proveedor == null || !mounted) return;

    final comprasResp = await ApiService.get('/compras/?negocio=${widget.negocio.id}&proveedor=${proveedor.id}');
    if (!mounted || comprasResp.statusCode != 200) return;
    final compras = (json.decode(utf8.decode(comprasResp.bodyBytes)) as List).map((j) => Compra.fromJson(j)).toList();
    if (compras.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${proveedor.nombre} no tiene compras registradas.")));
      return;
    }

    final compra = await showDialog<Compra>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text("Compras a ${proveedor.nombre}"),
        children: compras
            .map((c) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, c),
                  child: Text(
                    "${c.numeroFacturaProveedor.isNotEmpty ? c.numeroFacturaProveedor : 'Sin número'} · ${formatearColones(c.totalCompra)}",
                  ),
                ))
            .toList(),
      ),
    );
    if (compra == null || !mounted) return;

    await mostrarDialogoNotaDebito(context, compra, onCreada: _cargarNotasDebito);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            decoration: BoxDecoration(color: AppColors.surface, border: Border(bottom: BorderSide(color: AppColors.border))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.assignment_return_outlined, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Notas de Crédito y Débito",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                      ),
                    ),
                    if (_tabController.index == 0)
                      _actualizandoEstados
                          ? const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : IconButton(
                              icon: const Icon(Icons.refresh),
                              tooltip: 'Actualizar estados con Hacienda',
                              onPressed: _actualizarEstadosNotasCredito,
                            ),
                  ],
                ),
                const SizedBox(height: 12),
                TabBar(
                  controller: _tabController,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textMuted,
                  indicatorColor: AppColors.primary,
                  tabs: const [
                    Tab(text: "Notas de Crédito"),
                    Tab(text: "Notas de Débito"),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildListaCredito(), _buildListaDebito()],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _tabController.index == 0 ? _iniciarNuevaNotaCredito : _iniciarNuevaNotaDebito,
        icon: const Icon(Icons.add),
        label: Text(_tabController.index == 0 ? "Nueva Nota de Crédito" : "Nueva Nota de Débito"),
        backgroundColor: _tabController.index == 0 ? Colors.blue : Colors.deepOrange,
      ),
    );
  }

  // Mismo mapeo de estado_hacienda que DetalleFacturaScreen (comparten
  // Factura.ESTADOS_HACIENDA) -- acá faltaba mostrarlo del todo, la nota
  // quedaba sin ninguna pista visual de si Hacienda la aceptó o no.
  (Color, String) _estadoNotaCredito(String estadoHacienda) {
    switch (estadoHacienda) {
      case '3':
        return (Colors.green, 'Aceptada');
      case '4':
        return (Colors.red, 'Rechazada');
      case '5':
        return (Colors.red, 'Error técnico');
      case '1':
      case '2':
        return (Colors.orange, 'Procesando');
      default:
        return (Colors.grey, 'Desconocido');
    }
  }

  Widget _buildListaCredito() {
    if (_cargandoCredito) return const Center(child: CircularProgressIndicator());
    if (_notasCredito.isEmpty) {
      return const Center(child: Text("Todavía no hay notas de crédito.", style: TextStyle(color: Colors.grey)));
    }
    return RefreshIndicator(
      onRefresh: _cargarNotasCredito,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _notasCredito.length,
        itemBuilder: (context, i) {
          final n = _notasCredito[i];
          final (colorEstado, textoEstado) = _estadoNotaCredito(n.estadoHacienda);
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: const Icon(Icons.assignment_return_outlined, color: Colors.blue),
              title: Text("NC-${n.consecutivo} · ${n.receptorNombre}", style: TextStyle(color: AppColors.textStrong, fontWeight: FontWeight.bold)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Factura F-${n.facturaConsecutivo ?? '?'} · ${n.motivo}", style: TextStyle(color: AppColors.textMuted)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: colorEstado.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                    child: Text(textoEstado, style: TextStyle(color: colorEstado, fontWeight: FontWeight.w600, fontSize: 11.5)),
                  ),
                  if (n.motivoRechazo != null && n.motivoRechazo!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red, size: 16),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  n.estadoHacienda == '5' ? "Motivo del error" : "Motivo del rechazo",
                                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: n.motivoRechazo!));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text("Motivo copiado al portapapeles")),
                                  );
                                },
                                child: const Icon(Icons.copy, size: 16, color: Colors.red),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          SelectableText(n.motivoRechazo!, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              isThreeLine: true,
              trailing: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatearColones(n.total), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  // El monto de arriba siempre está en colones (mismo
                  // criterio que el listado de facturas), pero si la
                  // factura que esta nota anula fue en dólares, se agrega
                  // esta segunda línea con el monto real en USD para poder
                  // diferenciarlas a simple vista sin tener que abrir el PDF.
                  if (n.facturaMoneda == 'USD' && n.facturaTipoCambio > 0)
                    Text(
                      formatearDolares(n.total / n.facturaTipoCambio),
                      style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600),
                    ),
                  // Mientras sigue Procesando: "Consultar" para forzar el
                  // chequeo de estado. Una vez Aceptada, si por lo que sea el
                  // correo al cliente no salió (correo_enviado en False --
                  // ej. fallo puntual de Brevo, o se reseteó a mano en el
                  // admin para reenviar con datos corregidos), se ofrece
                  // "Reenviar correo" en su lugar -- antes esta fila
                  // desaparecía apenas quedaba Aceptada y no había forma de
                  // reenviar el correo desde la app.
                  if (n.estadoHacienda == '1' || n.estadoHacienda == '2' || (n.estadoHacienda == '3' && !n.correoEnviado)) ...[
                    const SizedBox(height: 4),
                    _consultandoIndividual.contains(n.id)
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : InkWell(
                            onTap: () => _consultarEstadoNota(n),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(n.estadoHacienda == '3' ? Icons.mail_outline : Icons.refresh, size: 13, color: AppColors.primary),
                                const SizedBox(width: 3),
                                Text(
                                  n.estadoHacienda == '3' ? 'Reenviar correo' : 'Consultar',
                                  style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                  ],
                ],
              ),
              onTap: () => ExportService.exportNotaCreditoToPdf(n),
            ),
          );
        },
      ),
    );
  }

  Widget _buildListaDebito() {
    if (_cargandoDebito) return const Center(child: CircularProgressIndicator());
    if (_notasDebito.isEmpty) {
      return const Center(child: Text("Todavía no hay notas de débito.", style: TextStyle(color: Colors.grey)));
    }
    return RefreshIndicator(
      onRefresh: _cargarNotasDebito,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _notasDebito.length,
        itemBuilder: (context, i) {
          final n = _notasDebito[i];
          final monto = double.tryParse(n['monto'].toString()) ?? 0.0;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: const Icon(Icons.assignment_late_outlined, color: Colors.deepOrange),
              title: Text(
                "${n['nombre_proveedor'] ?? 'Proveedor'}${(n['numero_documento'] ?? '').toString().isNotEmpty ? ' · ${n['numero_documento']}' : ''}",
                style: TextStyle(color: AppColors.textStrong, fontWeight: FontWeight.bold),
              ),
              subtitle: Text((n['motivo'] ?? '').toString(), style: TextStyle(color: AppColors.textMuted)),
              trailing: Text(formatearColones(monto), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
            ),
          );
        },
      ),
    );
  }
}
