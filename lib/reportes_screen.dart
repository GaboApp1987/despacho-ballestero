import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

import 'api_service.dart';
import 'compra_model.dart';
import 'export_service.dart';
import 'factura.dart';
import 'formato.dart';
import 'gasto_operativo.dart';
import 'ingreso_operativo.dart';
import 'negocio.dart';
import 'nota_credito.dart';
import 'widgets/selector_periodo.dart';
import 'widgets/botones_exportar.dart';

enum _TipoReporte { ventas, ingresos, compras, gastos, notasCredito }

/// Pantalla de Reportes del negocio: permite filtrar por rango de fechas y
/// por tipo de documento (ventas, compras, gastos, notas de crédito) y
/// exportar el resultado a PDF o Excel.
class ReportesScreen extends StatefulWidget {
  final Negocio negocio;
  const ReportesScreen({super.key, required this.negocio});

  @override
  State<ReportesScreen> createState() => _ReportesScreenState();
}

class _ReportesScreenState extends State<ReportesScreen> {
  _TipoReporte _tipo = _TipoReporte.ventas;
  late DateTime _fechaInicio;
  late DateTime _fechaFin;
  bool _cargando = true;

  List<Factura> _facturas = [];
  List<IngresoOperativo> _ingresos = [];
  List<Compra> _compras = [];
  List<GastoOperativo> _gastos = [];
  List<NotaCredito> _notasCredito = [];

  @override
  void initState() {
    super.initState();
    final ahora = DateTime.now();
    _fechaInicio = DateTime(ahora.year, ahora.month, 1);
    _fechaFin = DateTime(ahora.year, ahora.month + 1, 0);
    _cargarDatos();
  }

  String get _periodoTexto =>
      "${_fechaInicio.day}/${_fechaInicio.month}/${_fechaInicio.year} - ${_fechaFin.day}/${_fechaFin.month}/${_fechaFin.year}";

  static const List<String> _nombresMes = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  /// True si el rango actual es exactamente un mes calendario completo (el
  /// caso normal: al abrir la pantalla, o tras navegar con las flechas o
  /// tocar el nombre del mes) -- si no, es un rango personalizado elegido
  /// con _elegirRangoFechas, y se muestra la fecha en vez del nombre del mes.
  bool get _esMesCompleto {
    final primerDia = DateTime(_fechaInicio.year, _fechaInicio.month, 1);
    final ultimoDia = DateTime(_fechaInicio.year, _fechaInicio.month + 1, 0);
    return _fechaInicio.isAtSameMomentAs(primerDia) && _fechaFin.isAtSameMomentAs(ultimoDia);
  }

  String get _mesAnioTexto => '${_nombresMes[_fechaInicio.month - 1]} ${_fechaInicio.year}';

  /// Mueve el rango a un mes completo, relativo al mes de _fechaInicio
  /// (deltaMeses=0 selecciona todos los días DE ESE MES -- lo mismo que
  /// tocar el nombre del mes cuando el rango ya venía de uno personalizado).
  void _irAMes(int deltaMeses) {
    final base = DateTime(_fechaInicio.year, _fechaInicio.month + deltaMeses, 1);
    setState(() {
      _fechaInicio = DateTime(base.year, base.month, 1);
      _fechaFin = DateTime(base.year, base.month + 1, 0);
    });
    _cargarDatos();
  }

