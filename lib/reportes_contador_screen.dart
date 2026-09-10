import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

import 'api_service.dart';
import 'export_service.dart';
import 'formato.dart';
import 'negocio.dart';

enum _TipoReporteContador { ventas, compras, ambos }

/// Pestaña de Reportes para el contador/despacho: a diferencia de
/// ReportesScreen (que ya vive dentro del detalle de UN negocio puntual),
/// esta arranca sin negocio fijo -- primero elegís CUÁL cliente de la
/// cartera, y con qué rango de fechas y tipo (ventas/compras/ambos), y
/// consume /reportes/consolidado/ (ver ReporteConsolidadoView) que ya
/// devuelve el desglose de IVA por tarifa para ventas.
class ReportesContadorScreen extends StatefulWidget {
  const ReportesContadorScreen({super.key});

  @override
  State<ReportesContadorScreen> createState() => _ReportesContadorScreenState();
}

class _ReportesContadorScreenState extends State<ReportesContadorScreen> {
  bool _cargandoNegocios = true;
  List<Negocio> _negocios = [];
  Negocio? _negocioSeleccionado;
  _TipoReporteContador _tipo = _TipoReporteContador.ambos;
  late DateTime _fechaInicio;
  late DateTime _fechaFin;

  bool _generando = false;
  Map<String, dynamic>? _reporte;
  String? _error;

  @override
  void initState() {
    super.initState();
    final ahora = DateTime.now();
    _fechaInicio = DateTime(ahora.year, ahora.month, 1);
    _fechaFin = DateTime(ahora.year, ahora.month + 1, 0);
    _cargarNegocios();
  }

  Future<void> _cargarNegocios() async {
    setState(() => _cargandoNegocios = true);
    try {
      final r = await ApiService.get('/negocios/');
      if (r.statusCode == 200) {
        final data = json.decode(utf8.decode(r.bodyBytes)) as List;
        final negocios = data.map((j) => Negocio.fromJson(j)).toList();
        if (mounted) {
          setState(() {
            _negocios = negocios;
            _negocioSeleccionado = negocios.isNotEmpty ? negocios.first : null;
          });
        }
      }
    } catch (_) {
      // Si falla, el selector simplemente queda vacío.
    }
    if (mounted) setState(() => _cargandoNegocios = false);
  }

  String _fmtFecha(DateTime d) => "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  String get _periodoTexto =>
      "${_fechaInicio.day}/${_fechaInicio.month}/${_fechaInicio.year} - ${_fechaFin.day}/${_fechaFin.month}/${_fechaFin.year}";

