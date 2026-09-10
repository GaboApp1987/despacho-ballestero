import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'api_service.dart';
import 'factura.dart';
import 'nota_credito.dart';
import 'compra_model.dart';
import 'gasto_operativo.dart';
import 'formato.dart';
import 'negocio.dart';

class ExportService {
  static pw.ThemeData? _temaCache;

  /// Guarda un archivo Excel ya armado, pidiéndole al usuario dónde. En Web
  /// no existe un sistema de archivos real: hay que pasarle los bytes
  /// directo a saveFile() para que dispare la descarga del navegador. En
  /// escritorio, saveFile() solo devuelve la ruta elegida y hay que escribir
  /// el archivo aparte.
  static Future<void> _guardarExcel(Excel excel, {required String dialogTitle, required String fileName}) async {
    final bytes = excel.encode()!;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      bytes: Uint8List.fromList(bytes),
    );
    if (!kIsWeb && path != null) {
      await File(path).writeAsBytes(bytes);
    }
  }

  /// Fuente con soporte para el símbolo de colón (₡, U+20A1): las fuentes
  /// por defecto del paquete pdf (Helvetica) no lo tienen y lo dejan en blanco.
  static Future<pw.ThemeData> _cargarTema() async {
    if (_temaCache != null) return _temaCache!;
    final regular = await rootBundle.load('assets/fonts/arial.ttf');
    final bold = await rootBundle.load('assets/fonts/arialbd.ttf');
    _temaCache = pw.ThemeData.withFont(
      base: pw.Font.ttf(regular),
      bold: pw.Font.ttf(bold),
    );
    return _temaCache!;
  }

  /// Descarga el logo (si hay URL) para insertarlo en un PDF. Si falla o no
  /// hay logo, devuelve null y el PDF simplemente no lo muestra.
  static Future<pw.MemoryImage?> _cargarLogo(String? logoUrl) async {
    if (logoUrl == null || logoUrl.isEmpty) return null;
    try {
      final response = await http.get(Uri.parse(logoUrl));
      if (response.statusCode == 200) {
        return pw.MemoryImage(response.bodyBytes);
      }
    } catch (_) {
      // Sin logo, el PDF se genera igual.
    }
    return null;
  }

  /// Pie de página formal con los datos de identificación del negocio,
  /// para el cierre de facturas y notas de crédito.
  static pw.Widget _piePagina(NegocioInfo? info, PdfColor colorAccent) {
    if (info == null) return pw.SizedBox();

    final contacto = [
      if (info.telefono != null && info.telefono!.isNotEmpty) 'Tel: ${info.telefono}',
      if (info.correo != null && info.correo!.isNotEmpty) info.correo!,
    ].join('   ·   ');

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 30),
        pw.Divider(color: colorAccent, thickness: 1),
        pw.SizedBox(height: 8),
        pw.Text(info.nombreComercial, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
        pw.SizedBox(height: 2),
        pw.Text(info.cedulaEtiquetada, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        if (info.direccion != null && info.direccion!.isNotEmpty)
          pw.Text(info.direccion!, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        if (contacto.isNotEmpty)
          pw.Text(contacto, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        pw.SizedBox(height: 10),
        pw.Text(
          'Documento generado electrónicamente. No requiere firma manuscrita.',
          style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500, fontStyle: pw.FontStyle.italic),
        ),
      ],
    );
  }

  /// Exporta el listado de facturas a PDF
  static Future<void> exportFacturasToPdf(List<Factura> facturas, String negocioNombre, String periodo) async {
    final pdf = pw.Document(theme: await _cargarTema());
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context context) => [
        pw.Header(
          level: 0,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Reporte de Facturación', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Periodo: $periodo', style: const pw.TextStyle(fontSize: 12)),
                ],
              ),
              pw.Text(negocioNombre, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headers: const ['Fecha', 'Doc #', 'Cliente', 'Condición', 'Monto'],
          data: facturas.map((f) => [
            f.fechaEmision.split('T')[0],
            'F-${f.consecutivo}',
            f.receptorNombre,
            f.condicionVenta == "02" ? 'Crédito' : 'Contado',
            formatearColones(f.totalFactura),
          ]).toList(),
        ),
        pw.SizedBox(height: 20),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Total Facturado: ${formatearColones(facturas.fold<double>(0.0, (sum, f) => sum + f.totalFactura))}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
          ),
        ),
      ],
    ));
    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Facturacion.pdf');
  }

  /// Exporta el listado de facturas a Excel
  static Future<void> exportFacturasToExcel(List<Factura> facturas) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Facturas'];

    sheetObject.appendRow([
      TextCellValue('Fecha'),
      TextCellValue('Consecutivo'),
      TextCellValue('Cliente'),
      TextCellValue('Cédula'),
      TextCellValue('Condición'),
      TextCellValue('IVA'),
      TextCellValue('Total'),
    ]);

    for (var f in facturas) {
      sheetObject.appendRow([
        TextCellValue(f.fechaEmision.split('T')[0]),
        TextCellValue(f.consecutivo),
        TextCellValue(f.receptorNombre),
        TextCellValue(f.receptorCedula ?? ''),
        TextCellValue(f.condicionVenta == "02" ? 'Crédito' : 'Contado'),
        DoubleCellValue(f.totalIva),
        DoubleCellValue(f.totalFactura),
      ]);
    }

    await _guardarExcel(excel, dialogTitle: 'Guardar Reporte de Facturación', fileName: 'reporte_facturacion.xlsx');
  }

  /// Exporta el reporte consolidado (GET /reportes/consolidado/, ver
  /// ReporteConsolidadoView) a PDF -- ventas, notas de crédito, compras,
  /// notas de débito y el resumen para la declaración de IVA, según lo que
  /// venga en la respuesta.
  static Future<void> exportReporteConsolidadoToPdf(Map<String, dynamic> reporte, String periodo) async {
    final negocioNombre = reporte['negocio_nombre']?.toString() ?? '';
    final ventas = reporte['ventas'] as Map<String, dynamic>?;
    final compras = reporte['compras'] as Map<String, dynamic>?;
    final resumen = reporte['resumen_declaracion'] as Map<String, dynamic>?;

    pw.Widget tablaDesglose(List desglose) => pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headers: const ['Tarifa', 'Base Imponible', 'Monto de Impuesto'],
          data: desglose.map((d) => [
            d['tarifa']?.toString() ?? '',
            formatearColones(double.tryParse(d['base_imponible'].toString()) ?? 0),
            formatearColones(double.tryParse(d['monto_impuesto'].toString()) ?? 0),
          ]).toList(),
        );

    final widgets = <pw.Widget>[
      pw.Header(
        level: 0,
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Reporte de Ventas y Compras', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                pw.Text('Periodo: $periodo', style: const pw.TextStyle(fontSize: 12)),
              ],
            ),
            pw.Text(negocioNombre, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ),
      pw.SizedBox(height: 16),
    ];

    if (resumen != null) {
      final ventasPorTarifa = (resumen['ventas_por_tarifa'] as List?) ?? [];
      final comprasPorTarifa = (resumen['compras_por_tarifa'] as List?) ?? [];
      widgets.addAll([
        pw.Text('Resumen para la declaración de IVA (D-104)', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('Ventas y compras gravadas por tarifa, netas de notas de crédito.', style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 8),
        pw.Text('Ventas gravadas', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        ventasPorTarifa.isEmpty ? pw.Text('Sin ventas gravadas.', style: const pw.TextStyle(fontSize: 11)) : tablaDesglose(ventasPorTarifa),
        pw.SizedBox(height: 8),
        pw.Text('Compras gravadas', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        comprasPorTarifa.isEmpty ? pw.Text('Sin compras gravadas.', style: const pw.TextStyle(fontSize: 11)) : tablaDesglose(comprasPorTarifa),
        pw.SizedBox(height: 10),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'IVA a pagar (ventas - crédito fiscal de compras): ${formatearColones(double.tryParse(resumen['iva_a_pagar'].toString()) ?? 0)}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
          ),
        ),
        pw.SizedBox(height: 20),
        pw.Divider(),
        pw.SizedBox(height: 8),
      ]);
    }

    if (ventas != null) {
      final documentos = (ventas['documentos'] as List?) ?? [];
      widgets.addAll([
        pw.Text('Ventas', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headers: const ['Fecha', 'Documento', 'Tipo', 'Cliente', 'Base', 'IVA', 'Total'],
          data: documentos.map((f) => [
            (f['fecha']?.toString() ?? '').split('T').first,
            f['consecutivo']?.toString() ?? '',
            f['tipo_documento']?.toString() ?? '',
            f['cliente']?.toString() ?? '',
            formatearColones(double.tryParse(f['subtotal'].toString()) ?? 0),
            formatearColones(double.tryParse(f['monto_iva'].toString()) ?? 0),
            formatearColones(double.tryParse(f['total'].toString()) ?? 0),
          ]).toList(),
        ),
        pw.SizedBox(height: 8),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Total Ventas: ${formatearColones(double.tryParse(ventas['total'].toString()) ?? 0)}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
          ),
        ),
        pw.SizedBox(height: 12),
      ]);
      final notasCredito = (ventas['notas_credito'] as List?) ?? [];
      if (notasCredito.isNotEmpty) {
        widgets.addAll([
          pw.Text('Notas de Crédito', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headers: const ['Fecha', 'N.°', 'Anula Factura', 'Motivo', 'Base', 'IVA', 'Total'],
            data: notasCredito.map((n) => [
              (n['fecha']?.toString() ?? '').split('T').first,
              n['consecutivo']?.toString() ?? '',
              n['factura_anulada']?.toString() ?? '',
              n['motivo']?.toString() ?? '',
              formatearColones(double.tryParse(n['subtotal'].toString()) ?? 0),
              formatearColones(double.tryParse(n['monto_iva'].toString()) ?? 0),
              formatearColones(double.tryParse(n['total'].toString()) ?? 0),
            ]).toList(),
          ),
          pw.SizedBox(height: 8),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Total Ventas Neto: ${formatearColones(double.tryParse(ventas['total_neto'].toString()) ?? 0)}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
            ),
          ),
          pw.SizedBox(height: 12),
        ]);
      }
      final desglose = (ventas['desglose_impuestos'] as List?) ?? [];
      if (desglose.isNotEmpty) {
        widgets.addAll([
          pw.Text('Desglose de IVA por tarifa (neto de notas de crédito)', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          tablaDesglose(desglose),
          pw.SizedBox(height: 16),
        ]);
      }
    }

    if (compras != null) {
      final documentos = (compras['documentos'] as List?) ?? [];
      widgets.addAll([
        pw.Text('Compras', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headers: const ['Fecha', 'Proveedor', 'N.° Factura Proveedor', 'Base (est.)', 'IVA (est.)', 'Total'],
          data: documentos.map((c) => [
            (c['fecha']?.toString() ?? '').split('T').first,
            c['proveedor']?.toString() ?? '',
            c['numero_factura_proveedor']?.toString() ?? '',
            formatearColones(double.tryParse(c['subtotal_estimado'].toString()) ?? 0),
            formatearColones(double.tryParse(c['monto_iva_estimado'].toString()) ?? 0),
            formatearColones(double.tryParse(c['total'].toString()) ?? 0),
          ]).toList(),
        ),
        pw.SizedBox(height: 8),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Total Compras: ${formatearColones(double.tryParse(compras['total'].toString()) ?? 0)}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
          ),
        ),
        pw.SizedBox(height: 12),
      ]);
      final notasDebito = (compras['notas_debito'] as List?) ?? [];
      if (notasDebito.isNotEmpty) {
        widgets.addAll([
          pw.Text('Notas de Débito', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headers: const ['Fecha', 'N.°', 'Proveedor', 'Motivo', 'Monto'],
            data: notasDebito.map((n) => [
              (n['fecha']?.toString() ?? '').split('T').first,
              n['numero_documento']?.toString() ?? '',
              n['proveedor']?.toString() ?? '',
              n['motivo']?.toString() ?? '',
              formatearColones(double.tryParse(n['monto'].toString()) ?? 0),
            ]).toList(),
          ),
          pw.SizedBox(height: 8),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Total Compras Neto: ${formatearColones(double.tryParse(compras['total_neto'].toString()) ?? 0)}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
            ),
          ),
          pw.SizedBox(height: 12),
        ]);
      }
      final desglose = (compras['desglose_impuestos'] as List?) ?? [];
      if (desglose.isNotEmpty) {
        widgets.addAll([
          pw.Text('Desglose de IVA por tarifa (estimado)', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          tablaDesglose(desglose),
          pw.SizedBox(height: 6),
          pw.Text(
            compras['nota_desglose']?.toString() ?? '',
            style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic),
          ),
        ]);
      }
    }

    final pdf = pw.Document(theme: await _cargarTema());
    pdf.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, build: (context) => widgets));
    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Reporte_$negocioNombre.pdf');
  }

  /// Exporta el reporte consolidado a Excel -- una hoja por sección que
  /// exista en la respuesta (Resumen Declaración/Ventas/Notas de
  /// Crédito/Compras/Notas de Débito).
  static Future<void> exportReporteConsolidadoToExcel(Map<String, dynamic> reporte) async {
    var excel = Excel.createExcel();
    final ventas = reporte['ventas'] as Map<String, dynamic>?;
    final compras = reporte['compras'] as Map<String, dynamic>?;
    final resumen = reporte['resumen_declaracion'] as Map<String, dynamic>?;

    void escribirDesglose(Sheet hoja, List desglose) {
      hoja.appendRow([TextCellValue('Tarifa'), TextCellValue('Base Imponible'), TextCellValue('Monto de Impuesto')]);
      for (var d in desglose) {
        hoja.appendRow([
          TextCellValue(d['tarifa']?.toString() ?? ''),
          DoubleCellValue(double.tryParse(d['base_imponible'].toString()) ?? 0),
          DoubleCellValue(double.tryParse(d['monto_impuesto'].toString()) ?? 0),
        ]);
      }
    }

    if (resumen != null) {
      final hoja = excel['Resumen Declaracion'];
      hoja.appendRow([TextCellValue('Ventas gravadas')]);
      escribirDesglose(hoja, (resumen['ventas_por_tarifa'] as List?) ?? []);
      hoja.appendRow([TextCellValue('')]);
      hoja.appendRow([TextCellValue('Compras gravadas')]);
      escribirDesglose(hoja, (resumen['compras_por_tarifa'] as List?) ?? []);
      hoja.appendRow([TextCellValue('')]);
      hoja.appendRow([
        TextCellValue('IVA a pagar (ventas - crédito fiscal de compras)'),
        DoubleCellValue(double.tryParse(resumen['iva_a_pagar'].toString()) ?? 0),
      ]);
    }

    if (ventas != null) {
      final hojaVentas = excel['Ventas'];
      hojaVentas.appendRow([
        TextCellValue('Fecha'), TextCellValue('Documento'), TextCellValue('Tipo'), TextCellValue('Cliente'),
        TextCellValue('Base'), TextCellValue('IVA'), TextCellValue('Total'),
      ]);
      for (var f in (ventas['documentos'] as List? ?? [])) {
        hojaVentas.appendRow([
          TextCellValue((f['fecha']?.toString() ?? '').split('T').first),
          TextCellValue(f['consecutivo']?.toString() ?? ''),
          TextCellValue(f['tipo_documento']?.toString() ?? ''),
          TextCellValue(f['cliente']?.toString() ?? ''),
          DoubleCellValue(double.tryParse(f['subtotal'].toString()) ?? 0),
          DoubleCellValue(double.tryParse(f['monto_iva'].toString()) ?? 0),
          DoubleCellValue(double.tryParse(f['total'].toString()) ?? 0),
        ]);
      }

      final notasCredito = (ventas['notas_credito'] as List?) ?? [];
      if (notasCredito.isNotEmpty) {
        final hojaNC = excel['Notas de Credito'];
        hojaNC.appendRow([
          TextCellValue('Fecha'), TextCellValue('N.°'), TextCellValue('Anula Factura'), TextCellValue('Motivo'),
          TextCellValue('Base'), TextCellValue('IVA'), TextCellValue('Total'),
        ]);
        for (var n in notasCredito) {
          hojaNC.appendRow([
            TextCellValue((n['fecha']?.toString() ?? '').split('T').first),
            TextCellValue(n['consecutivo']?.toString() ?? ''),
            TextCellValue(n['factura_anulada']?.toString() ?? ''),
            TextCellValue(n['motivo']?.toString() ?? ''),
            DoubleCellValue(double.tryParse(n['subtotal'].toString()) ?? 0),
            DoubleCellValue(double.tryParse(n['monto_iva'].toString()) ?? 0),
            DoubleCellValue(double.tryParse(n['total'].toString()) ?? 0),
          ]);
        }
      }

      final desglose = (ventas['desglose_impuestos'] as List?) ?? [];
      if (desglose.isNotEmpty) {
        escribirDesglose(excel['Desglose IVA Ventas'], desglose);
      }
    }

    if (compras != null) {
      final hojaCompras = excel['Compras'];
      hojaCompras.appendRow([
        TextCellValue('Fecha'), TextCellValue('Proveedor'), TextCellValue('N.° Factura Proveedor'),
        TextCellValue('Base (est.)'), TextCellValue('IVA (est.)'), TextCellValue('Total'),
      ]);
      for (var c in (compras['documentos'] as List? ?? [])) {
        hojaCompras.appendRow([
          TextCellValue((c['fecha']?.toString() ?? '').split('T').first),
          TextCellValue(c['proveedor']?.toString() ?? ''),
          TextCellValue(c['numero_factura_proveedor']?.toString() ?? ''),
          DoubleCellValue(double.tryParse(c['subtotal_estimado'].toString()) ?? 0),
          DoubleCellValue(double.tryParse(c['monto_iva_estimado'].toString()) ?? 0),
          DoubleCellValue(double.tryParse(c['total'].toString()) ?? 0),
        ]);
      }

      final notasDebito = (compras['notas_debito'] as List?) ?? [];
      if (notasDebito.isNotEmpty) {
        final hojaND = excel['Notas de Debito'];
        hojaND.appendRow([
          TextCellValue('Fecha'), TextCellValue('N.°'), TextCellValue('Proveedor'), TextCellValue('Motivo'), TextCellValue('Monto'),
        ]);
        for (var n in notasDebito) {
          hojaND.appendRow([
            TextCellValue((n['fecha']?.toString() ?? '').split('T').first),
            TextCellValue(n['numero_documento']?.toString() ?? ''),
            TextCellValue(n['proveedor']?.toString() ?? ''),
            TextCellValue(n['motivo']?.toString() ?? ''),
            DoubleCellValue(double.tryParse(n['monto'].toString()) ?? 0),
          ]);
        }
      }

      final desglose = (compras['desglose_impuestos'] as List?) ?? [];
      if (desglose.isNotEmpty) {
        escribirDesglose(excel['Desglose IVA Compras'], desglose);
      }
    }

    // NO se borra la hoja "Sheet1" que trae Excel.createExcel() por defecto:
    // el propio código del paquete excel (save_file.dart) advierte que
    // borrar/renombrar la hoja default es una operación insegura ("Maybe
    // overkill and unsafe... another safer method preferred"), y en la
    // práctica hacía que excel.encode() fallara silenciosamente y la
    // exportación no generara ningún archivo. Queda como una pestaña extra
    // vacía en el archivo, sin romper nada.
    final negocioNombre = reporte['negocio_nombre']?.toString() ?? 'reporte';
    await _guardarExcel(
      excel,
      dialogTitle: 'Guardar Reporte de Ventas y Compras',
      fileName: 'reporte_${negocioNombre.replaceAll(' ', '_')}.xlsx',
    );
  }

  /// Exporta el listado general de Cuentas por Cobrar a PDF
  static Future<void> exportSaldosToPdf(List<Map<String, dynamic>> saldos, String negocioNombre) async {
    final pdf = pw.Document(theme: await _cargarTema());
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context context) => [
        pw.Header(
          level: 0,
          child: pw.Text('Reporte de Cuentas por Cobrar - $negocioNombre', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headers: const ['Cliente', 'Cédula', 'Saldo Pendiente'],
          data: saldos.map((item) => [
            item['nombre'],
            item['cedula'],
            formatearColones(double.parse(item['saldo'].toString())),
          ]).toList(),
        ),
        pw.SizedBox(height: 20),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Total por Cobrar: ${formatearColones(saldos.fold<double>(0.0, (sum, item) => sum + double.parse(item['saldo'].toString())))}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
          ),
        ),
      ],
    ));
    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Saldos_CxC.pdf');
  }

  /// Exporta el listado general de Cuentas por Cobrar a Excel
  static Future<void> exportSaldosToExcel(List<Map<String, dynamic>> saldos) async {
    var excel = Excel.createExcel();
    Sheet sheet = excel['Saldos'];
    sheet.appendRow([
      TextCellValue('Cliente'),
      TextCellValue('Cédula'),
      TextCellValue('Saldo Pendiente'),
    ]);
    for (var item in saldos) {
      sheet.appendRow([
        TextCellValue(item['nombre'].toString()),
        TextCellValue(item['cedula'].toString()),
        DoubleCellValue(double.parse(item['saldo'].toString())),
      ]);
    }
    await _guardarExcel(excel, dialogTitle: 'Guardar Reporte de Saldos', fileName: 'reporte_saldos.xlsx');
  }

  /// Exporta el historial individual de un cliente a PDF
  static Future<void> exportHistorialToPdf(String clienteNombre, List<dynamic> historial, String negocioNombre) async {
    final pdf = pw.Document(theme: await _cargarTema());
    double totalFacturado = 0;
    double totalAbonado = 0;

    for (var item in historial) {
      double monto = double.parse(item['monto'].toString());
      if (item['tipo'] == 'FACTURA') {
        totalFacturado += monto;
      } else {
        totalAbonado += monto;
      }
    }

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context context) => [
        pw.Text('Estado de Cuenta: $clienteNombre', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.Text('Negocio: $negocioNombre'),
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headers: const ['Fecha', 'Tipo', 'Detalle', 'Monto'],
          data: historial.map((item) => [
            item['fecha'],
            item['tipo'],
            item['tipo'] == 'FACTURA' ? 'F-${item['numero']}' : 'Recibo de Abono',
            '${item['tipo'] == 'FACTURA' ? '+' : '-'} ${formatearColones(double.parse(item['monto'].toString()))}',
          ]).toList(),
        ),
        pw.SizedBox(height: 20),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Total Facturado: ${formatearColones(totalFacturado)}'),
              pw.Text('Total Abonado: ${formatearColones(totalAbonado)}'),
              pw.SizedBox(width: 150, child: pw.Divider()),
              pw.Text('Saldo Pendiente: ${formatearColones(totalFacturado - totalAbonado)}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, color: PdfColors.red)),
            ],
          ),
        ),
      ],
    ));
    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Estado_Cuenta_$clienteNombre.pdf');
  }

  /// Exporta el historial individual de un cliente a Excel
  static Future<void> exportHistorialToExcel(String clienteNombre, List<dynamic> historial) async {
    var excel = Excel.createExcel();
    Sheet sheet = excel['Historial'];
    sheet.appendRow([
      TextCellValue('Fecha'),
      TextCellValue('Tipo'),
      TextCellValue('Detalle'),
      TextCellValue('Monto'),
    ]);
    for (var item in historial) {
      final bool esFactura = item['tipo'] == 'FACTURA';
      sheet.appendRow([
        TextCellValue(item['fecha'].toString()),
        TextCellValue(item['tipo'].toString()),
        TextCellValue(esFactura ? 'F-${item['numero']}' : 'Abono'),
        DoubleCellValue(double.parse(item['monto'].toString()) * (esFactura ? 1 : -1))
      ]);
    }
    await _guardarExcel(excel, dialogTitle: 'Guardar Historial de $clienteNombre', fileName: 'historial_${clienteNombre.replaceAll(' ', '_')}.xlsx');
  }

  /// Exporta (o comparte) una factura individual con su detalle de productos
  static Future<void> exportFacturaDetalleToPdf(Factura factura, {bool share = false, List<NotaCredito> notasCredito = const []}) async {
    final pdf = pw.Document(theme: await _cargarTema());
    final subtotal = factura.totalFactura - factura.totalIva;
    final logo = await _cargarLogo(factura.logoNegocioUrl);
    final subtotalAcreditado = notasCredito.fold(0.0, (s, n) => s + n.subtotal);
    final ivaAcreditado = notasCredito.fold(0.0, (s, n) => s + n.montoIva);
    final totalAcreditado = subtotalAcreditado + ivaAcreditado;

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context context) => [
        pw.Header(
          level: 0,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    factura.esInterno
                        ? 'TIQUETE INTERNO (NO FISCAL)'
                        : (factura.esTiquete ? 'TIQUETE ELECTRÓNICO' : 'FACTURA ELECTRÓNICA'),
                    style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text('Factura Número: F-${factura.consecutivo}'),
                  pw.Text('Fecha: ${factura.fechaEmision.split('T')[0]}'),
                  pw.Text('Condición: ${factura.condicionVenta == "02" ? 'Crédito' : 'Contado'}'),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  if (logo != null) pw.Image(logo, width: 60, height: 60, fit: pw.BoxFit.contain),
                  if (logo != null) pw.SizedBox(height: 6),
                  pw.Text(factura.nombreNegocio, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 20),
        pw.Text('RECEPTOR', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.indigo)),
        pw.Text(factura.receptorNombre),
        if (factura.receptorCedula != null && factura.receptorCedula!.isNotEmpty)
          pw.Text('Cédula: ${factura.receptorCedula}'),
        if (factura.receptorCorreo != null && factura.receptorCorreo!.isNotEmpty)
          pw.Text('Correo: ${factura.receptorCorreo}'),
        if (factura.clave != null && factura.clave!.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Text('Clave Numérica:', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.Text(factura.clave!, style: const pw.TextStyle(fontSize: 8)),
        ],
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo),
          headers: const ['Producto', 'Cant', 'Precio Unit.', 'IVA', 'Total'],
          data: factura.detalles.isEmpty
              ? [
                  ['Sin detalle de líneas registrado.', '', '', '', ''],
                ]
              : factura.detalles.map((d) => [
                    d.nombreProducto,
                    d.cantidad.toString(),
                    formatearColones(d.precioUnitario),
                    formatearColones(d.montoIva),
                    formatearColones(d.total),
                  ]).toList(),
        ),
        pw.SizedBox(height: 20),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Subtotal: ${formatearColones(subtotal)}'),
              pw.Text('IVA: ${formatearColones(factura.totalIva)}'),
              pw.SizedBox(width: 180, child: pw.Divider()),
              pw.Text(
                notasCredito.isEmpty ? 'TOTAL: ${formatearColones(factura.totalFactura)}' : 'Total Factura Original: ${formatearColones(factura.totalFactura)}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16, color: PdfColors.indigo),
              ),
            ],
          ),
        ),
        if (notasCredito.isNotEmpty) ...[
          pw.SizedBox(height: 20),
          pw.Text('NOTAS DE CRÉDITO APLICADAS', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
          pw.SizedBox(height: 8),
          ...notasCredito.map((n) => pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 10),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.orange200), borderRadius: pw.BorderRadius.circular(6)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      color: PdfColors.orange50,
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('NOTA DE CRÉDITO NC-${n.consecutivo}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.orange900)),
                          pw.Text(n.fechaEmision.split('T')[0], style: const pw.TextStyle(fontSize: 9, color: PdfColors.orange900)),
                        ],
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(10),
                      child: pw.TableHelper.fromTextArray(
                        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
                        headerDecoration: const pw.BoxDecoration(color: PdfColors.orange900),
                        cellStyle: const pw.TextStyle(fontSize: 9),
                        headers: const ['Producto', 'Cant', 'Precio Unit.', 'IVA', 'Total'],
                        data: n.detalles.map((d) => [
                              d.nombreProducto,
                              d.cantidad.toString(),
                              formatearColones(d.precioUnitario),
                              formatearColones(d.montoIva),
                              formatearColones(d.total),
                            ]).toList(),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.fromLTRB(10, 0, 10, 10),
                      child: pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text('Subtotal: -${formatearColones(n.subtotal)}', style: const pw.TextStyle(color: PdfColors.red900, fontSize: 10)),
                            pw.Text('IVA: -${formatearColones(n.montoIva)}', style: const pw.TextStyle(color: PdfColors.red900, fontSize: 10)),
                            pw.Text('Total NC: -${formatearColones(n.total)}', style: pw.TextStyle(color: PdfColors.red900, fontSize: 12, fontWeight: pw.FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              )),
          pw.SizedBox(height: 12),
          pw.Text('FACTURA NETA DESPUÉS DE NC', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.indigo)),
          pw.SizedBox(height: 8),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Subtotal neto: ${formatearColones(subtotal - subtotalAcreditado)}'),
                pw.Text('IVA neto: ${formatearColones(factura.totalIva - ivaAcreditado)}'),
                pw.SizedBox(width: 180, child: pw.Divider()),
                pw.Text(
                  'TOTAL NETO: ${formatearColones(factura.totalFactura - totalAcreditado)}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16, color: PdfColors.indigo),
                ),
              ],
            ),
          ),
        ],
        _piePagina(factura.negocioInfo, PdfColors.indigo),
      ],
    ));

    final pdfBytes = await pdf.save();
    final fileName = 'Factura_${factura.consecutivo}.pdf';

    if (share) {
      // XFile.fromData comparte directo desde memoria: funciona igual en
      // escritorio y en Web (donde no existe un sistema de archivos real
      // para escribir un temporal primero).
      await Share.shareXFiles(
        [XFile.fromData(pdfBytes, name: fileName, mimeType: 'application/pdf')],
        text: 'Le comparto la factura F-${factura.consecutivo}.',
      );
    } else {
      await Printing.layoutPdf(onLayout: (format) async => pdfBytes, name: fileName);
    }
  }

  /// Genera y comparte una cotización por WA/Correo
  static Future<void> exportCotizacionToPdf(Map<String, dynamic> cotizacion, String negocioNombre, {bool share = false}) async {
    final pdf = pw.Document(theme: await _cargarTema());
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context context) => [
        pw.Header(
          level: 0,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('PROFORMA / COTIZACIÓN', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.orange)),
                  pw.Text('Número: COT-${cotizacion['consecutivo_cotizacion'].toString().padLeft(5, '0')}'),
                  pw.Text('Fecha: ${cotizacion['fecha_emision'].toString().split('T')[0]}'),
                ],
              ),
              pw.Text(negocioNombre, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
        pw.SizedBox(height: 20),
        pw.Text('CLIENTE:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Text(cotizacion['cliente_nombre'] ?? 'Cliente General'),
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.orange),
          headers: const ['Producto', 'Cant', 'Precio Unit.', 'IVA', 'Total'],
          data: ((cotizacion['detalles'] as List?) ?? []).map((item) {
            final precioUnitario = double.tryParse(item['precio_unitario'].toString()) ?? 0.0;
            final montoIva = double.tryParse((item['monto_iva'] ?? 0).toString()) ?? 0.0;
            final subtotal = double.tryParse((item['subtotal'] ?? (precioUnitario * (item['cantidad'] ?? 1))).toString()) ?? 0.0;
            return [
              item['nombre_producto'] ?? 'Producto',
              item['cantidad'].toString(),
              formatearColones(precioUnitario),
              formatearColones(montoIva),
              formatearColones(subtotal + montoIva),
            ];
          }).toList(),
        ),
        pw.SizedBox(height: 20),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('TOTAL: ${formatearColones(double.parse(cotizacion['total'].toString()))}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18, color: PdfColors.orange)),
        ),
        pw.SizedBox(height: 50),
        pw.Center(child: pw.Text('Gracias por su preferencia. Esta cotización tiene una validez de 15 días.')),
      ],
    ));

    final pdfBytes = await pdf.save();
    final fileName = 'Cotizacion_${cotizacion['consecutivo_cotizacion']}.pdf';

    if (share) {
      await Share.shareXFiles(
        [XFile.fromData(pdfBytes, name: fileName, mimeType: 'application/pdf')],
        text: 'Comparto mi cotización con usted.',
      );
    } else {
      await Printing.layoutPdf(onLayout: (format) async => pdfBytes, name: fileName);
    }
  }

  /// Exporta un resumen detallado del dashboard con listados y gráficos
  static Future<void> exportResumenDashboardPdf({
    required String negocioNombre,
    required String periodo,
    required List<Factura> facturas,
    required List<dynamic> topProductos,
    required List<dynamic> saldosCxC,
  }) async {
    final pdf = pw.Document(theme: await _cargarTema());

    Map<String, double> ventasPorCliente = {};
    for (var f in facturas) {
      ventasPorCliente.update(f.receptorNombre, (val) => val + f.totalFactura, ifAbsent: () => f.totalFactura);
    }
    var listaVentasCliente = ventasPorCliente.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Resumen Ejecutivo Comercial', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                pw.Text(negocioNombre),
              ],
            ),
          ),
          pw.Text('Periodo: $periodo', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
          pw.SizedBox(height: 20),

          // SECCIÓN 1: CLIENTES CON FACTURAS VENDIDAS
          pw.Text('Ventas por Cliente en el Periodo', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo)),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headers: const ['Cliente', 'Monto Facturado'],
            data: listaVentasCliente.map((e) => [e.key, formatearColones(e.value)]).toList(),
          ),
          pw.SizedBox(height: 30),

          // SECCIÓN 2: CLIENTES CON MAYOR DEUDA (CxC)
          pw.Text('Cuentas por Cobrar (Top Pendientes)', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.red)),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headers: const ['Cliente', 'Saldo Pendiente'],
            data: saldosCxC.take(10).map((e) => [e['nombre'], formatearColones(double.parse(e['saldo'].toString()))]).toList(),
          ),
        ],
      ),
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          final top5 = topProductos.take(5).toList();
          final menosVendidos = topProductos.reversed.take(5).toList();

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Análisis de Productos', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.teal)),
              pw.SizedBox(height: 20),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 2,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Top Productos Vendidos', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 5),
                        pw.TableHelper.fromTextArray(
                          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          headers: const ['Producto', 'Unidades'],
                          data: top5.map((e) => [e['producto__nombre'], e['total_vendido'].toString()]).toList(),
                        ),
                        pw.SizedBox(height: 15),
                        pw.Text('Menos Vendidos', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 5),
                        pw.TableHelper.fromTextArray(
                          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          headers: const ['Producto', 'Unidades'],
                          data: menosVendidos.map((e) => [e['producto__nombre'], e['total_vendido'].toString()]).toList(),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 20),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Column(
                      children: [
                        pw.Text('Distribución Top 5', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 10),
                        pw.SizedBox(
                          height: 150,
                          child: pw.Chart(
                            grid: pw.PieGrid(),
                            datasets: top5.asMap().entries.map<pw.Dataset>((entry) {
                              final int index = entry.key;
                              final item = entry.value;
                              final double val = double.tryParse(item['total_vendido'].toString()) ?? 0.0;
                              const colores = [
                                PdfColors.blue,
                                PdfColors.red,
                                PdfColors.green,
                                PdfColors.orange,
                                PdfColors.purple,
                              ];
                              return pw.PieDataSet(
                                value: val,
                                legend: item['producto__nombre'],
                                color: colores[index % colores.length],
                                drawBorder: true,
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 40),
              pw.Text('Resumen Final del Reporte', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.Divider(),
              pw.Text('Total de Facturas emitidas en el periodo: ${facturas.length}'),
              pw.Text('Monto Global por Cobrar a la fecha: ${formatearColones(saldosCxC.fold<double>(0.0, (sum, e) => sum + double.parse(e['saldo'].toString())))}'),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Resumen_Dashboard.pdf');
  }

  /// Exporta el borrador de la Declaración de IVA del periodo (débito de
  /// ventas vs. crédito de compras) como PDF, listo para llevar al contador
  /// o de referencia antes de presentarlo en el D-104 de Hacienda.
  static Future<void> exportDeclaracionIvaPdf({
    required String negocioNombre,
    required String negocioCedula,
    required String periodo,
    required Map<String, dynamic> declaracion,
  }) async {
    final pdf = pw.Document(theme: await _cargarTema());

    double numDe(String llave) => double.tryParse(declaracion[llave]?.toString() ?? '') ?? 0.0;
    final ventasGravadas = numDe('ventas_gravadas');
    final debitoFiscal = numDe('debito_fiscal');
    final comprasTotales = numDe('compras_totales');
    final creditoFiscal = numDe('credito_fiscal');
    final saldoIva = numDe('saldo_iva');
    final aPagar = declaracion['a_pagar'] == true;
    final lineasSinImpuesto = (declaracion['lineas_compra_sin_impuesto'] as num?)?.toInt() ?? 0;
    final cantFacturas = (declaracion['cantidad_facturas'] as num?)?.toInt() ?? 0;
    final cantNotas = (declaracion['cantidad_notas_credito'] as num?)?.toInt() ?? 0;
    final cantCompras = (declaracion['cantidad_compras'] as num?)?.toInt() ?? 0;
    final sinSaldo = saldoIva.abs() < 0.01;
    final etiquetaSaldo = sinSaldo ? 'Sin saldo de IVA en el periodo' : (aPagar ? 'IVA a pagar' : 'IVA a favor (saldo acumulable)');
    final colorSaldo = sinSaldo ? PdfColors.grey800 : (aPagar ? PdfColors.red800 : PdfColors.green800);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Declaración de IVA (Borrador)', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.teal800)),
                      pw.Text(negocioNombre),
                      pw.Text('Cédula: $negocioCedula', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Text('Periodo: $periodo', style: const pw.TextStyle(fontSize: 11)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo),
              cellAlignment: pw.Alignment.centerLeft,
              columnWidths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(2)},
              headers: const ['Concepto', 'Monto'],
              data: [
                ['Ventas gravadas (débito)', formatearColones(ventasGravadas)],
                ['IVA de ventas (débito fiscal)', formatearColones(debitoFiscal)],
                ['Compras netas (crédito)', formatearColones(comprasTotales)],
                ['IVA de compras estimado (crédito fiscal)', formatearColones(creditoFiscal)],
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: colorSaldo), borderRadius: pw.BorderRadius.circular(8)),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(etiquetaSaldo, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: colorSaldo)),
                  pw.Text(formatearColones(saldoIva.abs()), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16, color: colorSaldo)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              '$cantFacturas factura(s) · $cantNotas nota(s) de crédito · $cantCompras compra(s) consideradas en el periodo.',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            if (lineasSinImpuesto > 0) ...[
              pw.SizedBox(height: 6),
              pw.Text(
                'Nota: $lineasSinImpuesto línea(s) de compra son de productos sin impuesto asignado y no se incluyeron en el crédito fiscal.',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.orange800),
              ),
            ],
            pw.SizedBox(height: 6),
            pw.Text(
              'El crédito fiscal de compras se estima con la tarifa de impuesto asignada a cada producto (no se registra un IVA propio por línea de compra). Verifique los montos antes de presentar la declaración ante Hacienda.',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey500, fontStyle: pw.FontStyle.italic),
            ),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Declaracion_IVA.pdf');
  }

  static const Map<String, String> _categoriasGastoPdf = {
    'planilla': 'Planilla y CCSS',
    'alquiler': 'Alquiler',
    'servicios': 'Servicios públicos',
    'honorarios': 'Honorarios profesionales',
    'mantenimiento': 'Mantenimiento y reparaciones',
    'publicidad': 'Publicidad y mercadeo',
    'transporte': 'Transporte y viáticos',
    'seguros': 'Seguros',
    'depreciacion': 'Depreciación de activos',
    'financieros': 'Gastos financieros e intereses',
    'impuestos_municipales': 'Impuestos y patentes municipales',
    'otros': 'Otros gastos',
  };

  /// Exporta el borrador de la Declaración de Renta (D-101) del periodo
  /// fiscal (año calendario) como PDF, listo para llevar al contador o de
  /// referencia antes de presentarlo ante Hacienda.
  static Future<void> exportDeclaracionRentaPdf({
    required String negocioNombre,
    required String negocioCedula,
    required Map<String, dynamic> declaracion,
  }) async {
    final pdf = pw.Document(theme: await _cargarTema());

    double numDe(String llave) => double.tryParse(declaracion[llave]?.toString() ?? '') ?? 0.0;
    final periodoFiscal = declaracion['periodo_fiscal']?.toString() ?? '';
    final tipoContribuyente = declaracion['tipo_contribuyente'] == 'juridica'
        ? 'Persona Jurídica'
        : 'Persona Física con Actividad Lucrativa';
    final ingresosBrutos = numDe('ingresos_brutos');
    final costoVentas = numDe('costo_ventas');
    final gastosDeducibles = numDe('gastos_deducibles');
    final gastosNoDeducibles = numDe('gastos_no_deducibles');
    final rentaLiquida = numDe('renta_liquida_gravable');
    final impuestoEstimado = numDe('impuesto_estimado');
    final tarifaUnica = declaracion['tarifa_unica_aplicada'] as String?;
    final configurado = declaracion['parametros_configurados'] == true;
    final gastosPorCategoria = (declaracion['gastos_por_categoria'] as List?) ?? [];
    final desgloseTramos = (declaracion['desglose_tramos'] as List?) ?? [];

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Declaración de Renta (Borrador)', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.deepPurple800)),
                      pw.Text(negocioNombre),
                      pw.Text('Cédula: $negocioCedula', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Periodo fiscal $periodoFiscal', style: const pw.TextStyle(fontSize: 11)),
                      pw.Text(tipoContribuyente, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            if (!configurado)
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(10),
                margin: const pw.EdgeInsets.only(bottom: 14),
                decoration: pw.BoxDecoration(color: PdfColors.red50, borderRadius: pw.BorderRadius.circular(6)),
                child: pw.Text(
                  'No hay tramos de Renta configurados para este periodo fiscal: el impuesto estimado no se pudo calcular.',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.red800),
                ),
              ),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.deepPurple),
              cellAlignment: pw.Alignment.centerLeft,
              columnWidths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(2)},
              headers: const ['Concepto', 'Monto'],
              data: [
                ['Ingresos brutos (ventas)', formatearColones(ingresosBrutos)],
                ['Costo de ventas (compras)', formatearColones(costoVentas)],
                ['Gastos deducibles', formatearColones(gastosDeducibles)],
                if (gastosNoDeducibles > 0) ['Gastos no deducibles', formatearColones(gastosNoDeducibles)],
                ['Renta líquida gravable', formatearColones(rentaLiquida)],
                ['Impuesto estimado', formatearColones(impuestoEstimado)],
              ],
            ),
            if (tarifaUnica != null) ...[
              pw.SizedBox(height: 8),
              pw.Text('Tarifa única aplicada: $tarifaUnica% (ingresos brutos superan el límite de tramos progresivos)',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            ],
            if (gastosPorCategoria.isNotEmpty) ...[
              pw.SizedBox(height: 20),
              pw.Text('Gastos deducibles por categoría', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headers: const ['Categoría', 'Monto'],
                data: gastosPorCategoria.map((g) {
                  final cat = _categoriasGastoPdf[g['categoria']] ?? g['categoria'].toString();
                  final total = double.tryParse(g['total'].toString()) ?? 0.0;
                  return [cat, formatearColones(total)];
                }).toList(),
              ),
            ],
            if (desgloseTramos.isNotEmpty) ...[
              pw.SizedBox(height: 20),
              pw.Text('Desglose por tramo', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headers: const ['Rango', 'Tarifa', 'Impuesto'],
                data: desgloseTramos.map((t) {
                  final desde = double.tryParse(t['desde'].toString()) ?? 0.0;
                  final hastaStr = t['hasta'];
                  final hasta = hastaStr != null ? double.tryParse(hastaStr.toString()) : null;
                  final impuestoTramo = double.tryParse(t['impuesto_tramo'].toString()) ?? 0.0;
                  final rango = hasta != null
                      ? '${formatearColones(desde, decimales: 0)} - ${formatearColones(hasta, decimales: 0)}'
                      : 'Más de ${formatearColones(desde, decimales: 0)}';
                  return [rango, '${t['porcentaje']}%', formatearColones(impuestoTramo)];
                }).toList(),
              ),
            ],
            pw.SizedBox(height: 20),
            pw.Text(
              'Cálculo de referencia: el costo de ventas se aproxima con las compras del año (no se costea inventario por unidad vendida) y no incluye depreciación fiscal detallada, pérdidas de periodos anteriores ni créditos personales (cónyuge/hijos). Verifíquelo con su contador antes de presentar el D-101 ante Hacienda.',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey500, fontStyle: pw.FontStyle.italic),
            ),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Declaracion_Renta_$periodoFiscal.pdf');
  }

  static const Map<String, String> _estadoHaciendaLabel = {
    '1': 'Sin Enviar',
    '2': 'Enviando',
    '3': 'Aceptado',
    '4': 'Rechazado',
    '5': 'Error Técnico',
    '6': 'Interno (No Fiscal)',
  };


  /// Exporta la Declaración de IVA con el detalle factura por factura, nota
  /// de crédito por nota de crédito y compra por compra del periodo — lista
  /// para llevar al contador o presentar como respaldo del D-104.
  static Future<void> exportDeclaracionIvaDetalladaPdf({
    required String negocioNombre,
    required String negocioCedula,
    required String periodo,
    required Map<String, dynamic> declaracion,
    required List<Factura> facturas,
    required List<NotaCredito> notasCredito,
    required List<Compra> compras,
  }) async {
    final pdf = pw.Document(theme: await _cargarTema());

    double numDe(String llave) => double.tryParse(declaracion[llave]?.toString() ?? '') ?? 0.0;
    final debitoPorTarifa = (declaracion['debito_por_tarifa'] as List?) ?? [];
    final creditoPorTarifa = (declaracion['credito_por_tarifa'] as List?) ?? [];

    pw.Widget encabezado(String titulo) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 24, bottom: 8),
          child: pw.Text(titulo, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo)),
        );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => context.pageNumber == 1
            ? pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Declaración de IVA — Detalle', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.teal800)),
                          pw.Text(negocioNombre),
                          pw.Text('Cédula: $negocioCedula', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                        ],
                      ),
                      pw.Text('Periodo: $periodo', style: const pw.TextStyle(fontSize: 11)),
                    ],
                  ),
                  pw.Divider(),
                ],
              )
            : pw.Container(),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Página ${context.pageNumber} de ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
        ),
        build: (pw.Context context) => [
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo),
            headers: const ['Concepto', 'Monto'],
            data: [
              ['Ventas gravadas', formatearColones(numDe('ventas_gravadas'))],
              ['IVA de ventas (débito fiscal)', formatearColones(numDe('debito_fiscal'))],
              ['Compras netas', formatearColones(numDe('compras_totales'))],
              ['IVA de compras estimado (crédito fiscal)', formatearColones(numDe('credito_fiscal'))],
              ['Saldo del periodo', formatearColones(numDe('saldo_iva'))],
            ],
          ),
          if (debitoPorTarifa.isNotEmpty) ...[
            encabezado('Débito fiscal por tarifa (ventas)'),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headers: const ['Tarifa', 'Base', 'IVA'],
              data: debitoPorTarifa.map((t) => [
                '${t['tarifa']}%',
                formatearColones(double.tryParse(t['base'].toString()) ?? 0),
                formatearColones(double.tryParse(t['iva'].toString()) ?? 0),
              ]).toList(),
            ),
          ],
          if (creditoPorTarifa.isNotEmpty) ...[
            encabezado('Crédito fiscal por tarifa (compras)'),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headers: const ['Tarifa', 'Base', 'IVA'],
              data: creditoPorTarifa.map((t) => [
                '${t['tarifa']}%',
                formatearColones(double.tryParse(t['base'].toString()) ?? 0),
                formatearColones(double.tryParse(t['iva'].toString()) ?? 0),
              ]).toList(),
            ),
          ],
          encabezado('Facturas del periodo (${facturas.length})'),
          facturas.isEmpty
              ? pw.Text('Sin facturas en el periodo.', style: const pw.TextStyle(color: PdfColors.grey600))
              : pw.TableHelper.fromTextArray(
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                  cellStyle: const pw.TextStyle(fontSize: 9),
                  headers: const ['Consecutivo', 'Fecha', 'Cliente', 'Cédula', 'Condición', 'Subtotal', 'IVA', 'Total', 'Estado'],
                  data: [
                    ...facturas.map((f) => [
                          'F-${f.consecutivo}',
                          f.fechaEmision.split('T').first,
                          f.receptorNombre,
                          f.receptorCedula ?? '',
                          f.condicionVenta == '02' ? 'Crédito' : 'Contado',
                          formatearColones(f.totalFactura - f.totalIva),
                          formatearColones(f.totalIva),
                          formatearColones(f.totalFactura),
                          _estadoHaciendaLabel[f.estadoHacienda] ?? f.estadoHacienda,
                        ]),
                    [
                      'TOTAL', '', '', '', '',
                      formatearColones(facturas.fold(0.0, (s, f) => s + (f.totalFactura - f.totalIva))),
                      formatearColones(facturas.fold(0.0, (s, f) => s + f.totalIva)),
                      formatearColones(facturas.fold(0.0, (s, f) => s + f.totalFactura)),
                      '',
                    ],
                  ],
                ),
          if (notasCredito.isNotEmpty) ...[
            encabezado('Notas de crédito del periodo (${notasCredito.length})'),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headers: const ['Consecutivo', 'Fecha', 'Anula Factura', 'Cliente', 'Subtotal', 'IVA', 'Total'],
              data: notasCredito.map((n) => [
                n.consecutivo,
                n.fechaEmision.split('T').first,
                'F-${n.facturaConsecutivo ?? ''}',
                n.receptorNombre,
                formatearColones(n.subtotal),
                formatearColones(n.montoIva),
                formatearColones(n.total),
              ]).toList(),
            ),
          ],
          encabezado('Compras del periodo (${compras.length})'),
          compras.isEmpty
              ? pw.Text('Sin compras en el periodo.', style: const pw.TextStyle(color: PdfColors.grey600))
              : pw.TableHelper.fromTextArray(
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                  cellStyle: const pw.TextStyle(fontSize: 9),
                  headers: const ['Proveedor', 'Fecha', 'N° Factura Prov.', 'Total'],
                  data: compras.map((c) => [
                    c.nombreProveedor ?? 'Sin especificar',
                    c.fechaCompra.split('T').first,
                    c.numeroFacturaProveedor,
                    formatearColones(c.totalCompra),
                  ]).toList(),
                ),
          pw.SizedBox(height: 16),
          pw.Text(
            'El crédito fiscal de compras se estima con la tarifa de impuesto asignada a cada producto (no se registra un IVA propio por línea de compra). Verifique los montos antes de presentar la declaración ante Hacienda.',
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500, fontStyle: pw.FontStyle.italic),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Declaracion_IVA_Detalle.pdf');
  }

  /// Exporta la Declaración de IVA detallada a Excel: una hoja de resumen y
  /// una hoja por cada libro (facturas, notas de crédito, compras).
  static Future<void> exportDeclaracionIvaDetalladaExcel({
    required String negocioNombre,
    required String periodo,
    required Map<String, dynamic> declaracion,
    required List<Factura> facturas,
    required List<NotaCredito> notasCredito,
    required List<Compra> compras,
  }) async {
    double numDe(String llave) => double.tryParse(declaracion[llave]?.toString() ?? '') ?? 0.0;
    var excel = Excel.createExcel();

    final resumen = excel['Resumen'];
    excel.setDefaultSheet('Resumen');
    resumen.appendRow([TextCellValue('Declaración de IVA - $negocioNombre')]);
    resumen.appendRow([TextCellValue('Periodo: $periodo')]);
    resumen.appendRow([]);
    resumen.appendRow([TextCellValue('Concepto'), TextCellValue('Monto')]);
    resumen.appendRow([TextCellValue('Ventas gravadas'), DoubleCellValue(numDe('ventas_gravadas'))]);
    resumen.appendRow([TextCellValue('IVA de ventas (débito fiscal)'), DoubleCellValue(numDe('debito_fiscal'))]);
    resumen.appendRow([TextCellValue('Compras netas'), DoubleCellValue(numDe('compras_totales'))]);
    resumen.appendRow([TextCellValue('IVA de compras estimado (crédito fiscal)'), DoubleCellValue(numDe('credito_fiscal'))]);
    resumen.appendRow([TextCellValue('Saldo del periodo'), DoubleCellValue(numDe('saldo_iva'))]);
    resumen.appendRow([]);
    resumen.appendRow([TextCellValue('Débito fiscal por tarifa')]);
    resumen.appendRow([TextCellValue('Tarifa'), TextCellValue('Base'), TextCellValue('IVA')]);
    for (final t in ((declaracion['debito_por_tarifa'] as List?) ?? [])) {
      resumen.appendRow([
        TextCellValue('${t['tarifa']}%'),
        DoubleCellValue(double.tryParse(t['base'].toString()) ?? 0),
        DoubleCellValue(double.tryParse(t['iva'].toString()) ?? 0),
      ]);
    }
    resumen.appendRow([]);
    resumen.appendRow([TextCellValue('Crédito fiscal por tarifa')]);
    resumen.appendRow([TextCellValue('Tarifa'), TextCellValue('Base'), TextCellValue('IVA')]);
    for (final t in ((declaracion['credito_por_tarifa'] as List?) ?? [])) {
      resumen.appendRow([
        TextCellValue('${t['tarifa']}%'),
        DoubleCellValue(double.tryParse(t['base'].toString()) ?? 0),
        DoubleCellValue(double.tryParse(t['iva'].toString()) ?? 0),
      ]);
    }

    final hojaFacturas = excel['Facturas'];
    hojaFacturas.appendRow([
      TextCellValue('Consecutivo'), TextCellValue('Fecha'), TextCellValue('Cliente'), TextCellValue('Cédula'),
      TextCellValue('Condición'), TextCellValue('Subtotal'), TextCellValue('IVA'), TextCellValue('Total'), TextCellValue('Estado'),
    ]);
    for (final f in facturas) {
      hojaFacturas.appendRow([
        TextCellValue('F-${f.consecutivo}'),
        TextCellValue(f.fechaEmision.split('T').first),
        TextCellValue(f.receptorNombre),
        TextCellValue(f.receptorCedula ?? ''),
        TextCellValue(f.condicionVenta == '02' ? 'Crédito' : 'Contado'),
        DoubleCellValue(f.totalFactura - f.totalIva),
        DoubleCellValue(f.totalIva),
        DoubleCellValue(f.totalFactura),
        TextCellValue(_estadoHaciendaLabel[f.estadoHacienda] ?? f.estadoHacienda),
      ]);
    }
    hojaFacturas.appendRow([]);
    hojaFacturas.appendRow([
      TextCellValue('TOTAL'), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''),
      DoubleCellValue(facturas.fold(0.0, (s, f) => s + (f.totalFactura - f.totalIva))),
      DoubleCellValue(facturas.fold(0.0, (s, f) => s + f.totalIva)),
      DoubleCellValue(facturas.fold(0.0, (s, f) => s + f.totalFactura)),
      TextCellValue(''),
    ]);

    final hojaNotas = excel['Notas de Credito'];
    hojaNotas.appendRow([
      TextCellValue('Consecutivo'), TextCellValue('Fecha'), TextCellValue('Anula Factura'),
      TextCellValue('Cliente'), TextCellValue('Subtotal'), TextCellValue('IVA'), TextCellValue('Total'),
    ]);
    for (final n in notasCredito) {
      hojaNotas.appendRow([
        TextCellValue(n.consecutivo),
        TextCellValue(n.fechaEmision.split('T').first),
        TextCellValue('F-${n.facturaConsecutivo ?? ''}'),
        TextCellValue(n.receptorNombre),
        DoubleCellValue(n.subtotal),
        DoubleCellValue(n.montoIva),
        DoubleCellValue(n.total),
      ]);
    }

    final hojaCompras = excel['Compras'];
    hojaCompras.appendRow([TextCellValue('Proveedor'), TextCellValue('Fecha'), TextCellValue('N° Factura Proveedor'), TextCellValue('Total')]);
    for (final c in compras) {
      hojaCompras.appendRow([
        TextCellValue(c.nombreProveedor ?? 'Sin especificar'),
        TextCellValue(c.fechaCompra.split('T').first),
        TextCellValue(c.numeroFacturaProveedor),
        DoubleCellValue(c.totalCompra),
      ]);
    }
    hojaCompras.appendRow([]);
    hojaCompras.appendRow([TextCellValue('TOTAL'), TextCellValue(''), TextCellValue(''), DoubleCellValue(compras.fold(0.0, (s, c) => s + c.totalCompra))]);

    excel.delete('Sheet1');

    await _guardarExcel(excel, dialogTitle: 'Guardar Declaración de IVA (Excel)', fileName: 'Declaracion_IVA_Detalle.xlsx');
  }

  /// Exporta la Declaración de Renta con el detalle factura por factura,
  /// compra por compra y gasto por gasto del periodo fiscal — lista para
  /// llevar al contador o presentar como respaldo del D-101.
  static Future<void> exportDeclaracionRentaDetalladaPdf({
    required String negocioNombre,
    required String negocioCedula,
    required Map<String, dynamic> declaracion,
    required List<Factura> facturas,
    required List<Compra> compras,
    required List<GastoOperativo> gastos,
  }) async {
    final pdf = pw.Document(theme: await _cargarTema());

    double numDe(String llave) => double.tryParse(declaracion[llave]?.toString() ?? '') ?? 0.0;
    final periodoFiscal = declaracion['periodo_fiscal']?.toString() ?? '';
    final tipoContribuyente = declaracion['tipo_contribuyente'] == 'juridica'
        ? 'Persona Jurídica'
        : 'Persona Física con Actividad Lucrativa';
    final tarifaUnica = declaracion['tarifa_unica_aplicada'] as String?;
    final desgloseTramos = (declaracion['desglose_tramos'] as List?) ?? [];

    pw.Widget encabezado(String titulo) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 24, bottom: 8),
          child: pw.Text(titulo, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo)),
        );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => context.pageNumber == 1
            ? pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Declaración de Renta — Detalle', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.deepPurple800)),
                          pw.Text(negocioNombre),
                          pw.Text('Cédula: $negocioCedula', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('Periodo fiscal $periodoFiscal', style: const pw.TextStyle(fontSize: 11)),
                          pw.Text(tipoContribuyente, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                        ],
                      ),
                    ],
                  ),
                  pw.Divider(),
                ],
              )
            : pw.Container(),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Página ${context.pageNumber} de ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
        ),
        build: (pw.Context context) => [
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.deepPurple),
            headers: const ['Concepto', 'Monto'],
            data: [
              ['Ingresos brutos (ventas)', formatearColones(numDe('ingresos_brutos'))],
              ['Costo de ventas (compras)', formatearColones(numDe('costo_ventas'))],
              ['Gastos deducibles', formatearColones(numDe('gastos_deducibles'))],
              if (numDe('gastos_no_deducibles') > 0) ['Gastos no deducibles', formatearColones(numDe('gastos_no_deducibles'))],
              ['Renta líquida gravable', formatearColones(numDe('renta_liquida_gravable'))],
              ['Impuesto estimado', formatearColones(numDe('impuesto_estimado'))],
            ],
          ),
          if (tarifaUnica != null) ...[
            pw.SizedBox(height: 8),
            pw.Text('Tarifa única aplicada: $tarifaUnica% (ingresos brutos superan el límite de tramos progresivos)',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          ],
          if (desgloseTramos.isNotEmpty) ...[
            encabezado('Desglose por tramo'),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headers: const ['Rango', 'Tarifa', 'Impuesto'],
              data: desgloseTramos.map((t) {
                final desde = double.tryParse(t['desde'].toString()) ?? 0.0;
                final hastaStr = t['hasta'];
                final hasta = hastaStr != null ? double.tryParse(hastaStr.toString()) : null;
                final impuestoTramo = double.tryParse(t['impuesto_tramo'].toString()) ?? 0.0;
                final rango = hasta != null
                    ? '${formatearColones(desde, decimales: 0)} - ${formatearColones(hasta, decimales: 0)}'
                    : 'Más de ${formatearColones(desde, decimales: 0)}';
                return [rango, '${t['porcentaje']}%', formatearColones(impuestoTramo)];
              }).toList(),
            ),
          ],
          encabezado('Facturas del periodo fiscal (${facturas.length})'),
          facturas.isEmpty
              ? pw.Text('Sin facturas en el periodo.', style: const pw.TextStyle(color: PdfColors.grey600))
              : pw.TableHelper.fromTextArray(
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                  cellStyle: const pw.TextStyle(fontSize: 9),
                  headers: const ['Consecutivo', 'Fecha', 'Cliente', 'Subtotal', 'IVA', 'Total'],
                  data: facturas.map((f) => [
                    'F-${f.consecutivo}',
                    f.fechaEmision.split('T').first,
                    f.receptorNombre,
                    formatearColones(f.totalFactura - f.totalIva),
                    formatearColones(f.totalIva),
                    formatearColones(f.totalFactura),
                  ]).toList(),
                ),
          encabezado('Compras del periodo fiscal (${compras.length})'),
          compras.isEmpty
              ? pw.Text('Sin compras en el periodo.', style: const pw.TextStyle(color: PdfColors.grey600))
              : pw.TableHelper.fromTextArray(
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                  cellStyle: const pw.TextStyle(fontSize: 9),
                  headers: const ['Proveedor', 'Fecha', 'N° Factura Prov.', 'Total'],
                  data: compras.map((c) => [
                    c.nombreProveedor ?? 'Sin especificar',
                    c.fechaCompra.split('T').first,
                    c.numeroFacturaProveedor,
                    formatearColones(c.totalCompra),
                  ]).toList(),
                ),
          encabezado('Gastos del periodo fiscal (${gastos.length})'),
          gastos.isEmpty
              ? pw.Text('Sin gastos registrados en el periodo.', style: const pw.TextStyle(color: PdfColors.grey600))
              : pw.TableHelper.fromTextArray(
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                  cellStyle: const pw.TextStyle(fontSize: 9),
                  headers: const ['Fecha', 'Categoría', 'Descripción', 'Monto', 'Deducible'],
                  data: gastos.map((g) => [
                    g.fecha,
                    g.categoriaLabel,
                    g.descripcion,
                    formatearColones(g.monto),
                    g.deducible ? 'Sí' : 'No',
                  ]).toList(),
                ),
          pw.SizedBox(height: 16),
          pw.Text(
            'El costo de ventas se aproxima con las compras del periodo (no se costea inventario por unidad vendida) y no incluye depreciación fiscal detallada, pérdidas de periodos anteriores ni créditos personales (cónyuge/hijos). Verifique los montos antes de presentar el D-101 ante Hacienda.',
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500, fontStyle: pw.FontStyle.italic),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Declaracion_Renta_Detalle_$periodoFiscal.pdf');
  }

  /// Exporta la Declaración de Renta detallada a Excel: resumen + una hoja
  /// por cada libro (facturas, compras, gastos).
  static Future<void> exportDeclaracionRentaDetalladaExcel({
    required String negocioNombre,
    required Map<String, dynamic> declaracion,
    required List<Factura> facturas,
    required List<Compra> compras,
    required List<GastoOperativo> gastos,
  }) async {
    double numDe(String llave) => double.tryParse(declaracion[llave]?.toString() ?? '') ?? 0.0;
    final periodoFiscal = declaracion['periodo_fiscal']?.toString() ?? '';
    var excel = Excel.createExcel();

    final resumen = excel['Resumen'];
    excel.setDefaultSheet('Resumen');
    resumen.appendRow([TextCellValue('Declaración de Renta - $negocioNombre')]);
    resumen.appendRow([TextCellValue('Periodo fiscal: $periodoFiscal')]);
    resumen.appendRow([]);
    resumen.appendRow([TextCellValue('Concepto'), TextCellValue('Monto')]);
    resumen.appendRow([TextCellValue('Ingresos brutos (ventas)'), DoubleCellValue(numDe('ingresos_brutos'))]);
    resumen.appendRow([TextCellValue('Costo de ventas (compras)'), DoubleCellValue(numDe('costo_ventas'))]);
    resumen.appendRow([TextCellValue('Gastos deducibles'), DoubleCellValue(numDe('gastos_deducibles'))]);
    resumen.appendRow([TextCellValue('Gastos no deducibles'), DoubleCellValue(numDe('gastos_no_deducibles'))]);
    resumen.appendRow([TextCellValue('Renta líquida gravable'), DoubleCellValue(numDe('renta_liquida_gravable'))]);
    resumen.appendRow([TextCellValue('Impuesto estimado'), DoubleCellValue(numDe('impuesto_estimado'))]);
    resumen.appendRow([]);
    resumen.appendRow([TextCellValue('Desglose por tramo')]);
    resumen.appendRow([TextCellValue('Rango desde'), TextCellValue('Rango hasta'), TextCellValue('Tarifa'), TextCellValue('Impuesto')]);
    for (final t in ((declaracion['desglose_tramos'] as List?) ?? [])) {
      resumen.appendRow([
        DoubleCellValue(double.tryParse(t['desde'].toString()) ?? 0),
        TextCellValue(t['hasta']?.toString() ?? 'Sin límite'),
        TextCellValue('${t['porcentaje']}%'),
        DoubleCellValue(double.tryParse(t['impuesto_tramo'].toString()) ?? 0),
      ]);
    }

    final hojaFacturas = excel['Facturas'];
    hojaFacturas.appendRow([TextCellValue('Consecutivo'), TextCellValue('Fecha'), TextCellValue('Cliente'), TextCellValue('Subtotal'), TextCellValue('IVA'), TextCellValue('Total')]);
    for (final f in facturas) {
      hojaFacturas.appendRow([
        TextCellValue('F-${f.consecutivo}'),
        TextCellValue(f.fechaEmision.split('T').first),
        TextCellValue(f.receptorNombre),
        DoubleCellValue(f.totalFactura - f.totalIva),
        DoubleCellValue(f.totalIva),
        DoubleCellValue(f.totalFactura),
      ]);
    }

    final hojaCompras = excel['Compras'];
    hojaCompras.appendRow([TextCellValue('Proveedor'), TextCellValue('Fecha'), TextCellValue('N° Factura Proveedor'), TextCellValue('Total')]);
    for (final c in compras) {
      hojaCompras.appendRow([
        TextCellValue(c.nombreProveedor ?? 'Sin especificar'),
        TextCellValue(c.fechaCompra.split('T').first),
        TextCellValue(c.numeroFacturaProveedor),
        DoubleCellValue(c.totalCompra),
      ]);
    }

    final hojaGastos = excel['Gastos'];
    hojaGastos.appendRow([TextCellValue('Fecha'), TextCellValue('Categoría'), TextCellValue('Descripción'), TextCellValue('Monto'), TextCellValue('Deducible')]);
    for (final g in gastos) {
      hojaGastos.appendRow([
        TextCellValue(g.fecha),
        TextCellValue(g.categoriaLabel),
        TextCellValue(g.descripcion),
        DoubleCellValue(g.monto),
        TextCellValue(g.deducible ? 'Sí' : 'No'),
      ]);
    }
    hojaGastos.appendRow([]);
    hojaGastos.appendRow([TextCellValue('TOTAL DEDUCIBLE'), TextCellValue(''), TextCellValue(''), DoubleCellValue(gastos.where((g) => g.deducible).fold(0.0, (s, g) => s + g.monto)), TextCellValue('')]);

    excel.delete('Sheet1');

    await _guardarExcel(excel, dialogTitle: 'Guardar Declaración de Renta (Excel)', fileName: 'Declaracion_Renta_Detalle_$periodoFiscal.xlsx');
  }

  /// Exporta (o comparte) una Nota de Crédito con el detalle de lo que anula.
  static Future<void> exportNotaCreditoToPdf(NotaCredito nota, {bool share = false}) async {
    final pdf = pw.Document(theme: await _cargarTema());
    final logo = await _cargarLogo(nota.logoNegocioUrl);

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context context) => [
        pw.Header(
          level: 0,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('NOTA DE CRÉDITO', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.orange900)),
                  pw.Text('Consecutivo: ${nota.consecutivo}'),
                  pw.Text('Anula Factura: F-${nota.facturaConsecutivo ?? ''}'),
                  pw.Text('Fecha: ${nota.fechaEmision.split('T')[0]}'),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  if (logo != null) pw.Image(logo, width: 60, height: 60, fit: pw.BoxFit.contain),
                  if (logo != null) pw.SizedBox(height: 6),
                  pw.Text(nota.nombreNegocio, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 20),
        pw.Text('MOTIVO', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.orange900)),
        pw.Text(nota.motivo),
        pw.SizedBox(height: 12),
        pw.Text('RECEPTOR', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.orange900)),
        pw.Text(nota.receptorNombre),
        if (nota.receptorCedula != null && nota.receptorCedula!.isNotEmpty)
          pw.Text('Cédula: ${nota.receptorCedula}'),
        if (nota.clave != null && nota.clave!.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Text('Clave Numérica:', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.Text(nota.clave!, style: const pw.TextStyle(fontSize: 8)),
        ],
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.orange900),
          headers: const ['Producto', 'Cant', 'Precio Unit.', 'IVA', 'Total'],
          data: nota.detalles.isEmpty
              ? [
                  ['Sin detalle de líneas registrado.', '', '', '', ''],
                ]
              : nota.detalles.map((d) => [
                    d.nombreProducto,
                    d.cantidad.toString(),
                    formatearColones(d.precioUnitario),
                    formatearColones(d.montoIva),
                    formatearColones(d.total),
                  ]).toList(),
        ),
        pw.SizedBox(height: 20),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Subtotal: ${formatearColones(nota.subtotal)}'),
              pw.Text('IVA: ${formatearColones(nota.montoIva)}'),
              pw.SizedBox(width: 180, child: pw.Divider()),
              pw.Text(
                'TOTAL ACREDITADO: ${formatearColones(nota.total)}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16, color: PdfColors.orange900),
              ),
            ],
          ),
        ),
        _piePagina(nota.negocioInfo, PdfColors.orange900),
      ],
    ));

    final pdfBytes = await pdf.save();
    final fileName = 'NotaCredito_${nota.consecutivo}.pdf';

    if (share) {
      await Share.shareXFiles(
        [XFile.fromData(pdfBytes, name: fileName, mimeType: 'application/pdf')],
        text: 'Le comparto la Nota de Crédito ${nota.consecutivo}.',
      );
    } else {
      await Printing.layoutPdf(onLayout: (format) async => pdfBytes, name: fileName);
    }
  }

  /// Comparte los archivos OFICIALES de una nota de credito ya aceptada por
  /// Hacienda (el PDF y XML firmado que devuelve Alanube, mas el XML de
  /// respuesta de Hacienda si ya se guardo) -- a diferencia de
  /// [exportNotaCreditoToPdf], que genera un PDF propio en el momento, estos
  /// son los mismos 3 archivos que ya recibio el cliente por correo. Si
  /// [soloPdf] es true solo se comparte el PDF. Lanza una excepcion con un
  /// mensaje legible si el backend no puede entregarlos (p.ej. la nota
  /// todavia no fue aceptada por Hacienda).
  static Future<void> shareDocumentosOficialesNotaCredito(NotaCredito nota, {required bool soloPdf}) async {
    final response = await ApiService.get('/notas-credito/${nota.id}/documentos/');
    final data = json.decode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'No se pudieron obtener los archivos.');
    }

    final archivos = <XFile>[];
    final pdfB64 = data['pdf'] as String?;
    if (pdfB64 != null) {
      archivos.add(XFile.fromData(base64Decode(pdfB64), name: 'NotaCredito_${nota.consecutivo}.pdf', mimeType: 'application/pdf'));
    }
    if (!soloPdf) {
      final xmlB64 = data['xml'] as String?;
      if (xmlB64 != null) {
        archivos.add(XFile.fromData(base64Decode(xmlB64), name: 'NotaCredito_${nota.consecutivo}.xml', mimeType: 'application/xml'));
      }
      final respuestaB64 = data['respuesta_hacienda'] as String?;
      if (respuestaB64 != null) {
        archivos.add(XFile.fromData(base64Decode(respuestaB64), name: 'NotaCredito_${nota.consecutivo}_respuesta_hacienda.xml', mimeType: 'application/xml'));
      }
    }
    if (archivos.isEmpty) {
      throw Exception('Alanube no devolvió ningún archivo para esta nota de crédito.');
    }
    await Share.shareXFiles(archivos, text: 'Le comparto la Nota de Crédito ${nota.consecutivo}.');
  }

  /// Exporta el listado de compras (Reportes) a PDF
  static Future<void> exportComprasToPdf(List<Compra> compras, String negocioNombre, String periodo) async {
    final pdf = pw.Document(theme: await _cargarTema());
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context context) => [
        pw.Header(
          level: 0,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Reporte de Compras', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Periodo: $periodo', style: const pw.TextStyle(fontSize: 12)),
                ],
              ),
              pw.Text(negocioNombre, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headers: const ['Fecha', 'Proveedor', 'Factura Prov.', 'Total'],
          data: compras.map((c) => [
            c.fechaCompra.split('T')[0],
            c.nombreProveedor ?? 'Sin especificar',
            c.numeroFacturaProveedor,
            formatearColones(c.totalCompra),
          ]).toList(),
        ),
        pw.SizedBox(height: 20),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Total Comprado: ${formatearColones(compras.fold<double>(0.0, (sum, c) => sum + c.totalCompra))}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
          ),
        ),
      ],
    ));
    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Reporte_Compras.pdf');
  }

  /// Exporta el listado de compras (Reportes) a Excel
  static Future<void> exportComprasToExcel(List<Compra> compras) async {
    var excel = Excel.createExcel();
    Sheet sheet = excel['Compras'];
    sheet.appendRow([
      TextCellValue('Fecha'),
      TextCellValue('Proveedor'),
      TextCellValue('Factura Proveedor'),
      TextCellValue('Total'),
    ]);
    for (var c in compras) {
      sheet.appendRow([
        TextCellValue(c.fechaCompra.split('T')[0]),
        TextCellValue(c.nombreProveedor ?? 'Sin especificar'),
        TextCellValue(c.numeroFacturaProveedor),
        DoubleCellValue(c.totalCompra),
      ]);
    }
    await _guardarExcel(excel, dialogTitle: 'Guardar Reporte de Compras', fileName: 'reporte_compras.xlsx');
  }

  /// Exporta el listado de gastos operativos (Reportes) a PDF
  static Future<void> exportGastosToPdf(List<GastoOperativo> gastos, String negocioNombre, String periodo) async {
    final pdf = pw.Document(theme: await _cargarTema());
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context context) => [
        pw.Header(
          level: 0,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Reporte de Gastos Operativos', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Periodo: $periodo', style: const pw.TextStyle(fontSize: 12)),
                ],
              ),
              pw.Text(negocioNombre, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headers: const ['Fecha', 'Categoría', 'Descripción', 'Deducible', 'Monto'],
          data: gastos.map((g) => [
            g.fecha,
            g.categoriaLabel,
            g.descripcion,
            g.deducible ? 'Sí' : 'No',
            formatearColones(g.monto),
          ]).toList(),
        ),
        pw.SizedBox(height: 20),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Total de Gastos: ${formatearColones(gastos.fold<double>(0.0, (sum, g) => sum + g.monto))}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
          ),
        ),
      ],
    ));
    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Reporte_Gastos.pdf');
  }

  /// Exporta el listado de gastos operativos (Reportes) a Excel
  static Future<void> exportGastosToExcel(List<GastoOperativo> gastos) async {
    var excel = Excel.createExcel();
    Sheet sheet = excel['Gastos'];
    sheet.appendRow([
      TextCellValue('Fecha'),
      TextCellValue('Categoría'),
      TextCellValue('Descripción'),
      TextCellValue('Deducible'),
      TextCellValue('Monto'),
    ]);
    for (var g in gastos) {
      sheet.appendRow([
        TextCellValue(g.fecha),
        TextCellValue(g.categoriaLabel),
        TextCellValue(g.descripcion),
        TextCellValue(g.deducible ? 'Sí' : 'No'),
        DoubleCellValue(g.monto),
      ]);
    }
    await _guardarExcel(excel, dialogTitle: 'Guardar Reporte de Gastos', fileName: 'reporte_gastos.xlsx');
  }

  /// Exporta el listado de notas de crédito (Reportes) a PDF
  static Future<void> exportNotasCreditoToPdf(List<NotaCredito> notas, String negocioNombre, String periodo) async {
    final pdf = pw.Document(theme: await _cargarTema());
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context context) => [
        pw.Header(
          level: 0,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Reporte de Notas de Crédito', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Periodo: $periodo', style: const pw.TextStyle(fontSize: 12)),
                ],
              ),
              pw.Text(negocioNombre, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headers: const ['Fecha', 'Consecutivo', 'Anula Factura', 'Cliente', 'Total'],
          data: notas.map((n) => [
            n.fechaEmision.split('T')[0],
            n.consecutivo,
            'F-${n.facturaConsecutivo ?? ''}',
            n.receptorNombre,
            formatearColones(n.total),
          ]).toList(),
        ),
        pw.SizedBox(height: 20),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Total Acreditado: ${formatearColones(notas.fold<double>(0.0, (sum, n) => sum + n.total))}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
          ),
        ),
      ],
    ));
    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Reporte_NotasCredito.pdf');
  }

  /// Exporta el listado de notas de crédito (Reportes) a Excel
  static Future<void> exportNotasCreditoToExcel(List<NotaCredito> notas) async {
    var excel = Excel.createExcel();
    Sheet sheet = excel['NotasCredito'];
    sheet.appendRow([
      TextCellValue('Fecha'),
      TextCellValue('Consecutivo'),
      TextCellValue('Anula Factura'),
      TextCellValue('Cliente'),
      TextCellValue('Total'),
    ]);
    for (var n in notas) {
      sheet.appendRow([
        TextCellValue(n.fechaEmision.split('T')[0]),
        TextCellValue(n.consecutivo),
        TextCellValue('F-${n.facturaConsecutivo ?? ''}'),
        TextCellValue(n.receptorNombre),
        DoubleCellValue(n.total),
      ]);
    }
    await _guardarExcel(excel, dialogTitle: 'Guardar Reporte de Notas de Crédito', fileName: 'reporte_notas_credito.xlsx');
  }
}