  String _fmtFecha(DateTime d) => "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    final inicioStr = _fmtFecha(_fechaInicio);
    final finStr = _fmtFecha(_fechaFin);
    try {
      switch (_tipo) {
        case _TipoReporte.ventas:
          // Las notas de crédito del periodo se restan de las ventas.
          final rn = await ApiService.get('/notas-credito/?negocio=${widget.negocio.id}&fecha_inicio=$inicioStr&fecha_fin=$finStr');
          if (rn.statusCode == 200) {
            final data = json.decode(utf8.decode(rn.bodyBytes)) as List;
            _notasCredito = data
                .map((j) => NotaCredito.fromJson(j))
                .where((n) => n.estadoHacienda != '4' && n.estadoHacienda != '5')
                .toList();
          }
          final r = await ApiService.get('/facturas/?negocio=${widget.negocio.id}&fecha_inicio=$inicioStr&fecha_fin=$finStr');
          if (r.statusCode == 200) {
            final data = json.decode(utf8.decode(r.bodyBytes)) as List;
            // Una factura Rechazada (4) o con Error Técnico (5) nunca quedó
            // validada por Hacienda -- no es una venta real y no debe
            // sumarse ni aparecer en este reporte (mismo criterio que ya
            // usa el resto de la app: solo estado_hacienda '3' cuenta).
            _facturas = data
                .map((j) => Factura.fromJson(j))
                .where((f) => f.estadoHacienda != '4' && f.estadoHacienda != '5')
                .toList();
          }
          break;
        case _TipoReporte.ingresos:
          final r = await ApiService.get('/ingresos-operativos/?negocio=${widget.negocio.id}&fecha_inicio=$inicioStr&fecha_fin=$finStr');
          if (r.statusCode == 200) {
            final data = json.decode(utf8.decode(r.bodyBytes)) as List;
            _ingresos = data.map((j) => IngresoOperativo.fromJson(j)).toList();
          }
          break;
        case _TipoReporte.compras:
          final r = await ApiService.get('/compras/?negocio=${widget.negocio.id}&fecha_inicio=$inicioStr&fecha_fin=$finStr');
          if (r.statusCode == 200) {
            final data = json.decode(utf8.decode(r.bodyBytes)) as List;
            // Una compra que este negocio le Rechazó a Hacienda (Mensaje
            // Receptor tipo '3') no es una compra real, no debe sumarse.
            _compras = data
                .map((j) => Compra.fromJson(j))
                .where((c) => c.mensajeReceptorTipo != '3')
                .toList();
          }
          break;
        case _TipoReporte.gastos:
          final r = await ApiService.get('/gastos-operativos/?negocio=${widget.negocio.id}&fecha_inicio=$inicioStr&fecha_fin=$finStr');
          if (r.statusCode == 200) {
            final data = json.decode(utf8.decode(r.bodyBytes)) as List;
            _gastos = data.map((j) => GastoOperativo.fromJson(j)).toList();
          }
          break;
        case _TipoReporte.notasCredito:
          final r = await ApiService.get('/notas-credito/?negocio=${widget.negocio.id}&fecha_inicio=$inicioStr&fecha_fin=$finStr');
          if (r.statusCode == 200) {
            final data = json.decode(utf8.decode(r.bodyBytes)) as List;
            _notasCredito = data.map((j) => NotaCredito.fromJson(j)).toList();
          }
          break;
      }
    } catch (_) {
      // Si falla, simplemente se muestra la lista vacía con el estado actual.
    }
    if (mounted) setState(() => _cargando = false);
  }

  bool _consultandoNota = false;

  /// Reintenta a mano la confirmacion con Hacienda de una nota de credito
  /// que se quedo "Procesando" -- el reintento automatico en el backend se
  /// rinde tras ~2.5 minutos, y a diferencia de las facturas, las notas de
  /// credito no tenian ningun boton para reintentar despues de eso, asi que
  /// quedaban atascadas para siempre (y el correo al cliente nunca salia).
  Future<void> _consultarEstadoNotaCredito(NotaCredito nota) async {
    if (_consultandoNota) return;
    setState(() => _consultandoNota = true);
    try {
      final r = await ApiService.post('/notas-credito/${nota.id}/consultar-hacienda/', {});
      if (!mounted) return;
      final data = json.decode(utf8.decode(r.bodyBytes));
      if (r.statusCode != 200) {
        throw Exception(data['detail'] ?? 'Error al consultar el estado');
      }
      final estado = data['ind_estado_hacienda'] ?? '';
      final correoInfo = data['correo_info'];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(correoInfo != null ? "Estado: $estado. $correoInfo" : "Estado: $estado")),
      );
      _cargarDatos();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _consultandoNota = false);
    }
  }

  Future<void> _elegirRangoFechas() async {
    final rango = await elegirPeriodo(context, inicial: DateTimeRange(start: _fechaInicio, end: _fechaFin));
    if (rango != null) {
      setState(() {
        _fechaInicio = rango.start;
        _fechaFin = rango.end;
      });
      _cargarDatos();
    }
  }

  double get _totalActual {
    switch (_tipo) {
      case _TipoReporte.ventas:
        // Ventas netas: facturas válidas menos notas de crédito.
        return _facturas.fold(0.0, (s, f) => s + f.totalFactura) - _notasCredito.fold(0.0, (s, n) => s + n.total);
      case _TipoReporte.ingresos:
        return _ingresos.fold(0.0, (s, i) => s + i.total);
      case _TipoReporte.compras:
        return _compras.fold(0.0, (s, c) => s + c.totalCompra);
      case _TipoReporte.gastos:
        return _gastos.fold(0.0, (s, g) => s + g.monto);
      case _TipoReporte.notasCredito:
        return _notasCredito.fold(0.0, (s, n) => s + n.total);
    }
  }

  int get _cantidadActual {
    switch (_tipo) {
      case _TipoReporte.ventas:
        return _facturas.length;
      case _TipoReporte.ingresos:
        return _ingresos.length;
      case _TipoReporte.compras:
        return _compras.length;
      case _TipoReporte.gastos:
        return _gastos.length;
      case _TipoReporte.notasCredito:
        return _notasCredito.length;
    }
  }

  void _exportarPdf() {
    switch (_tipo) {
      case _TipoReporte.ventas:
        ExportService.exportFacturasToPdf(_facturas, widget.negocio.nombreComercial, _periodoTexto, notasCredito: _notasCredito);
        break;
      case _TipoReporte.ingresos:
        ExportService.exportIngresosToPdf(_ingresos, widget.negocio.nombreComercial, _periodoTexto);
        break;
      case _TipoReporte.compras:
        ExportService.exportComprasToPdf(_compras, widget.negocio.nombreComercial, _periodoTexto);
        break;
      case _TipoReporte.gastos:
        ExportService.exportGastosToPdf(_gastos, widget.negocio.nombreComercial, _periodoTexto);
        break;
      case _TipoReporte.notasCredito:
        ExportService.exportNotasCreditoToPdf(_notasCredito, widget.negocio.nombreComercial, _periodoTexto);
        break;
    }
  }

  void _exportarExcel() {
    switch (_tipo) {
      case _TipoReporte.ventas:
        ExportService.exportFacturasToExcel(_facturas, notasCredito: _notasCredito);
        break;
      case _TipoReporte.ingresos:
        ExportService.exportIngresosToExcel(_ingresos);
        break;
      case _TipoReporte.compras:
        ExportService.exportComprasToExcel(_compras);
        break;
      case _TipoReporte.gastos:
        ExportService.exportGastosToExcel(_gastos);
        break;
      case _TipoReporte.notasCredito:
        ExportService.exportNotasCreditoToExcel(_notasCredito);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    "Reportes",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textStrong),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      tooltip: "Mes anterior",
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _irAMes(-1),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _irAMes(0),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: Text(
                          _esMesCompleto ? _mesAnioTexto : _periodoTexto,
                          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      tooltip: "Mes siguiente",
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _irAMes(1),
                    ),
                    IconButton(
                      icon: const Icon(Icons.date_range, size: 18),
                      tooltip: "Elegir un rango de fechas personalizado",
                      visualDensity: VisualDensity.compact,
                      onPressed: _elegirRangoFechas,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 10,
              children: [
                _chipTipo(_TipoReporte.ventas, "Ventas", Icons.receipt_long_outlined),
                _chipTipo(_TipoReporte.ingresos, "Ingresos", Icons.trending_up),
                _chipTipo(_TipoReporte.compras, "Compras", Icons.shopping_cart_outlined),
                _chipTipo(_TipoReporte.gastos, "Gastos", Icons.payments_outlined),
                _chipTipo(_TipoReporte.notasCredito, "Notas de Crédito", Icons.assignment_return_outlined),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      _buildResumenYExportar(),
                      Expanded(child: _buildLista()),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chipTipo(_TipoReporte tipo, String label, IconData icono) {
    final seleccionado = _tipo == tipo;
    return ChoiceChip(
      label: Text(label),
      avatar: Icon(icono, size: 16, color: seleccionado ? Colors.black : AppColors.primary),
      selected: seleccionado,
      onSelected: (_) {
        setState(() => _tipo = tipo);
        _cargarDatos();
      },
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(color: seleccionado ? Colors.black : AppColors.textMuted, fontWeight: FontWeight.w600, fontSize: 13),
      backgroundColor: AppColors.surfaceSubtle,
      shape: StadiumBorder(side: BorderSide(color: seleccionado ? AppColors.primary : AppColors.border)),
    );
  }

  Widget _buildResumenYExportar() {
    final vacio = _cantidadActual == 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tipo == _TipoReporte.ventas
                ? "Ventas netas · ${_facturas.length} venta(s)${_notasCredito.isEmpty ? '' : ' − ${_notasCredito.length} nota(s) de crédito'}"
                : "$_cantidadActual documento(s) en el periodo",
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(formatearColones(_totalActual), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primary)),
          const SizedBox(height: 14),
          BotonesExportar(onPdf: vacio ? null : _exportarPdf, onExcel: vacio ? null : _exportarExcel),
        ],
      ),
    );
  }

  Widget _buildLista() {
    switch (_tipo) {
      case _TipoReporte.ventas:
        if (_facturas.isEmpty && _notasCredito.isEmpty) return _vacio("No hay ventas en este periodo.");
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          itemCount: _facturas.length + _notasCredito.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            // Después de las facturas, las notas de crédito (restan).
            if (i >= _facturas.length) {
              final n = _notasCredito[i - _facturas.length];
              return _filaReporte(
                icono: Icons.assignment_return_outlined,
                titulo: n.receptorNombre,
                subtitulo: "Nota de crédito ${n.consecutivo} • anula F-${n.facturaConsecutivo ?? ''} • ${n.fechaEmision.split('T')[0]}",
                monto: -n.total,
              );
            }
            final f = _facturas[i];
            return _filaReporte(
              icono: Icons.receipt_long_outlined,
              titulo: f.receptorNombre,
              subtitulo: "F-${f.consecutivo} • ${f.fechaEmision.split('T')[0]} • ${f.condicionVenta == "02" ? 'Crédito' : 'Contado'}",
              monto: f.totalFactura,
            );
          },
        );
      case _TipoReporte.ingresos:
        if (_ingresos.isEmpty) return _vacio("No hay ingresos en este periodo.");
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          itemCount: _ingresos.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final ing = _ingresos[i];
            return _filaReporte(
              icono: Icons.trending_up,
              titulo: ing.clienteNombre.isNotEmpty ? ing.clienteNombre : "Cliente sin especificar",
              subtitulo: "${ing.fecha}${ing.referencia.isNotEmpty ? ' • ${ing.referencia}' : ''} • ${ing.condicionVenta == '02' ? 'Crédito' : 'Contado'}",
              monto: ing.total,
            );
          },
        );
      case _TipoReporte.compras:
        if (_compras.isEmpty) return _vacio("No hay compras en este periodo.");
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          itemCount: _compras.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final c = _compras[i];
            return _filaReporte(
              icono: Icons.shopping_cart_outlined,
              titulo: c.nombreProveedor ?? "Proveedor sin especificar",
              subtitulo: "${c.fechaCompra.split('T')[0]}${c.numeroFacturaProveedor.isNotEmpty ? ' • Factura: ${c.numeroFacturaProveedor}' : ''}",
              monto: c.totalCompra,
            );
          },
        );
      case _TipoReporte.gastos:
        if (_gastos.isEmpty) return _vacio("No hay gastos en este periodo.");
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          itemCount: _gastos.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final g = _gastos[i];
            return _filaReporte(
              icono: Icons.payments_outlined,
              titulo: g.categoriaLabel,
              subtitulo: "${g.fecha}${g.descripcion.isNotEmpty ? ' • ${g.descripcion}' : ''}",
              monto: g.monto,
            );
          },
        );
      case _TipoReporte.notasCredito:
        if (_notasCredito.isEmpty) return _vacio("No hay notas de crédito en este periodo.");
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          itemCount: _notasCredito.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final n = _notasCredito[i];
            if (n.estadoHacienda != '2') {
              return _filaNotaCredito(n);
            }
            // Todavia "Procesando": el reintento automatico del backend ya
            // se rindio, asi que se ofrece este boton para reintentar a
            // mano (mismo patron que "CONSULTAR ESTADO EN HACIENDA" en el
            // detalle de factura).
            return Container(
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(backgroundColor: const Color(0xFFEEF2FF), child: Icon(Icons.assignment_return_outlined, color: AppColors.primary, size: 20)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(n.receptorNombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text(
                              "NC-${n.consecutivo} • Anula F-${n.facturaConsecutivo ?? ''} • ${n.fechaEmision.split('T')[0]}",
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Text(formatearColones(n.total), style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.orange),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        minimumSize: const Size(double.infinity, 0),
                      ),
                      icon: const Icon(Icons.refresh, color: Colors.orange, size: 18),
                      label: const Text("CONSULTAR ESTADO EN HACIENDA", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: _consultandoNota ? null : () => _consultarEstadoNotaCredito(n),
                    ),
                  ),
                ],
              ),
            );
          },
        );
    }
  }

  bool _compartiendoNota = false;

  /// Pregunta si compartir solo el PDF o los 3 archivos oficiales (PDF, XML
  /// firmado y XML de respuesta de Hacienda) de una nota de credito ya
  /// aceptada, y llama a ExportService.shareDocumentosOficialesNotaCredito.
  Future<void> _elegirYCompartirNota(NotaCredito nota) async {
    final soloPdf = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Compartir Nota de Crédito"),
        content: const Text("¿Qué archivos quiere compartir?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          OutlinedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Solo PDF")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("PDF + XML + XML Hacienda")),
        ],
      ),
    );
    if (soloPdf == null || !mounted) return;

    setState(() => _compartiendoNota = true);
    try {
      await ExportService.shareDocumentosOficialesNotaCredito(nota, soloPdf: soloPdf);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _compartiendoNota = false);
    }
  }

  Widget _filaNotaCredito(NotaCredito n) {
    final aceptada = n.estadoHacienda == '3';
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(backgroundColor: const Color(0xFFEEF2FF), child: Icon(Icons.assignment_return_outlined, color: AppColors.primary, size: 20)),
        title: Text(n.receptorNombre, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          "NC-${n.consecutivo} • Anula F-${n.facturaConsecutivo ?? ''} • ${n.fechaEmision.split('T')[0]}",
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(formatearColones(n.total), style: const TextStyle(fontWeight: FontWeight.bold)),
            if (aceptada)
              IconButton(
                icon: const Icon(Icons.share_outlined, size: 20),
                tooltip: "Compartir",
                onPressed: _compartiendoNota ? null : () => _elegirYCompartirNota(n),
              ),
          ],
        ),
      ),
    );
  }

  Widget _vacio(String mensaje) => Center(child: Text(mensaje, style: const TextStyle(color: Colors.grey)));

  Widget _filaReporte({required IconData icono, required String titulo, required String subtitulo, required double monto}) {
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(backgroundColor: const Color(0xFFEEF2FF), child: Icon(icono, color: AppColors.primary, size: 20)),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitulo, style: const TextStyle(fontSize: 12)),
        trailing: Text(
          monto < 0 ? "-${formatearColones(-monto)}" : formatearColones(monto),
          style: TextStyle(fontWeight: FontWeight.bold, color: monto < 0 ? Colors.red[400] : null),
        ),
      ),
    );
  }
}
