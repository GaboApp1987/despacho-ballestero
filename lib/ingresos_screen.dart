import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_service.dart';
import 'export_service.dart';
import 'ingreso_operativo.dart';
import 'importar_externo_dialog.dart';
import 'negocio.dart';
import 'formato.dart';

/// Ingresos/ventas que no pasan por Factura -- para negocios que llevan su
/// contabilidad con Equilibra pero no facturan electrónicamente acá (ver
/// IngresoOperativo en el backend). Junto con Compras, alimenta la
/// Declaración de IVA/Renta y "Generar asientos automáticos".
class IngresosScreen extends StatefulWidget {
  final Negocio negocio;
  const IngresosScreen({super.key, required this.negocio});

  @override
  State<IngresosScreen> createState() => _IngresosScreenState();
}

class _IngresosScreenState extends State<IngresosScreen> {
  bool _cargando = true;
  List<IngresoOperativo> _ingresos = [];
  late DateTime _fechaInicio;
  late DateTime _fechaFin;

  @override
  void initState() {
    super.initState();
    final ahora = DateTime.now();
    _fechaInicio = DateTime(ahora.year, ahora.month, 1);
    _fechaFin = DateTime(ahora.year, ahora.month + 1, 0);
    _cargarDatos();
  }

  Future<double> _obtenerTipoCambioDelDia() async {
    try {
      final r = await ApiService.get('/tipo-cambio/');
      if (r.statusCode == 200) {
        final d = json.decode(utf8.decode(r.bodyBytes));
        if (d['disponible'] == true) return (d['venta'] as num).toDouble();
      }
    } catch (_) {}
    return 1.0;
  }

  static const List<String> _nombresMes = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  String _fmtFecha(DateTime d) => "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  String get _periodoTexto =>
      "${_fechaInicio.day}/${_fechaInicio.month}/${_fechaInicio.year} - ${_fechaFin.day}/${_fechaFin.month}/${_fechaFin.year}";

  /// Igual que en Reportes: true si el rango actual es exactamente un mes
  /// calendario completo, para mostrar el nombre del mes en vez del rango.
  bool get _esMesCompleto {
    final primerDia = DateTime(_fechaInicio.year, _fechaInicio.month, 1);
    final ultimoDia = DateTime(_fechaInicio.year, _fechaInicio.month + 1, 0);
    return _fechaInicio.isAtSameMomentAs(primerDia) && _fechaFin.isAtSameMomentAs(ultimoDia);
  }

  String get _mesAnioTexto => '${_nombresMes[_fechaInicio.month - 1]} ${_fechaInicio.year}';