  Future<void> _elegirRangoFechas() async {
    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
      initialDateRange: DateTimeRange(start: _fechaInicio, end: _fechaFin),
    );
    if (rango != null) {
      setState(() {
        _fechaInicio = rango.start;
        _fechaFin = rango.end;
      });
    }
  }

  Future<void> _generarReporte() async {
    if (_negocioSeleccionado == null) return;
    setState(() {
      _generando = true;
      _error = null;
    });
    try {
      final tipoStr = switch (_tipo) {
        _TipoReporteContador.ventas => 'ventas',
        _TipoReporteContador.compras => 'compras',
        _TipoReporteContador.ambos => 'ambos',
      };
      final r = await ApiService.get(
        '/reportes/consolidado/?negocio=${_negocioSeleccionado!.id}'
        '&fecha_inicio=${_fmtFecha(_fechaInicio)}&fecha_fin=${_fmtFecha(_fechaFin)}&tipo=$tipoStr',
      );
      final data = json.decode(utf8.decode(r.bodyBytes));
      if (r.statusCode != 200) {
        throw Exception(data['detail'] ?? 'No se pudo generar el reporte.');
      }
      if (mounted) setState(() => _reporte = data);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: const Color(0xFF4F46E5),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text("Reportes", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Elegí el cliente, el período y qué querés ver.",
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 20),
            _tarjetaFiltros(),
            const SizedBox(height: 20),
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            if (_reporte != null) _resultados(),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaFiltros() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Cliente", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
          const SizedBox(height: 6),
          _cargandoNegocios
              ? const LinearProgressIndicator()
              : _negocios.isEmpty
                  ? Text("No tenés negocios en tu cartera todavía.", style: TextStyle(color: AppColors.textMuted))
                  : DropdownButtonFormField<Negocio>(
                      initialValue: _negocioSeleccionado,
                      isExpanded: true,
                      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                      items: _negocios
                          .map((n) => DropdownMenuItem(value: n, child: Text(n.nombreComercial, overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: (n) => setState(() {
                        _negocioSeleccionado = n;
                        _reporte = null;
                      }),
                    ),
          const SizedBox(height: 16),
          Text("Período", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
          const SizedBox(height: 6),
          InkWell(
            onTap: _elegirRangoFechas,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  Icon(Icons.date_range, size: 18, color: AppColors.textMuted),
                  const SizedBox(width: 8),
                  Text(_periodoTexto),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text("Qué mostrar", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
          const SizedBox(height: 6),
          SegmentedButton<_TipoReporteContador>(
            segments: const [
              ButtonSegment(value: _TipoReporteContador.ventas, label: Text("Ventas")),
              ButtonSegment(value: _TipoReporteContador.compras, label: Text("Compras")),
              ButtonSegment(value: _TipoReporteContador.ambos, label: Text("Ambos")),
            ],
            selected: {_tipo},
            onSelectionChanged: (s) => setState(() => _tipo = s.first),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_generando || _negocioSeleccionado == null) ? null : _generarReporte,
              icon: _generando
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.insert_chart_outlined),
              label: Text(_generando ? "Generando..." : "Generar reporte"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultados() {
    final ventas = _reporte!['ventas'] as Map<String, dynamic>?;
    final compras = _reporte!['compras'] as Map<String, dynamic>?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text("Resultado", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textStrong)),
            ),
            TextButton.icon(
              onPressed: () => ExportService.exportReporteConsolidadoToPdf(_reporte!, _periodoTexto),
              icon: const Icon(Icons.picture_as_pdf, color: Colors.redAccent, size: 18),
              label: const Text("PDF"),
            ),
            TextButton.icon(
              onPressed: () => ExportService.exportReporteConsolidadoToExcel(_reporte!),
              icon: const Icon(Icons.table_chart, color: Colors.green, size: 18),
              label: const Text("Excel"),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (ventas != null) _seccionVentas(ventas),
        if (compras != null) _seccionCompras(compras),
      ],
    );
  }

  Widget _seccionVentas(Map<String, dynamic> ventas) {
    final documentos = (ventas['documentos'] as List?) ?? [];
    final desglose = (ventas['desglose_impuestos'] as List?) ?? [];
    final total = double.tryParse(ventas['total'].toString()) ?? 0;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Ventas (${documentos.length})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text(formatearColones(total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF4338CA))),
            ],
          ),
          const SizedBox(height: 10),
          if (documentos.isEmpty)
            Text("Sin ventas en este período.", style: TextStyle(color: AppColors.textMuted))
          else
            ...documentos.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          "${f['tipo_documento']} ${f['consecutivo']} · ${f['cliente'] ?? ''}",
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        formatearColones(double.tryParse(f['total'].toString()) ?? 0),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                )),
          if (desglose.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(),
            Text("Desglose de IVA por tarifa", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
            const SizedBox(height: 6),
            ...desglose.map((d) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(d['tarifa']?.toString() ?? '', style: const TextStyle(fontSize: 12)),
                      Text(
                        "Base: ${formatearColones(double.tryParse(d['base_imponible'].toString()) ?? 0)} · "
                        "Impuesto: ${formatearColones(double.tryParse(d['monto_impuesto'].toString()) ?? 0)}",
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _seccionCompras(Map<String, dynamic> compras) {
    final documentos = (compras['documentos'] as List?) ?? [];
    final total = double.tryParse(compras['total'].toString()) ?? 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Compras (${documentos.length})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text(formatearColones(total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF4338CA))),
            ],
          ),
          const SizedBox(height: 10),
          if (documentos.isEmpty)
            Text("Sin compras en este período.", style: TextStyle(color: AppColors.textMuted))
          else
            ...documentos.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          "${c['proveedor'] ?? 'Sin proveedor'} · N.° ${c['numero_factura_proveedor'] ?? ''}",
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        formatearColones(double.tryParse(c['total'].toString()) ?? 0),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}
