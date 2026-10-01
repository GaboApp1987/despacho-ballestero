import 'dart:async';
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
  final bool esContador;

  const ReportesContadorScreen({super.key, this.esContador = false});

  @override
  State<ReportesContadorScreen> createState() => _ReportesContadorScreenState();
}

class _ReportesContadorScreenState extends State<ReportesContadorScreen> {
  bool _cargandoNegocios = true;
  List<Negocio> _negocios = [];
  final Set<Negocio> _negociosSeleccionados = {};
  _TipoReporteContador _tipo = _TipoReporteContador.ambos;
  late DateTime _fechaInicio;
  late DateTime _fechaFin;

  Color get _colorFondo => widget.esContador ? TemaContador.fondo : AppColors.background;
  Color get _colorSuperficie => widget.esContador ? TemaContador.superficie : AppColors.surface;
  Color get _colorBorde => widget.esContador ? TemaContador.borde : AppColors.border;
  Color get _colorTenue => widget.esContador ? TemaContador.textoTenue : AppColors.textMuted;
  Color get _colorFuerte => widget.esContador ? TemaContador.textoFuerte : AppColors.textStrong;
  Color get _colorAcento => widget.esContador ? TemaContador.acento : const Color(0xFF4338CA);

  bool _generando = false;
  // Progreso visible mientras se piden los reportes cliente por cliente
  // (con "Todos" puede tardar) -- ver _tarjetaGenerando.
  int _progresoHecho = 0;
  int _progresoTotal = 0;
  String _clienteEnCurso = '';
  // Un solo cliente seleccionado -> _reporte (vista detallada de siempre).
  // Dos o más -> _reportes (resumen por cliente + exportación combinada).
  Map<String, dynamic>? _reporte;
  List<Map<String, dynamic>>? _reportes;
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
            if (negocios.isNotEmpty) _negociosSeleccionados.add(negocios.first);
          });
        }
      }
    } catch (_) {
      // Si falla, el selector simplemente queda vacío.
    }
    if (mounted) setState(() => _cargandoNegocios = false);
  }

  /// Los botones de exportar llamaban a ExportService directo en el
  /// onPressed -- si algo fallaba (ej. un dato inesperado del backend), la
  /// excepción quedaba en un Future sin capturar y no pasaba nada visible:
  /// "toco el ícono de Excel y no hace nada". Con esto al menos se ve el
  /// error real en pantalla en vez de fallar en silencio.
  ///
  /// Mientras se arma el archivo (con muchos clientes tarda unos segundos)
  /// se muestra una ventana con animación -- antes la pantalla quedaba
  /// quieta y parecía trabada.
  Future<void> _exportar(Future<void> Function() accion, {required String formato}) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogoExportando(formato: formato, acento: _colorAcento, fondo: _colorSuperficie, texto: _colorFuerte, tenue: _colorTenue),
    );
    // Un par de frames para que la ventana se dibuje antes del trabajo pesado.
    await Future.delayed(const Duration(milliseconds: 150));
    try {
      await accion();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("No se pudo exportar: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
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

  Future<Map<String, dynamic>> _pedirReporte(int negocioId, String tipoStr) async {
    final r = await ApiService.get(
      '/reportes/consolidado/?negocio=$negocioId'
      '&fecha_inicio=${_fmtFecha(_fechaInicio)}&fecha_fin=${_fmtFecha(_fechaFin)}&tipo=$tipoStr',
    );
    final data = json.decode(utf8.decode(r.bodyBytes));
    if (r.statusCode != 200) {
      throw Exception(data['detail'] ?? 'No se pudo generar el reporte.');
    }
    return data as Map<String, dynamic>;
  }

  Future<void> _generarReporte() async {
    if (_negociosSeleccionados.isEmpty) return;
    setState(() {
      _generando = true;
      _error = null;
      _reporte = null;
      _reportes = null;
      _progresoHecho = 0;
      _progresoTotal = _negociosSeleccionados.length;
      _clienteEnCurso = _negociosSeleccionados.first.nombreComercial;
    });
    final tipoStr = switch (_tipo) {
      _TipoReporteContador.ventas => 'ventas',
      _TipoReporteContador.compras => 'compras',
      _TipoReporteContador.ambos => 'ambos',
    };
    try {
      if (_negociosSeleccionados.length == 1) {
        final data = await _pedirReporte(_negociosSeleccionados.first.id, tipoStr);
        if (mounted) setState(() => _reporte = data);
      } else {
        // Uno por uno (no en paralelo) para no saturar al backend si el
        // contador elige "Todos" con una cartera grande de negocios.
        final reportes = <Map<String, dynamic>>[];
        for (final negocio in _negociosSeleccionados) {
          if (mounted) setState(() => _clienteEnCurso = negocio.nombreComercial);
          reportes.add(await _pedirReporte(negocio.id, tipoStr));
          if (mounted) setState(() => _progresoHecho++);
        }
        if (mounted) setState(() => _reportes = reportes);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  Future<void> _elegirClientes() async {
    final seleccionTemporal = Set<Negocio>.from(_negociosSeleccionados);
    final resultado = await showDialog<Set<Negocio>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text("Elegí los clientes"),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  title: const Text("Seleccionar todos", style: TextStyle(fontWeight: FontWeight.bold)),
                  value: seleccionTemporal.length == _negocios.length,
                  onChanged: (marcado) => setDialogState(() {
                    if (marcado == true) {
                      seleccionTemporal
                        ..clear()
                        ..addAll(_negocios);
                    } else {
                      seleccionTemporal.clear();
                    }
                  }),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: _negocios
                        .map((n) => CheckboxListTile(
                              title: Text(n.nombreComercial, overflow: TextOverflow.ellipsis),
                              value: seleccionTemporal.contains(n),
                              onChanged: (marcado) => setDialogState(() {
                                if (marcado == true) {
                                  seleccionTemporal.add(n);
                                } else {
                                  seleccionTemporal.remove(n);
                                }
                              }),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
            ElevatedButton(
              style: widget.esContador
                  ? ElevatedButton.styleFrom(backgroundColor: TemaContador.acento, foregroundColor: Colors.white)
                  : null,
              onPressed: seleccionTemporal.isEmpty ? null : () => Navigator.pop(ctx, seleccionTemporal),
              child: const Text("Listo"),
            ),
          ],
        ),
      ),
    );
    if (resultado != null) {
      setState(() {
        _negociosSeleccionados
          ..clear()
          ..addAll(resultado);
        _reporte = null;
        _reportes = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        backgroundColor: widget.esContador ? TemaContador.fondo : const Color(0xFF4F46E5),
        foregroundColor: widget.esContador ? TemaContador.textoFuerte : Colors.white,
        iconTheme: IconThemeData(color: widget.esContador ? TemaContador.textoFuerte : Colors.white),
        elevation: 0,
        title: Text(
          "Reportes",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: widget.esContador ? TemaContador.textoFuerte : Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Elegí el cliente, el período y qué querés ver.",
              style: TextStyle(fontSize: 13, color: _colorTenue),
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
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _generando ? _tarjetaGenerando() : const SizedBox.shrink(),
            ),
            if (_reporte != null) _resultados(),
            if (_reportes != null) _resultadosMultiples(),
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
        color: _colorSuperficie,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Cliente(s)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _colorTenue)),
          const SizedBox(height: 6),
          _cargandoNegocios
              ? const LinearProgressIndicator()
              : _negocios.isEmpty
                  ? Text("No tenés negocios en tu cartera todavía.", style: TextStyle(color: _colorTenue))
                  : InkWell(
                      onTap: _elegirClientes,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(border: Border.all(color: _colorBorde), borderRadius: BorderRadius.circular(10)),
                        child: Row(
                          children: [
                            Icon(Icons.people_outline, size: 18, color: _colorTenue),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _negociosSeleccionados.isEmpty
                                    ? "Elegí uno o más clientes"
                                    : _negociosSeleccionados.length == 1
                                        ? _negociosSeleccionados.first.nombreComercial
                                        : _negociosSeleccionados.length == _negocios.length
                                            ? "Todos los clientes (${_negocios.length})"
                                            : "${_negociosSeleccionados.length} clientes seleccionados",
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: _colorFuerte),
                              ),
                            ),
                            Icon(Icons.arrow_drop_down, color: _colorTenue),
                          ],
                        ),
                      ),
                    ),
          const SizedBox(height: 16),
          Text("Período", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _colorTenue)),
          const SizedBox(height: 6),
          InkWell(
            onTap: _elegirRangoFechas,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(border: Border.all(color: _colorBorde), borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  Icon(Icons.date_range, size: 18, color: _colorTenue),
                  const SizedBox(width: 8),
                  Text(_periodoTexto, style: TextStyle(color: _colorFuerte)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text("Qué mostrar", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _colorTenue)),
          const SizedBox(height: 6),
          SegmentedButton<_TipoReporteContador>(
            segments: const [
              ButtonSegment(value: _TipoReporteContador.ventas, label: Text("Ventas")),
              ButtonSegment(value: _TipoReporteContador.compras, label: Text("Compras")),
              ButtonSegment(value: _TipoReporteContador.ambos, label: Text("Ambos")),
            ],
            selected: {_tipo},
            onSelectionChanged: (s) => setState(() => _tipo = s.first),
            style: widget.esContador
                ? SegmentedButton.styleFrom(
                    selectedBackgroundColor: TemaContador.acento,
                    selectedForegroundColor: Colors.white,
                    foregroundColor: TemaContador.textoFuerte,
                    side: const BorderSide(color: TemaContador.borde),
                  )
                : null,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: widget.esContador
                  ? ElevatedButton.styleFrom(backgroundColor: TemaContador.acento, foregroundColor: Colors.white)
                  : null,
              onPressed: (_generando || _negociosSeleccionados.isEmpty) ? null : _generarReporte,
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

  /// Tarjeta animada mientras se genera: ícono que late, el cliente que se
  /// está procesando, una barra que avanza cliente por cliente y mensajes
  /// que van rotando, para que se note que está trabajando.
  Widget _tarjetaGenerando() {
    final varios = _progresoTotal > 1;
    final valor = varios ? _progresoHecho / _progresoTotal : null;
    return Container(
      key: const ValueKey('generando'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _colorSuperficie,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _colorAcento.withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconoPulsante(icono: Icons.insert_chart_outlined, color: _colorAcento),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Generando reporte…", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _colorFuerte)),
                    const SizedBox(height: 2),
                    Text(
                      varios
                          ? "Cliente ${(_progresoHecho + 1).clamp(1, _progresoTotal)} de $_progresoTotal: $_clienteEnCurso"
                          : _clienteEnCurso,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: _colorTenue),
                    ),
                  ],
                ),
              ),
              if (varios)
                Text("${(valor! * 100).round()}%", style: TextStyle(fontWeight: FontWeight.w800, color: _colorAcento)),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: valor ?? 0),
              duration: const Duration(milliseconds: 400),
              builder: (_, v, __) => LinearProgressIndicator(
                value: varios ? v : null,
                minHeight: 6,
                backgroundColor: _colorBorde,
                valueColor: AlwaysStoppedAnimation(_colorAcento),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _MensajesRotativos(color: _colorTenue),
        ],
      ),
    );
  }

  Widget _resultadosMultiples() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                "Resultado (${_reportes!.length} clientes)",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _colorFuerte),
              ),
            ),
            TextButton.icon(
              onPressed: () => _exportar(() => ExportService.exportReportesConsolidadosToPdf(_reportes!, _periodoTexto), formato: 'PDF'),
              icon: const Icon(Icons.picture_as_pdf, color: Colors.redAccent, size: 18),
              label: const Text("PDF"),
            ),
            TextButton.icon(
              onPressed: () => _exportar(() => ExportService.exportReportesConsolidadosToExcel(_reportes!), formato: 'Excel'),
              icon: const Icon(Icons.table_chart, color: Colors.green, size: 18),
              label: const Text("Excel"),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          "Vista resumida por cliente. El detalle completo (documento por documento) va en el PDF o Excel exportado.",
          style: TextStyle(fontSize: 11, color: _colorTenue),
        ),
        const SizedBox(height: 12),
        ..._reportes!.map((r) {
          final ventas = r['ventas'] as Map<String, dynamic>?;
          final compras = r['compras'] as Map<String, dynamic>?;
          final resumen = r['resumen_declaracion'] as Map<String, dynamic>?;
          final ivaAPagar = resumen != null ? double.tryParse(resumen['iva_a_pagar'].toString()) ?? 0 : null;
          return _tarjeta(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r['negocio_nombre']?.toString() ?? '', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _colorFuerte)),
                const SizedBox(height: 8),
                if (ventas != null) _filaDocumento("Ventas", total: double.tryParse(ventas['total'].toString()) ?? 0),
                if (compras != null) _filaDocumento("Compras", total: double.tryParse(compras['total'].toString()) ?? 0),
                if (ivaAPagar != null) ...[
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("IVA a pagar", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _colorFuerte)),
                      Text(
                        formatearColones(ivaAPagar),
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: ivaAPagar >= 0 ? _colorAcento : Colors.green),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _resultados() {
    final ventas = _reporte!['ventas'] as Map<String, dynamic>?;
    final compras = _reporte!['compras'] as Map<String, dynamic>?;
    final resumen = _reporte!['resumen_declaracion'] as Map<String, dynamic>?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text("Resultado", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _colorFuerte)),
            ),
            TextButton.icon(
              onPressed: () => _exportar(() => ExportService.exportReporteConsolidadoToPdf(_reporte!, _periodoTexto), formato: 'PDF'),
              icon: const Icon(Icons.picture_as_pdf, color: Colors.redAccent, size: 18),
              label: const Text("PDF"),
            ),
            TextButton.icon(
              onPressed: () => _exportar(() => ExportService.exportReporteConsolidadoToExcel(_reporte!), formato: 'Excel'),
              icon: const Icon(Icons.table_chart, color: Colors.green, size: 18),
              label: const Text("Excel"),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (resumen != null) _seccionResumenDeclaracion(resumen),
        if (ventas != null) _seccionVentas(ventas),
        if (compras != null) _seccionCompras(compras),
      ],
    );
  }

  Widget _tarjeta({required Widget child}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _colorSuperficie, borderRadius: BorderRadius.circular(14), border: Border.all(color: _colorBorde)),
        child: child,
      );

  Widget _filaDocumento(String titulo, {String? subtitulo, required double total, double? iva, bool esEstimado = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: TextStyle(fontSize: 12, color: _colorFuerte), overflow: TextOverflow.ellipsis),
                if (subtitulo != null) Text(subtitulo, style: TextStyle(fontSize: 11, color: _colorTenue)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatearColones(total), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _colorFuerte)),
              if (iva != null)
                Text(
                  "IVA: ${formatearColones(iva)}${esEstimado ? ' (est.)' : ''}",
                  style: TextStyle(fontSize: 10, color: _colorTenue),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tablaDesglose(List desglose) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: desglose
          .map((d) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(d['tarifa']?.toString() ?? '', style: TextStyle(fontSize: 12, color: _colorFuerte)),
                    Text(
                      "Base: ${formatearColones(double.tryParse(d['base_imponible'].toString()) ?? 0)} · "
                      "Impuesto: ${formatearColones(double.tryParse(d['monto_impuesto'].toString()) ?? 0)}",
                      style: TextStyle(fontSize: 12, color: _colorFuerte),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _seccionResumenDeclaracion(Map<String, dynamic> r) {
    final ventasPorTarifa = (r['ventas_por_tarifa'] as List?) ?? [];
    final comprasPorTarifa = (r['compras_por_tarifa'] as List?) ?? [];
    final ivaAPagar = double.tryParse(r['iva_a_pagar'].toString()) ?? 0;
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_outlined, color: _colorAcento, size: 18),
              const SizedBox(width: 8),
              Text("Resumen para la declaración de IVA (D-104)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _colorFuerte)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "Ventas y compras gravadas por tarifa, netas de notas de crédito.",
            style: TextStyle(fontSize: 11, color: _colorTenue),
          ),
          const SizedBox(height: 12),
          Text("Ventas gravadas", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _colorTenue)),
          const SizedBox(height: 6),
          ventasPorTarifa.isEmpty
              ? Text("Sin ventas gravadas en este período.", style: TextStyle(fontSize: 12, color: _colorTenue))
              : _tablaDesglose(ventasPorTarifa),
          const SizedBox(height: 12),
          Text("Compras gravadas", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _colorTenue)),
          const SizedBox(height: 6),
          comprasPorTarifa.isEmpty
              ? Text("Sin compras gravadas en este período.", style: TextStyle(fontSize: 12, color: _colorTenue))
              : _tablaDesglose(comprasPorTarifa),
          const SizedBox(height: 12),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("IVA a pagar (ventas − crédito fiscal de compras)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _colorFuerte)),
              Text(
                formatearColones(ivaAPagar),
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: ivaAPagar >= 0 ? _colorAcento : Colors.green),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _seccionVentas(Map<String, dynamic> ventas) {
    final documentos = (ventas['documentos'] as List?) ?? [];
    final notasCredito = (ventas['notas_credito'] as List?) ?? [];
    final desglose = (ventas['desglose_impuestos'] as List?) ?? [];
    final total = double.tryParse(ventas['total'].toString()) ?? 0;
    final totalNotas = double.tryParse(ventas['total_notas_credito'].toString()) ?? 0;
    final totalNeto = double.tryParse(ventas['total_neto'].toString()) ?? 0;
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Ventas (${documentos.length})", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _colorFuerte)),
              Text(formatearColones(total), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _colorAcento)),
            ],
          ),
          const SizedBox(height: 10),
          if (documentos.isEmpty)
            Text("Sin ventas en este período.", style: TextStyle(color: _colorTenue))
          else
            ...documentos.map((f) => _filaDocumento(
                  "${f['tipo_documento']} ${f['consecutivo']} · ${f['cliente'] ?? ''}",
                  total: double.tryParse(f['total'].toString()) ?? 0,
                  iva: double.tryParse(f['monto_iva'].toString()) ?? 0,
                )),
          if (notasCredito.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Notas de Crédito (${notasCredito.length})", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _colorTenue)),
                Text("- ${formatearColones(totalNotas)}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red)),
              ],
            ),
            const SizedBox(height: 6),
            ...notasCredito.map((n) => _filaDocumento(
                  "NC ${n['consecutivo']}${n['factura_anulada'] != null ? ' · anula F-${n['factura_anulada']}' : ''}",
                  subtitulo: n['motivo']?.toString(),
                  total: double.tryParse(n['total'].toString()) ?? 0,
                  iva: double.tryParse(n['monto_iva'].toString()) ?? 0,
                )),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Total neto (ventas − notas de crédito)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _colorFuerte)),
                Text(formatearColones(totalNeto), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _colorFuerte)),
              ],
            ),
          ],
          if (desglose.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(),
            Text("Desglose de IVA por tarifa (neto de notas de crédito)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _colorTenue)),
            const SizedBox(height: 6),
            _tablaDesglose(desglose),
          ],
        ],
      ),
    );
  }

  Widget _seccionCompras(Map<String, dynamic> compras) {
    final documentos = (compras['documentos'] as List?) ?? [];
    final notasDebito = (compras['notas_debito'] as List?) ?? [];
    final desglose = (compras['desglose_impuestos'] as List?) ?? [];
    final total = double.tryParse(compras['total'].toString()) ?? 0;
    final totalNotas = double.tryParse(compras['total_notas_debito'].toString()) ?? 0;
    final totalNeto = double.tryParse(compras['total_neto'].toString()) ?? 0;
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Compras (${documentos.length})", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _colorFuerte)),
              Text(formatearColones(total), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _colorAcento)),
            ],
          ),
          const SizedBox(height: 10),
          if (documentos.isEmpty)
            Text("Sin compras en este período.", style: TextStyle(color: _colorTenue))
          else
            ...documentos.map((c) => _filaDocumento(
                  "${c['proveedor'] ?? 'Sin proveedor'} · N.° ${c['numero_factura_proveedor'] ?? ''}",
                  total: double.tryParse(c['total'].toString()) ?? 0,
                  iva: double.tryParse(c['monto_iva_estimado'].toString()) ?? 0,
                  esEstimado: true,
                )),
          if (notasDebito.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Notas de Débito (${notasDebito.length})", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _colorTenue)),
                Text("+ ${formatearColones(totalNotas)}", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _colorFuerte)),
              ],
            ),
            const SizedBox(height: 6),
            ...notasDebito.map((n) => _filaDocumento(
                  "ND ${n['numero_documento'] ?? ''} · ${n['proveedor'] ?? ''}",
                  subtitulo: n['motivo']?.toString(),
                  total: double.tryParse(n['monto'].toString()) ?? 0,
                )),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Total neto (compras + notas de débito)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _colorFuerte)),
                Text(formatearColones(totalNeto), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _colorFuerte)),
              ],
            ),
          ],
          if (desglose.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(),
            Text("Desglose de IVA por tarifa (estimado)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _colorTenue)),
            const SizedBox(height: 6),
            _tablaDesglose(desglose),
            const SizedBox(height: 6),
            Text(
              compras['nota_desglose']?.toString() ?? '',
              style: TextStyle(fontSize: 10, color: _colorTenue, fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }
}


/// Ícono que "late" (escala y opacidad) mientras se trabaja.
class _IconoPulsante extends StatefulWidget {
  final IconData icono;
  final Color color;
  const _IconoPulsante({required this.icono, required this.color});

  @override
  State<_IconoPulsante> createState() => _IconoPulsanteState();
}

class _IconoPulsanteState extends State<_IconoPulsante> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = Curves.easeInOut.transform(_c.value);
        return Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withOpacity(0.10 + 0.12 * t),
          ),
          child: Transform.scale(
            scale: 0.9 + 0.15 * t,
            child: Icon(widget.icono, color: widget.color, size: 24),
          ),
        );
      },
    );
  }
}