  void _irAMes(int deltaMeses) {
    final base = DateTime(_fechaInicio.year, _fechaInicio.month + deltaMeses, 1);
    setState(() {
      _fechaInicio = DateTime(base.year, base.month, 1);
      _fechaFin = DateTime(base.year, base.month + 1, 0);
    });
    _cargarDatos();
  }

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
      _cargarDatos();
    }
  }

  Future<void> _cargarDatos() async {
    if (!mounted) return;
    setState(() => _cargando = true);
    try {
      final res = await ApiService.get(
        '/ingresos-operativos/?negocio=${widget.negocio.id}&fecha_inicio=${_fmtFecha(_fechaInicio)}&fecha_fin=${_fmtFecha(_fechaFin)}',
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final List data = json.decode(utf8.decode(res.bodyBytes));
        setState(() {
          _ingresos = data.map((j) => IngresoOperativo.fromJson(j)).toList();
          _cargando = false;
        });
      } else {
        setState(() => _cargando = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al cargar ingresos: $e")));
    }
  }

  double get _totalSubtotal => _ingresos.fold(0.0, (s, i) => s + i.monto);
  double get _totalIva => _ingresos.fold(0.0, (s, i) => s + i.montoIva);

  // Igual que _tarifa_de en CompraViewSet.declaracion_iva (backend): la
  // tarifa no se guarda por ingreso, se calcula a partir de lo que
  // realmente se cobró (IVA/subtotal) para que coincida con el desglose
  // que ya usa la Declaración de IVA.
  String _tarifaDe(double subtotal, double iva) {
    if (subtotal == 0) return "0.00";
    return (iva / subtotal * 100).toStringAsFixed(2);
  }

  List<MapEntry<String, List<double>>> get _sumaPorTarifa {
    final mapa = <String, List<double>>{};
    for (final i in _ingresos) {
      final tarifa = _tarifaDe(i.monto, i.montoIva);
      final acumulado = mapa.putIfAbsent(tarifa, () => [0, 0]);
      acumulado[0] += i.monto;
      acumulado[1] += i.montoIva;
    }
    final entradas = mapa.entries.toList()
      ..sort((a, b) => double.parse(b.key).compareTo(double.parse(a.key)));
    return entradas;
  }

  Future<void> _abrirComprobante(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo abrir el comprobante: $url")));
      }
    }
  }

  void _mostrarFormulario({IngresoOperativo? ingresoExistente}) {
    final fechaInicial = ingresoExistente != null && ingresoExistente.fecha.isNotEmpty
        ? DateTime.tryParse(ingresoExistente.fecha) ?? DateTime.now()
        : DateTime.now();
    DateTime fecha = fechaInicial;
    final clienteCtrl = TextEditingController(text: ingresoExistente?.clienteNombre ?? '');
    final referenciaCtrl = TextEditingController(text: ingresoExistente?.referencia ?? '');
    // Si el ingreso ya existente venía en dólares, se muestran de vuelta los
    // montos originales en dólares (monto/montoIva siempre están en
    // colones) para no confundir al editar.
    final montoCtrl = TextEditingController(
      text: ingresoExistente != null ? (ingresoExistente.monto / ingresoExistente.tipoCambio).toStringAsFixed(2) : '',
    );
    final ivaCtrl = TextEditingController(
      text: ingresoExistente != null ? (ingresoExistente.montoIva / ingresoExistente.tipoCambio).toStringAsFixed(2) : '',
    );
    String condicion = ingresoExistente?.condicionVenta ?? '01';
    String moneda = ingresoExistente?.moneda ?? 'CRC';
    final tipoCambioCtrl = TextEditingController(text: (ingresoExistente?.tipoCambio ?? 1.0).toStringAsFixed(2));
    bool guardando = false;

    Future.microtask(() {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
            title: Text(ingresoExistente == null ? "Nuevo Ingreso" : "Editar Ingreso"),
            content: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () async {
                        final elegida = await showDatePicker(
                          context: ctx,
                          initialDate: fecha,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(DateTime.now().year + 1, 12, 31),
                        );
                        if (elegida != null) setStateDialog(() => fecha = elegida);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: "Fecha", border: OutlineInputBorder(), prefixIcon: Icon(Icons.calendar_today)),
                        child: Text("${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}"),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: clienteCtrl,
                      decoration: const InputDecoration(labelText: "Cliente (opcional)", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: referenciaCtrl,
                      decoration: const InputDecoration(labelText: "Referencia / N.° factura (opcional)", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: moneda,
                            decoration: const InputDecoration(labelText: "Moneda", border: OutlineInputBorder()),
                            items: const [
                              DropdownMenuItem(value: 'CRC', child: Text("Colones")),
                              DropdownMenuItem(value: 'USD', child: Text("Dólares")),
                            ],
                            onChanged: (v) async {
                              if (v == 'USD' && tipoCambioCtrl.text.trim() == '1.00') {
                                tipoCambioCtrl.text = (await _obtenerTipoCambioDelDia()).toStringAsFixed(2);
                              }
                              setStateDialog(() => moneda = v!);
                            },
                          ),
                        ),
                        if (moneda == 'USD') ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: tipoCambioCtrl,
                              decoration: const InputDecoration(labelText: "Tipo de cambio", border: OutlineInputBorder()),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: montoCtrl,
                            decoration: InputDecoration(
                              labelText: moneda == 'USD' ? "Subtotal (US\$)" : "Subtotal (₡)",
                              border: const OutlineInputBorder(),
                              prefixText: moneda == 'USD' ? "\$ " : "₡ ",
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: ivaCtrl,
                            decoration: InputDecoration(
                              labelText: moneda == 'USD' ? "IVA (US\$)" : "IVA (₡)",
                              border: const OutlineInputBorder(),
                              prefixText: moneda == 'USD' ? "\$ " : "₡ ",
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: condicion,
                      decoration: const InputDecoration(labelText: "Condición", border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: '01', child: Text("Contado")),
                        DropdownMenuItem(value: '02', child: Text("Crédito")),
                      ],
                      onChanged: (v) => setStateDialog(() => condicion = v!),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: guardando ? null : () => Navigator.pop(ctx), child: const Text("Cancelar")),
              ElevatedButton(
                onPressed: guardando
                    ? null
                    : () async {
                        final monto = double.tryParse(montoCtrl.text.replaceAll(',', '.').trim());
                        if (monto == null || monto <= 0) {
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Ingrese un subtotal válido.")));
                          return;
                        }
                        final iva = double.tryParse(ivaCtrl.text.replaceAll(',', '.').trim()) ?? 0;
                        final tipoCambio = moneda == 'USD'
                            ? (double.tryParse(tipoCambioCtrl.text.replaceAll(',', '.').trim()) ?? 1.0)
                            : 1.0;
                        setStateDialog(() => guardando = true);
                        final fechaStr = "${fecha.year}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}";
                        final body = {
                          'negocio': widget.negocio.id,
                          'fecha': fechaStr,
                          'cliente_nombre': clienteCtrl.text.trim(),
                          'referencia': referenciaCtrl.text.trim(),
                          'moneda': moneda,
                          'tipo_cambio': tipoCambio,
                          // monto/monto_iva SIEMPRE se guardan en colones --
                          // ver IngresoOperativo.moneda/tipoCambio.
                          'monto': redondear2(monto * tipoCambio),
                          'monto_iva': redondear2(iva * tipoCambio),
                          'condicion_venta': condicion,
                        };
                        try {
                          final response = ingresoExistente == null
                              ? await ApiService.post('/ingresos-operativos/', body)
                              : await ApiService.put('/ingresos-operativos/${ingresoExistente.id}/', body);
                          if (response.statusCode == 200 || response.statusCode == 201) {
                            if (ctx.mounted) Navigator.pop(ctx);
                            _cargarDatos();
                          } else {
                            throw Exception(utf8.decode(response.bodyBytes));
                          }
                        } catch (e) {
                          setStateDialog(() => guardando = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text("Error: $e")));
                          }
                        }
                      },
                child: guardando
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text("Guardar"),
              ),
            ],
          ),
        ),
      );
    });
  }

  Future<void> _eliminarIngreso(IngresoOperativo ingreso) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Borrar ingreso?"),
        content: Text("Se eliminará el ingreso de ${formatearColones(ingreso.total)}."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Borrar"),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      final response = await ApiService.delete('/ingresos-operativos/${ingreso.id}/');
      if (response.statusCode == 204 || response.statusCode == 200) {
        _cargarDatos();
      } else {
        throw Exception(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No se pudo borrar: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Ingresos"),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: "Mes anterior",
            onPressed: () => _irAMes(-1),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _irAMes(0),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Text(
                _esMesCompleto ? _mesAnioTexto : _periodoTexto,
                style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textStrong),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: "Mes siguiente",
            onPressed: () => _irAMes(1),
          ),
          IconButton(
            icon: const Icon(Icons.date_range, size: 20),
            tooltip: "Elegir un rango de fechas personalizado",
            onPressed: _elegirRangoFechas,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _cargarDatos),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: AppColors.surfaceSubtle,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Subtotal del periodo", style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text(formatearColones(_totalSubtotal), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("IVA del periodo", style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text(formatearColones(_totalIva), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
                        tooltip: "Exportar PDF",
                        onPressed: _ingresos.isEmpty
                            ? null
                            : () => ExportService.exportIngresosToPdf(_ingresos, widget.negocio.nombreComercial, _periodoTexto),
                      ),
                      IconButton(
                        icon: const Icon(Icons.table_chart, color: Colors.green),
                        tooltip: "Exportar Excel",
                        onPressed: _ingresos.isEmpty ? null : () => ExportService.exportIngresosToExcel(_ingresos),
                      ),
                    ],
                  ),
                ),
                if (_sumaPorTarifa.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    color: AppColors.surfaceSubtle,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Desglose por tarifa", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                        const SizedBox(height: 6),
                        Table(
                          columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(2), 2: FlexColumnWidth(2), 3: FlexColumnWidth(2)},
                          children: [
                            TableRow(children: [
                              Text("Tarifa", style: TextStyle(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.bold)),
                              Text("Subtotal", textAlign: TextAlign.right, style: TextStyle(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.bold)),
                              Text("IVA", textAlign: TextAlign.right, style: TextStyle(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.bold)),
                              Text("Total", textAlign: TextAlign.right, style: TextStyle(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.bold)),
                            ]),
                            ..._sumaPorTarifa.map((e) {
                              final subtotal = e.value[0];
                              final iva = e.value[1];
                              return TableRow(children: [
                                Padding(padding: const EdgeInsets.only(top: 4), child: Text("${e.key}%", style: const TextStyle(fontSize: 12))),
                                Padding(padding: const EdgeInsets.only(top: 4), child: Text(formatearColones(subtotal, decimales: 0), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
                                Padding(padding: const EdgeInsets.only(top: 4), child: Text(formatearColones(iva, decimales: 0), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
                                Padding(padding: const EdgeInsets.only(top: 4), child: Text(formatearColones(subtotal + iva, decimales: 0), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                              ]);
                            }),
                          ],
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: _ingresos.isEmpty
                      ? const Center(child: Text("No hay ingresos registrados en este periodo.", style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _ingresos.length,
                          itemBuilder: (context, i) {
                            final ing = _ingresos[i];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFFEEF2FF),
                                  child: Icon(Icons.trending_up, color: AppColors.primary, size: 20),
                                ),
                                title: Text(
                                  ing.clienteNombre.isNotEmpty ? ing.clienteNombre : "Cliente sin especificar",
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                  [
                                    ing.fecha,
                                    if (ing.referencia.isNotEmpty) ing.referencia,
                                    ing.condicionVenta == '02' ? 'Crédito' : 'Contado',
                                    if (ing.moneda == 'USD')
                                      "US\$${(ing.total / ing.tipoCambio).toStringAsFixed(2)} @ ₡${ing.tipoCambio.toStringAsFixed(2)}",
                                  ].join(" · "),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(formatearColones(ing.total), style: const TextStyle(fontWeight: FontWeight.bold)),
                                    PopupMenuButton<String>(
                                      onSelected: (opcion) {
                                        if (opcion == 'editar') _mostrarFormulario(ingresoExistente: ing);
                                        if (opcion == 'comprobante' && ing.comprobanteUrl != null) _abrirComprobante(ing.comprobanteUrl!);
                                        if (opcion == 'borrar') _eliminarIngreso(ing);
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(value: 'editar', child: Text("Editar")),
                                        if (ing.comprobanteUrl != null && ing.comprobanteUrl!.isNotEmpty)
                                          const PopupMenuItem(value: 'comprobante', child: Text("Ver comprobante")),
                                        const PopupMenuItem(value: 'borrar', child: Text("Borrar")),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'importar-ingresos',
            onPressed: () => importarArchivoExterno(
              context: context,
              negocio: widget.negocio,
              endpoint: '/ingresos-operativos/importar-externo/',
              tipoLabel: 'ventas',
              onImportado: _cargarDatos,
            ),
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text("Importar archivo"),
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.textStrong,
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'nuevo-ingreso',
            onPressed: () => _mostrarFormulario(),
            icon: const Icon(Icons.add),
            label: const Text("Nuevo Ingreso"),
            backgroundColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}
