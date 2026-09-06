import 'dart:convert';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

import 'api_service.dart';
import 'compra_model.dart';
import 'declaracion_fiscal_widgets.dart';
import 'detalle_negocio.dart';
import 'export_service.dart';
import 'factura.dart';
import 'gasto_operativo.dart';
import 'negocio.dart';
import 'nota_credito.dart';

/// Lo primero que ve el contador al entrar a un cliente: el resumen fiscal
/// completo (IVA del periodo + Renta del año) antes de meterse a administrar
/// el negocio por dentro (facturas, inventario, etc.).
class ResumenFiscalNegocioScreen extends StatefulWidget {
  final Negocio negocio;
  const ResumenFiscalNegocioScreen({super.key, required this.negocio});

  @override
  State<ResumenFiscalNegocioScreen> createState() => _ResumenFiscalNegocioScreenState();
}

class _ResumenFiscalNegocioScreenState extends State<ResumenFiscalNegocioScreen> {
  late DateTime _fechaInicio;
  late DateTime _fechaFin;
  late int _anioRenta;
  late Future<Map<String, dynamic>> _declaracionIvaFuture;
  late Future<Map<String, dynamic>> _declaracionRentaFuture;
  bool _exportandoIva = false;
  bool _exportandoRenta = false;

  @override
  void initState() {
    super.initState();
    final ahora = DateTime.now();
    _fechaInicio = DateTime(ahora.year, ahora.month, 1);
    _fechaFin = DateTime(ahora.year, ahora.month + 1, 0);
    _anioRenta = ahora.year;
    _declaracionIvaFuture = _obtenerDeclaracionIva();
    _declaracionRentaFuture = _obtenerDeclaracionRenta();
  }

  Future<Map<String, dynamic>> _obtenerDeclaracionIva() async {
    String inicioStr = "${_fechaInicio.year}-${_fechaInicio.month.toString().padLeft(2, '0')}-${_fechaInicio.day.toString().padLeft(2, '0')}";
    String finStr = "${_fechaFin.year}-${_fechaFin.month.toString().padLeft(2, '0')}-${_fechaFin.day.toString().padLeft(2, '0')}";
    final response = await ApiService.get(
      '/facturas/declaracion-iva/?negocio=${widget.negocio.id}&fecha_inicio=$inicioStr&fecha_fin=$finStr',
    );
    if (response.statusCode == 200) {
      return json.decode(utf8.decode(response.bodyBytes));
    }
    return {};
  }

  Future<Map<String, dynamic>> _obtenerDeclaracionRenta() async {
    final response = await ApiService.get(
      '/facturas/declaracion-renta/?negocio=${widget.negocio.id}&periodo_fiscal=$_anioRenta',
    );
    if (response.statusCode == 200) {
      return json.decode(utf8.decode(response.bodyBytes));
    }
    return {};
  }