/// Mensajes cortos que van rotando mientras se genera.
class _MensajesRotativos extends StatefulWidget {
  final Color color;
  const _MensajesRotativos({required this.color});

  @override
  State<_MensajesRotativos> createState() => _MensajesRotativosState();
}

class _MensajesRotativosState extends State<_MensajesRotativos> {
  static const _mensajes = [
    "Sumando ventas y notas de crédito…",
    "Revisando las compras del período…",
    "Calculando el IVA por tarifa…",
    "Armando el resumen para la declaración…",
  ];
  int _i = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 2200), (_) {
      if (mounted) setState(() => _i = (_i + 1) % _mensajes.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(anim), child: child),
      ),
      child: Text(_mensajes[_i], key: ValueKey(_i), style: TextStyle(fontSize: 12.5, color: widget.color)),
    );
  }
}

/// Ventana mientras se arma el PDF/Excel exportado.
class _DialogoExportando extends StatelessWidget {
  final String formato;
  final Color acento;
  final Color fondo;
  final Color texto;
  final Color tenue;
  const _DialogoExportando({required this.formato, required this.acento, required this.fondo, required this.texto, required this.tenue});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: fondo,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _IconoPulsante(icono: formato == 'Excel' ? Icons.table_chart_outlined : Icons.picture_as_pdf_outlined, color: acento),
              const SizedBox(height: 16),
              Text("Preparando tu $formato…", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: texto)),
              const SizedBox(height: 6),
              Text("Con muchos clientes puede tardar unos segundos.", textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: tenue)),
              const SizedBox(height: 18),
              SizedBox(
                width: 220,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(minHeight: 5, valueColor: AlwaysStoppedAnimation(acento), backgroundColor: acento.withOpacity(0.15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