  Future<void> _cambiarPeriodoIva() async {
    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
      initialDateRange: DateTimeRange(start: _fechaInicio, end: _fechaFin),
    );
    if (rango == null) return;
    setState(() {
      _fechaInicio = rango.start;
      _fechaFin = rango.end;
      _declaracionIvaFuture = _obtenerDeclaracionIva();
    });
  }

  void _cambiarAnioRenta(int nuevoAnio) {
    setState(() {
      _anioRenta = nuevoAnio;
      _declaracionRentaFuture = _obtenerDeclaracionRenta();
    });
  }

  String _fmtFecha(DateTime f) => "${f.year}-${f.month.toString().padLeft(2, '0')}-${f.day.toString().padLeft(2, '0')}";

  Future<List<Factura>> _obtenerFacturasPeriodo(DateTime inicio, DateTime fin) async {
    final response = await ApiService.get(
      '/facturas/?negocio=${widget.negocio.id}&fecha_inicio=${_fmtFecha(inicio)}&fecha_fin=${_fmtFecha(fin)}',
    );
    if (response.statusCode != 200) return [];
    final List data = json.decode(utf8.decode(response.bodyBytes));
    return data.map((j) => Factura.fromJson(j)).toList();
  }

  Future<List<NotaCredito>> _obtenerNotasCreditoPeriodo(DateTime inicio, DateTime fin) async {
    final response = await ApiService.get(
      '/notas-credito/?negocio=${widget.negocio.id}&fecha_inicio=${_fmtFecha(inicio)}&fecha_fin=${_fmtFecha(fin)}',
    );
    if (response.statusCode != 200) return [];
    final List data = json.decode(utf8.decode(response.bodyBytes));
    return data.map((j) => NotaCredito.fromJson(j)).toList();
  }

  Future<List<Compra>> _obtenerComprasPeriodo(DateTime inicio, DateTime fin) async {
    final response = await ApiService.get(
      '/compras/?negocio=${widget.negocio.id}&fecha_inicio=${_fmtFecha(inicio)}&fecha_fin=${_fmtFecha(fin)}',
    );
    if (response.statusCode != 200) return [];
    final List data = json.decode(utf8.decode(response.bodyBytes));
    return data.map((j) => Compra.fromJson(j)).toList();
  }

  Future<List<GastoOperativo>> _obtenerGastosAnio(int anio) async {
    final response = await ApiService.get(
      '/gastos-operativos/?negocio=${widget.negocio.id}&fecha_inicio=$anio-01-01&fecha_fin=$anio-12-31',
    );
    if (response.statusCode != 200) return [];
    final List data = json.decode(utf8.decode(response.bodyBytes));
    return data.map((j) => GastoOperativo.fromJson(j)).toList();
  }

  String get _periodoIvaTexto =>
      "Del ${_fechaInicio.day}/${_fechaInicio.month}/${_fechaInicio.year} al ${_fechaFin.day}/${_fechaFin.month}/${_fechaFin.year}";

  Future<void> _exportarIva({required bool excel}) async {
    if (_exportandoIva) return;
    setState(() => _exportandoIva = true);
    try {
      final resultados = await Future.wait([
        _declaracionIvaFuture,
        _obtenerFacturasPeriodo(_fechaInicio, _fechaFin),
        _obtenerNotasCreditoPeriodo(_fechaInicio, _fechaFin),
        _obtenerComprasPeriodo(_fechaInicio, _fechaFin),
      ]);
      final declaracion = resultados[0] as Map<String, dynamic>;
      final facturas = resultados[1] as List<Factura>;
      final notas = resultados[2] as List<NotaCredito>;
      final compras = resultados[3] as List<Compra>;

      if (declaracion.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No se pudo cargar la declaración de IVA para exportar")),
          );
        }
        return;
      }

      if (excel) {
        await ExportService.exportDeclaracionIvaDetalladaExcel(
          negocioNombre: widget.negocio.nombreComercial,
          periodo: _periodoIvaTexto,
          declaracion: declaracion,
          facturas: facturas,
          notasCredito: notas,
          compras: compras,
        );
      } else {
        await ExportService.exportDeclaracionIvaDetalladaPdf(
          negocioNombre: widget.negocio.nombreComercial,
          negocioCedula: widget.negocio.cedula,
          periodo: _periodoIvaTexto,
          declaracion: declaracion,
          facturas: facturas,
          notasCredito: notas,
          compras: compras,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al exportar: $e")));
      }
    } finally {
      if (mounted) setState(() => _exportandoIva = false);
    }
  }

  Future<void> _exportarRenta({required bool excel}) async {
    if (_exportandoRenta) return;
    setState(() => _exportandoRenta = true);
    try {
      final inicioAnio = DateTime(_anioRenta, 1, 1);
      final finAnio = DateTime(_anioRenta, 12, 31);
      final resultados = await Future.wait([
        _declaracionRentaFuture,
        _obtenerFacturasPeriodo(inicioAnio, finAnio),
        _obtenerComprasPeriodo(inicioAnio, finAnio),
        _obtenerGastosAnio(_anioRenta),
      ]);
      final declaracion = resultados[0] as Map<String, dynamic>;
      final facturas = resultados[1] as List<Factura>;
      final compras = resultados[2] as List<Compra>;
      final gastos = resultados[3] as List<GastoOperativo>;

      if (declaracion.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No se pudo cargar la declaración de Renta para exportar")),
          );
        }
        return;
      }

      if (excel) {
        await ExportService.exportDeclaracionRentaDetalladaExcel(
          negocioNombre: widget.negocio.nombreComercial,
          declaracion: declaracion,
          facturas: facturas,
          compras: compras,
          gastos: gastos,
        );
      } else {
        await ExportService.exportDeclaracionRentaDetalladaPdf(
          negocioNombre: widget.negocio.nombreComercial,
          negocioCedula: widget.negocio.cedula,
          declaracion: declaracion,
          facturas: facturas,
          compras: compras,
          gastos: gastos,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al exportar: $e")));
      }
    } finally {
      if (mounted) setState(() => _exportandoRenta = false);
    }
  }

  void _gestionarClienteInternamente() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => DetalleNegocio(negocio: widget.negocio)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.negocio.nombreComercial),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textStrong,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppColors.primary.withOpacity(0.12),
                    child: Icon(Icons.business_center, color: AppColors.primary, size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.negocio.nombreComercial, style: TextStyle(color: AppColors.textStrong, fontSize: 18, fontWeight: FontWeight.bold)),
                        Text("Cédula: ${widget.negocio.cedula}", style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text("Declaración de IVA (Borrador del Periodo)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textStrong)),
                ),
                if (_exportandoIva)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else ...[
                  IconButton(
                    tooltip: "Exportar a PDF (detallado)",
                    onPressed: () => _exportarIva(excel: false),
                    icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.redAccent),
                  ),
                  IconButton(
                    tooltip: "Exportar a Excel (detallado)",
                    onPressed: () => _exportarIva(excel: true),
                    icon: const Icon(Icons.table_chart_outlined, color: Colors.green),
                  ),
                ],
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _cambiarPeriodoIva,
                  icon: const Icon(Icons.date_range, size: 18),
                  label: Text("${_fechaInicio.day}/${_fechaInicio.month}/${_fechaInicio.year} - ${_fechaFin.day}/${_fechaFin.month}/${_fechaFin.year}"),
                ),
              ],
            ),
            const SizedBox(height: 15),
            FutureBuilder<Map<String, dynamic>>(
              future: _declaracionIvaFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
                final d = snapshot.data ?? {};
                if (d.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: AppColors.surfaceSubtle, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                    child: const Text("No se pudo cargar la declaración de IVA de este periodo", style: TextStyle(color: Colors.grey)),
                  );
                }
                return buildDeclaracionIva(d);
              },
            ),

            const SizedBox(height: 30),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text("Declaración de Renta (Borrador Anual)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textStrong)),
                ),
                if (_exportandoRenta)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else ...[
                  IconButton(
                    tooltip: "Exportar a PDF (detallado)",
                    onPressed: () => _exportarRenta(excel: false),
                    icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.redAccent),
                  ),
                  IconButton(
                    tooltip: "Exportar a Excel (detallado)",
                    onPressed: () => _exportarRenta(excel: true),
                    icon: const Icon(Icons.table_chart_outlined, color: Colors.green),
                  ),
                ],
                const SizedBox(width: 8),
                DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _anioRenta,
                    items: List.generate(5, (i) => DateTime.now().year - i)
                        .map((a) => DropdownMenuItem(value: a, child: Text("Periodo fiscal $a")))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) _cambiarAnioRenta(v);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            FutureBuilder<Map<String, dynamic>>(
              future: _declaracionRentaFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
                final d = snapshot.data ?? {};
                if (d.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: AppColors.surfaceSubtle, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                    child: const Text("No se pudo cargar la declaración de Renta de este periodo", style: TextStyle(color: Colors.grey)),
                  );
                }
                return buildDeclaracionRenta(d);
              },
            ),

            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _gestionarClienteInternamente,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E1B4B),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.settings_suggest_outlined, color: Colors.white),
                label: const Text(
                  "GESTIONAR CLIENTE INTERNAMENTE",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
