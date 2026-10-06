import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'descarga_navegador_stub.dart' if (dart.library.html) 'descarga_navegador_web.dart';
import 'api_service.dart';
import 'factura.dart';
import 'nota_credito.dart';
import 'compra_model.dart';
import 'gasto_operativo.dart';
import 'ingreso_operativo.dart';
import 'formato.dart';
import 'negocio.dart';

/// Montos de un documento (en colones) con la moneda y el tipo de cambio
/// con que se emitió -- ver ExportService._celdasUsd.
typedef _DocUsd = ({String moneda, double tc, double subtotal, double iva, double total});

class ExportService {
  static pw.ThemeData? _temaCache;

  /// Tarifa de IVA de una línea, redondeada al entero más cercano (0, 1, 2,
  /// 4, 13) -- mismo criterio que usa el backend para tarifa_pct
  /// (monto_iva / subtotal * 100), calculado acá porque el listado de
  /// facturas de este reporte no trae el desglose por tarifa ya armado.
  static int _tarifaLinea(DetalleFacturaItem d) => d.subtotal > 0 ? (d.montoIva / d.subtotal * 100).round() : 0;

  /// Tarifa de una factura completa para mostrarla en una sola columna:
  /// el porcentaje si todas sus líneas comparten la misma tarifa, o
  /// "Mixta" si combina varias (ej. productos exentos y gravados juntos).
  static String _tarifaFactura(Factura f) {
    final tarifas = f.detalles.map(_tarifaLinea).toSet();
    if (tarifas.isEmpty) return '-';
    if (tarifas.length > 1) return 'Mixta';
    return '${tarifas.first}%';
  }

  /// Agrupa las líneas de todas las facturas por tarifa de IVA y suma la
  /// base (subtotal) y el IVA de cada una -- mismo desglose que "Detalle
  /// por tarifa de IVA" en la Declaración de IVA, calculado del lado del
  /// cliente a partir de los detalles de cada factura.
  static ({Map<int, double> base, Map<int, double> iva}) _agruparPorTarifa(List<Factura> facturas) {
    final base = <int, double>{};
    final iva = <int, double>{};
    for (final f in facturas) {
      for (final d in f.detalles) {
        final t = _tarifaLinea(d);
        base[t] = (base[t] ?? 0) + d.subtotal;
        iva[t] = (iva[t] ?? 0) + d.montoIva;
      }
    }
    return (base: base, iva: iva);
  }

  // --- Estilos compartidos para que los Excel exportados no se vean "pegados"
  // (sin separación entre encabezado y datos, números sin separador de miles,
  // columnas demasiado angostas) -- mismo color de marca que ya usan los PDF. ---
  static final ExcelColor _colorMarca = ExcelColor.fromHexString('FF3730A3');

  static CellStyle _estiloTitulo() => CellStyle(bold: true, fontSize: 16, fontColorHex: _colorMarca);

  static CellStyle _estiloSubtitulo() => CellStyle(fontColorHex: ExcelColor.fromHexString('FF6B7280'));

  static CellStyle _estiloEncabezadoSeccion() => CellStyle(bold: true, fontSize: 12, fontColorHex: _colorMarca);

  static CellStyle _estiloEncabezadoTabla() => CellStyle(
        bold: true,
        fontColorHex: ExcelColor.white,
        backgroundColorHex: _colorMarca,
        horizontalAlign: HorizontalAlign.Center,
      );

  static CellStyle _estiloMoneda({bool negrita = false}) => CellStyle(
        bold: negrita,
        numberFormat: NumFormat.standard_4, // "#,##0.00"
        horizontalAlign: HorizontalAlign.Right,
      );

  static CellStyle _estiloTotalTexto() => CellStyle(
        bold: true,
        topBorder: Border(borderStyle: BorderStyle.Thin),
      );

  static CellStyle _estiloTotalMoneda() => CellStyle(
        bold: true,
        numberFormat: NumFormat.standard_4,
        horizontalAlign: HorizontalAlign.Right,
        topBorder: Border(borderStyle: BorderStyle.Thin),
      );

  /// Aplica [estilo] a las primeras [columnas] celdas de la última fila
  /// escrita en [sheet] (justo después de un appendRow) -- evita tener que
  /// llevar el índice de fila a mano en cada exportación.
  static void _estilarUltimaFila(Sheet sheet, int columnas, CellStyle estilo) {
    final fila = sheet.maxRows - 1;
    for (var c = 0; c < columnas; c++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: fila)).cellStyle = estilo;
    }
  }

  /// Aplica [estilo] a una sola celda de la última fila escrita.
  static void _estilarCeldaUltimaFila(Sheet sheet, int columna, CellStyle estilo) {
    final fila = sheet.maxRows - 1;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: columna, rowIndex: fila)).cellStyle = estilo;
  }

  static void _anchoColumnas(Sheet sheet, List<double> anchos) {
    for (var i = 0; i < anchos.length; i++) {
      sheet.setColumnWidth(i, anchos[i]);
    }
  }

  static final ExcelColor _fondoFilaAlterna = ExcelColor.fromHexString('FFF5F7FF');

  /// Escribe una tabla con el formato de la casa: título y subtítulo
  /// (opcionales), encabezado con el color de marca, filas alternas
  /// sombreadas, montos con separador de miles, una fila TOTAL con las
  /// columnas de [sumar] y anchos de columna calculados según el contenido
  /// (o [anchos] si se pasan). Se puede llamar varias veces sobre la misma
  /// hoja para poner varias tablas una debajo de otra ([seccion] les pone
  /// un subtítulo).
  // ---- Documentos en dólares --------------------------------------------
  // Facturas, notas, compras e ingresos guardan los montos en colones y,
  // aparte, la moneda y el tipo de cambio con que se emitieron. Si un
  // reporte trae alguno en dólares se agregan columnas con los montos en
  // US$ y el tipo de cambio usado (Excel) o una sección aparte (PDF).
  static const List<String> _encabezadosUsd = ['Moneda', 'Tipo de cambio', 'Subtotal USD', 'IVA USD', 'Total USD'];

  static double _r2(double v) => (v * 100).roundToDouble() / 100;

  static bool _esUsd(_DocUsd d) => d.moneda == 'USD' && d.tc > 0;

  static _DocUsd _usdFactura(Factura f) => (moneda: f.moneda, tc: f.tipoCambio, subtotal: f.totalFactura - f.totalIva, iva: f.totalIva, total: f.totalFactura);
  static _DocUsd _usdNota(NotaCredito n) => (moneda: n.facturaMoneda, tc: n.facturaTipoCambio, subtotal: n.subtotal, iva: n.montoIva, total: n.total);
  static _DocUsd _usdCompra(Compra c) {
    final iva = _ivaEstimadoCompra(c);
    return (moneda: c.moneda, tc: c.tipoCambio, subtotal: c.totalCompra, iva: iva, total: c.totalCompra + iva);
  }

  static _DocUsd _usdIngreso(IngresoOperativo i) => (moneda: i.moneda, tc: i.tipoCambio, subtotal: i.monto, iva: i.montoIva, total: i.total);

  static List<CellValue> _celdasUsd(_DocUsd d) {
    if (!_esUsd(d)) return [TextCellValue('CRC'), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue('')];
    return [
      TextCellValue('USD'),
      DoubleCellValue(d.tc),
      DoubleCellValue(_r2(d.subtotal / d.tc)),
      DoubleCellValue(_r2(d.iva / d.tc)),
      DoubleCellValue(_r2(d.total / d.tc)),
    ];
  }

  static List<CellValue> _totalesUsd(Iterable<_DocUsd> docs) {
    final usd = docs.where(_esUsd);
    return [
      TextCellValue(''),
      TextCellValue(''),
      DoubleCellValue(_r2(usd.fold(0.0, (s, d) => s + d.subtotal / d.tc))),
      DoubleCellValue(_r2(usd.fold(0.0, (s, d) => s + d.iva / d.tc))),
      DoubleCellValue(_r2(usd.fold(0.0, (s, d) => s + d.total / d.tc))),
    ];
  }

  static final NumFormat _formatoDolares = NumFormat.custom(formatCode: '"US\$"#,##0.00');

  static CellStyle _estiloDolares({bool total = false}) => total
      ? CellStyle(
          bold: true,
          numberFormat: _formatoDolares,
          horizontalAlign: HorizontalAlign.Right,
          topBorder: Border(borderStyle: BorderStyle.Thin),
        )
      : CellStyle(numberFormat: _formatoDolares, horizontalAlign: HorizontalAlign.Right);

  /// Formato de las 5 columnas en dólares de la última fila, desde [desde].
  static void _estilarUsdUltimaFila(Sheet hoja, int desde, {bool total = false}) {
    _estilarCeldaUltimaFila(hoja, desde + 1, total ? _estiloTotalMoneda() : _estiloMoneda());
    for (var c = desde + 2; c < desde + 5; c++) {
      _estilarCeldaUltimaFila(hoja, c, _estiloDolares(total: total));
    }
  }

  /// Sección "en dólares" para los PDF: solo si hay algún documento en US$.
  static List<pw.Widget> _seccionDolaresPdf(
    String titulo,
    String etiquetaTercero,
    List<(String, String, String, _DocUsd)> filas, {
    PdfColor color = PdfColors.indigo,
  }) {
    final usd = filas.where((f) => _esUsd(f.$4)).toList();
    if (usd.isEmpty) return [];
    String d(double v) => formatearDolares(_r2(v));
    return [
      pw.SizedBox(height: 22),
      pw.Text('$titulo en dólares', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: color)),
      pw.SizedBox(height: 4),
      pw.Text(
        'Montos originales en dólares y el tipo de cambio usado; en las tablas de arriba van convertidos a colones.',
        style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey600),
      ),
      pw.SizedBox(height: 8),
      pw.TableHelper.fromTextArray(
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9.5),
        headerDecoration: pw.BoxDecoration(color: color),
        cellStyle: const pw.TextStyle(fontSize: 9),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        headerPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        headers: ['Documento', 'Fecha', etiquetaTercero, 'Tipo de cambio', 'Subtotal USD', 'IVA USD', 'Total USD'],
        columnWidths: const {
          0: pw.FlexColumnWidth(1.3),
          1: pw.FlexColumnWidth(1.1),
          2: pw.FlexColumnWidth(2.2),
          3: pw.FlexColumnWidth(1.1),
          4: pw.FlexColumnWidth(1.2),
          5: pw.FlexColumnWidth(1.1),
          6: pw.FlexColumnWidth(1.2),
        },
        cellAlignments: const {
          3: pw.Alignment.centerRight,
          4: pw.Alignment.centerRight,
          5: pw.Alignment.centerRight,
          6: pw.Alignment.centerRight,
        },
        data: [
          for (final f in usd)
            [f.$1, f.$2, f.$3, formatearNumero(f.$4.tc), d(f.$4.subtotal / f.$4.tc), d(f.$4.iva / f.$4.tc), d(f.$4.total / f.$4.tc)],
          [
            'TOTAL', '', '', '',
            d(usd.fold(0.0, (s, f) => s + f.$4.subtotal / f.$4.tc)),
            d(usd.fold(0.0, (s, f) => s + f.$4.iva / f.$4.tc)),
            d(usd.fold(0.0, (s, f) => s + f.$4.total / f.$4.tc)),
          ],
        ],
      ),
    ];
  }

  // ---- Ventas reales ------------------------------------------------------
  // Un comprobante rechazado por Hacienda (4) o con error técnico (5) no es
  // una venta: no entra en los reportes de ventas ni en sus totales. Las
  // notas de crédito válidas se RESTAN (ventas netas).
  static bool _ventaValida(Factura f) => f.estadoHacienda != '4' && f.estadoHacienda != '5';
  static bool _notaValida(NotaCredito n) => n.estadoHacienda != '4' && n.estadoHacienda != '5';

  static void _escribirTabla(
    Sheet hoja, {
    String? titulo,
    String? subtitulo,
    String? seccion,
    required List<String> encabezados,
    required List<List<CellValue>> filas,
    Set<int> moneda = const {},
    Set<int> sumar = const {},
    Set<int> porcentaje = const {},
    Set<int> dolares = const {},
    String etiquetaTotal = 'TOTAL',
    List<double>? anchos,
    String vacio = 'Sin datos en este periodo.',
  }) {
    if (titulo != null) {
      hoja.appendRow([TextCellValue(titulo)]);
      _estilarCeldaUltimaFila(hoja, 0, _estiloTitulo());
      final hoy = DateTime.now();
      hoja.appendRow([TextCellValue([if (subtitulo != null && subtitulo.isNotEmpty) subtitulo, 'Generado el ${hoy.day}/${hoy.month}/${hoy.year} con Equilibra'].join('   ·   '))]);
      _estilarCeldaUltimaFila(hoja, 0, _estiloSubtitulo());
      hoja.appendRow([]);
    }
    if (seccion != null) {
      if (titulo == null && hoja.maxRows > 0) hoja.appendRow([]);
      hoja.appendRow([TextCellValue(seccion)]);
      _estilarCeldaUltimaFila(hoja, 0, _estiloEncabezadoSeccion());
    }
    hoja.appendRow(encabezados.map((e) => TextCellValue(e)).toList());
    _estilarUltimaFila(hoja, encabezados.length, _estiloEncabezadoTabla());

    if (filas.isEmpty) {
      hoja.appendRow([TextCellValue(vacio)]);
      _estilarCeldaUltimaFila(hoja, 0, CellStyle(italic: true, fontColorHex: ExcelColor.fromHexString('FF6B7280')));
    }
    final totales = <int, double>{for (final c in sumar) c: 0};
    for (var i = 0; i < filas.length; i++) {
      final fila = filas[i];
      hoja.appendRow(fila);
      final alterna = i.isOdd;
      for (var c = 0; c < encabezados.length; c++) {
        final esMonto = moneda.contains(c);
        final esPct = porcentaje.contains(c);
        final esUsd = dolares.contains(c);
        _estilarCeldaUltimaFila(
          hoja,
          c,
          CellStyle(
            numberFormat: esUsd ? _formatoDolares : (esMonto ? NumFormat.standard_4 : (esPct ? NumFormat.standard_10 : NumFormat.standard_0)),
            horizontalAlign: (esMonto || esPct || esUsd) ? HorizontalAlign.Right : HorizontalAlign.Left,
            backgroundColorHex: alterna ? _fondoFilaAlterna : ExcelColor.none,
          ),
        );
        if (sumar.contains(c) && c < fila.length) {
          final v = fila[c];
          if (v is DoubleCellValue) totales[c] = totales[c]! + v.value;
          if (v is IntCellValue) totales[c] = totales[c]! + v.value;
        }
      }
    }
    if (sumar.isNotEmpty && filas.isNotEmpty) {
      hoja.appendRow([
        for (var c = 0; c < encabezados.length; c++)
          c == 0 ? TextCellValue(etiquetaTotal) : (sumar.contains(c) ? DoubleCellValue(totales[c]!) : TextCellValue('')),
      ]);
      for (var c = 0; c < encabezados.length; c++) {
        _estilarCeldaUltimaFila(
          hoja,
          c,
          sumar.contains(c) ? (dolares.contains(c) ? _estiloDolares(total: true) : _estiloTotalMoneda()) : _estiloTotalTexto(),
        );
      }
    }

    // Anchos: los que vengan, o según el texto más largo de cada columna.
    final calculados = anchos ??
        [
          for (var c = 0; c < encabezados.length; c++)
            () {
              var largo = encabezados[c].length.toDouble();
              for (final fila in filas.take(300)) {
                if (c >= fila.length) continue;
                final v = fila[c];
                final texto = v is DoubleCellValue ? v.value.toStringAsFixed(2) : v.toString();
                if (texto.length > largo) largo = texto.length.toDouble();
              }
              final minimo = moneda.contains(c) ? 15.0 : 10.0;
              return (largo * 1.1 + 3).clamp(minimo, 50.0);
            }(),
        ];
    // Nunca achicar una columna que otra tabla de la misma hoja ya ensanchó
    // (Sheet.getColumnWidth del paquete falla si la columna no tiene ancho
    // asignado, por eso se lleva la cuenta acá).
    final usados = _anchosUsados[hoja] ??= {};
    for (var c = 0; c < calculados.length; c++) {
      if ((usados[c] ?? 0) < calculados[c]) {
        usados[c] = calculados[c];
        hoja.setColumnWidth(c, calculados[c]);
      }
    }
  }

  static final Expando<Map<int, double>> _anchosUsados = Expando();

  static double _numeroDe(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;

  // =====================================================================
  // DASHBOARD -- primera pestaña de TODOS los Excel exportados. Antes la
  // primera pestaña era la "Sheet1" vacía que trae Excel.createExcel(); ahora
  // es un resumen visual: indicadores grandes (tipo tarjeta) y gráficos de
  // barras dibujados dentro de las celdas (el paquete excel no soporta
  // gráficos nativos; estas barras se ven igual en Excel, Google Sheets y el
  // celular). Uso: crear la hoja con excel['Dashboard'] ANTES que las demás
  // (así queda primera), y al final llamar a _escribirDashboard.
  // =====================================================================

  static final CellStyle _dashTitulo = CellStyle(bold: true, fontSize: 18, fontColorHex: _colorMarca);
  static final CellStyle _dashSubtitulo = CellStyle(italic: true, fontColorHex: ExcelColor.fromHexString('FF6B7280'));
  static final ExcelColor _dashFondoTarjeta = ExcelColor.fromHexString('FFEEF2FF');

  static CellStyle _dashEtiqueta() => CellStyle(
        bold: true, fontSize: 9, fontColorHex: ExcelColor.fromHexString('FF4B5563'),
        backgroundColorHex: _dashFondoTarjeta, topBorder: Border(borderStyle: BorderStyle.Thick, borderColorHex: _colorMarca),
      );

  static CellStyle _dashValor(String formato) => CellStyle(
        bold: true, fontSize: 15, fontColorHex: _colorMarca, backgroundColorHex: _dashFondoTarjeta,
        horizontalAlign: HorizontalAlign.Left,
        numberFormat: switch (formato) {
          'porcentaje' => NumFormat.standard_10,
          'numero' => NumFormat.standard_3,
          _ => NumFormat.custom(formatCode: '"₡"#,##0.00'),
        },
      );

  static CellStyle _dashNota() => CellStyle(
        fontSize: 9, italic: true, fontColorHex: ExcelColor.fromHexString('FF6B7280'), backgroundColorHex: _dashFondoTarjeta,
      );

  /// [indicadores]: (etiqueta, valor, formato 'moneda'|'numero'|'porcentaje', nota opcional).
  /// [graficos]: (título, datos etiqueta->valor, formato de los valores). Se
  /// muestran los 8 más grandes y el resto se agrupa en "Otros".
  static void _escribirDashboard(
    Excel excel, {
    required String titulo,
    String subtitulo = '',
    required List<(String, double, String, String?)> indicadores,
    List<(String, Map<String, double>, String)> graficos = const [],
  }) {
    final hoja = excel['Dashboard'];
    _anchoColumnas(hoja, [2, 30, 30, 26, 26]);

    void celda(int col, CellValue valor, CellStyle estilo) {
      final c = hoja.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: hoja.maxRows - 1));
      c.value = valor;
      c.cellStyle = estilo;
    }

    final hoy = DateTime.now();
    hoja.appendRow([TextCellValue('')]);
    hoja.appendRow([TextCellValue(''), TextCellValue(titulo)]);
    _estilarCeldaUltimaFila(hoja, 1, _dashTitulo);
    hoja.appendRow([
      TextCellValue(''),
      TextCellValue([if (subtitulo.isNotEmpty) subtitulo, 'Generado el ${hoy.day}/${hoy.month}/${hoy.year} con Equilibra'].join('   ·   ')),
    ]);
    _estilarCeldaUltimaFila(hoja, 1, _dashSubtitulo);
    hoja.appendRow([TextCellValue('')]);

    // --- tarjetas de indicadores: 4 por fila (columnas B a E), 3 renglones cada una
    for (var i = 0; i < indicadores.length; i += 4) {
      final grupo = indicadores.sublist(i, (i + 4).clamp(0, indicadores.length));
      hoja.appendRow([TextCellValue('')]);
      for (var j = 0; j < grupo.length; j++) {
        celda(j + 1, TextCellValue(grupo[j].$1.toUpperCase()), _dashEtiqueta());
      }
      hoja.appendRow([TextCellValue('')]);
      for (var j = 0; j < grupo.length; j++) {
        celda(j + 1, DoubleCellValue(grupo[j].$2), _dashValor(grupo[j].$3));
      }
      hoja.appendRow([TextCellValue('')]);
      for (var j = 0; j < grupo.length; j++) {
        celda(j + 1, TextCellValue(grupo[j].$4 ?? ''), _dashNota());
      }
      hoja.appendRow([TextCellValue('')]);
    }

    // --- gráficos de barras en celdas
    final estiloBarra = CellStyle(fontColorHex: _colorMarca);
    final estiloPct = CellStyle(numberFormat: NumFormat.standard_9, fontColorHex: ExcelColor.fromHexString('FF6B7280'), horizontalAlign: HorizontalAlign.Right);
    for (final (tituloGrafico, datosOriginales, formato) in graficos) {
      final datos = datosOriginales.entries.where((e) => e.value.abs() > 0.004).toList()..sort((a, b) => b.value.compareTo(a.value));
      if (datos.isEmpty) continue;
      final visibles = datos.take(8).toList();
      if (datos.length > 8) {
        visibles.add(MapEntry('Otros (${datos.length - 8})', datos.skip(8).fold(0.0, (a, e) => a + e.value)));
      }
      final total = datos.fold(0.0, (a, e) => a + e.value.abs());
      final maximo = visibles.fold(0.0, (a, e) => e.value.abs() > a ? e.value.abs() : a);

      hoja.appendRow([TextCellValue(''), TextCellValue(tituloGrafico)]);
      _estilarCeldaUltimaFila(hoja, 1, _estiloEncabezadoSeccion());
      for (final e in visibles) {
        final largo = maximo == 0 ? 0 : ((e.value.abs() / maximo) * 24).round().clamp(1, 24);
        hoja.appendRow([
          TextCellValue(''),
          TextCellValue(e.key),
          TextCellValue(_bloqueBarra * largo),
          DoubleCellValue(e.value),
          DoubleCellValue(total == 0 ? 0 : e.value.abs() / total),
        ]);
        _estilarCeldaUltimaFila(hoja, 2, estiloBarra);
        _estilarCeldaUltimaFila(hoja, 3, formato == 'numero'
            ? CellStyle(numberFormat: NumFormat.standard_3, horizontalAlign: HorizontalAlign.Right)
            : CellStyle(numberFormat: NumFormat.custom(formatCode: '"₡"#,##0.00'), horizontalAlign: HorizontalAlign.Right));
        _estilarCeldaUltimaFila(hoja, 4, estiloPct);
      }
      hoja.appendRow([TextCellValue('')]);
    }
  }

  static const String _bloqueBarra = '█';

  /// Deja el Dashboard como pestaña inicial y quita la "Sheet1" vacía.
  static void _dashboardPrimero(Excel excel) {
    excel.setDefaultSheet('Dashboard');
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
  }

  /// Suma valores agrupados por una llave (para los gráficos).
  static Map<String, double> _agrupar<T>(Iterable<T> items, String Function(T) llave, double Function(T) valor) {
    final m = <String, double>{};
    for (final it in items) {
      final k = llave(it).trim().isEmpty ? '(sin nombre)' : llave(it).trim();
      m[k] = (m[k] ?? 0) + valor(it);
    }
    return m;
  }

  static String _mesCorto(String fechaIso) {
    const meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'set', 'oct', 'nov', 'dic'];
    final d = DateTime.tryParse(fechaIso);
    return d == null ? '(sin fecha)' : '${meses[d.month - 1]} ${d.year}';
  }

  static double _div(double a, double b) => b == 0 ? 0 : a / b;

  /// Guarda un archivo Excel ya armado, pidiéndole al usuario dónde. En Web
  /// no existe un sistema de archivos real: hay que pasarle los bytes
  /// directo a saveFile() para que dispare la descarga del navegador. En
  /// escritorio, saveFile() solo devuelve la ruta elegida y hay que escribir
  /// el archivo aparte.
  /// Solo para pruebas automáticas (test/export_dashboard_test.dart): si se
  /// asigna, recibe el archivo generado en vez de descargarlo/guardarlo.
  @visibleForTesting
  static void Function(List<int> bytes, String fileName)? capturarExcelParaPruebas;

  static Future<void> _guardarExcel(Excel excel, {required String dialogTitle, required String fileName}) async {
    final bytes = excel.encode()!;
    if (capturarExcelParaPruebas != null) {
      capturarExcelParaPruebas!(bytes, fileName);
      return;
    }
    if (kIsWeb) {
      // file_picker NO implementa saveFile() en Web -- lanza
      // "UnimplementedError: saveFile() has not been implemented" (lo
      // confirmamos leyendo su código fuente). Reportado real: "toco el
      // ícono de Excel y no pasa nada" era justo esta excepción quedando
      // sin capturar. Se dispara la descarga directo por el navegador.
      descargarBytesEnNavegador(Uint8List.fromList(bytes), fileName);
      return;
    }
    final path = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      bytes: Uint8List.fromList(bytes),
    );
    if (path != null) {
      await File(path).writeAsBytes(bytes);
    }
  }

  /// Fuente con soporte para el símbolo de colón (₡, U+20A1): las fuentes
  /// por defecto del paquete pdf (Helvetica) no lo tienen y lo dejan en blanco.
  static Future<pw.ThemeData> _cargarTema() async {
    if (_temaCache != null) return _temaCache!;
    try {
      final logo = await rootBundle.load('assets/branding/logo_equilibra_pdf.png');
      _logoEquilibra = pw.MemoryImage(logo.buffer.asUint8List());
    } catch (_) {
      // Sin el logo el pie sale solo con el texto.
    }
    final regular = await rootBundle.load('assets/fonts/arial.ttf');
    final bold = await rootBundle.load('assets/fonts/arialbd.ttf');
    _temaCache = pw.ThemeData.withFont(
      base: pw.Font.ttf(regular),
      bold: pw.Font.ttf(bold),
    );
    return _temaCache!;
  }

  static pw.MemoryImage? _logoEquilibra;

  /// Formato de página de todos los PDF: A4 con el pie "Generado con
  /// Equilibra" y el logo en el margen de abajo de cada hoja (por fuera del
  /// contenido, así no choca con los pies propios de cada documento).
  static pw.PageTheme _temaPagina({pw.EdgeInsets? margin}) => pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: margin,
        buildForeground: (context) => pw.Align(
          alignment: pw.Alignment.bottomCenter,
          child: pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 14),
            child: _marcaEquilibra(),
          ),
        ),
      );

  static pw.Widget _marcaEquilibra() => pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (_logoEquilibra != null) ...[
            pw.Image(_logoEquilibra!, width: 12, height: 12),
            pw.SizedBox(width: 5),
          ],
          pw.Text(
            'Generado con Equilibra  ·  Facturación electrónica y contabilidad  ·  equilibracr.com',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      );

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

  /// Encabezado de facturas y notas de crédito: logo y datos del negocio
  /// que factura ARRIBA a la izquierda (antes el nombre iba chiquito a la
  /// derecha y la cédula/dirección/contacto quedaban en el pie de página), y
  /// a la derecha un recuadro con el tipo de documento, número y fecha.
  static pw.Widget _encabezadoDocumento({
    required NegocioInfo? info,
    required String nombreNegocio,
    required pw.MemoryImage? logo,
    required String titulo,
    required List<String> datos,
    required PdfColor color,
  }) {
    const gris = pw.TextStyle(fontSize: 9, color: PdfColors.grey700);
    final contacto = [
      if (info?.telefono != null && info!.telefono!.isNotEmpty) 'Tel. ${info.telefono}',
      if (info?.correo != null && info!.correo!.isNotEmpty) info.correo!,
    ].join('  |  ');
    final nombre = (info?.nombreComercial.isNotEmpty ?? false) ? info!.nombreComercial : nombreNegocio;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logo != null) ...[
              pw.Container(width: 70, height: 56, alignment: pw.Alignment.topLeft, child: pw.Image(logo, fit: pw.BoxFit.contain)),
              pw.SizedBox(width: 10),
            ],
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(nombre, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
                  if (info?.nombreLegal != null && info!.nombreLegal!.isNotEmpty && info.nombreLegal != nombre)
                    pw.Text(info.nombreLegal!, style: gris),
                  if (info != null) pw.Text(info.cedulaEtiquetada, style: gris),
                  if (info?.direccion != null && info!.direccion!.isNotEmpty) pw.Text(info.direccion!, style: gris),
                  if (contacto.isNotEmpty) pw.Text(contacto, style: gris),
                ],
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Container(
              width: 170,
              decoration: pw.BoxDecoration(border: pw.Border.all(color: color, width: 0.8)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Container(
                    color: color,
                    padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
                    child: pw.Text(titulo,
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10.5)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Column(
                      children: datos
                          .map((d) => pw.Text(d, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9)))
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Divider(color: PdfColors.grey400, thickness: 0.7),
      ],
    );
  }

  /// Cierre de facturas y notas de crédito (los datos del negocio ahora van
  /// en el encabezado, ver [_encabezadoDocumento]).
  static pw.Widget _piePagina() => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 24),
        child: pw.Text(
          'Documento generado electrónicamente. No requiere firma manuscrita.',
          style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500, fontStyle: pw.FontStyle.italic),
        ),
      );

  /// Exporta el listado de facturas a PDF
  static Future<void> exportFacturasToPdf(
    List<Factura> todas,
    String negocioNombre,
    String periodo, {
    List<NotaCredito> notasCredito = const [],
  }) async {
    final facturas = todas.where(_ventaValida).toList();
    final excluidas = todas.length - facturas.length;
    final notas = notasCredito.where(_notaValida).toList();
    final ventasSub = facturas.fold<double>(0.0, (s, f) => s + (f.totalFactura - f.totalIva));
    final ventasIva = facturas.fold<double>(0.0, (s, f) => s + f.totalIva);
    final notasSub = notas.fold<double>(0.0, (s, n) => s + n.subtotal);
    final notasIva = notas.fold<double>(0.0, (s, n) => s + n.montoIva);
    final pdf = pw.Document(theme: await _cargarTema());
    pdf.addPage(pw.MultiPage(
      pageTheme: _temaPagina(),
      build: (pw.Context context) => [
        pw.Header(
          level: 0,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Reporte de Facturación', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo)),
                  pw.Text('Periodo: $periodo', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                ],
              ),
              pw.Text(negocioNombre, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: pw.BoxDecoration(color: PdfColors.indigo50, borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(
            children: [
              for (final (etiqueta, sub, iva, fuerte) in [
                ('Ventas (${facturas.length} comprobante${facturas.length == 1 ? '' : 's'})', ventasSub, ventasIva, false),
                if (notas.isNotEmpty) ('(-) Notas de crédito (${notas.length})', -notasSub, -notasIva, false),
                ('Ventas netas', ventasSub - notasSub, ventasIva - notasIva, true),
              ])
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        flex: 3,
                        child: pw.Text(etiqueta, style: pw.TextStyle(fontSize: fuerte ? 12.5 : 11, fontWeight: fuerte ? pw.FontWeight.bold : null)),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text('Subtotal ${formatearColones(sub)}', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 10.5)),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text('IVA ${formatearColones(iva)}', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 10.5)),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text(
                          formatearColones(sub + iva),
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(fontSize: fuerte ? 13 : 11, fontWeight: pw.FontWeight.bold, color: fuerte ? PdfColors.indigo : PdfColors.grey800),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo),
          cellStyle: const pw.TextStyle(fontSize: 9.5),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          headerPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          headers: const ['Fecha', 'Doc #', 'Cliente', 'Condición', 'Subtotal', 'Tarifa', 'IVA', 'Total'],
          columnWidths: const {
            0: pw.FlexColumnWidth(1.2),
            1: pw.FlexColumnWidth(1.1),
            2: pw.FlexColumnWidth(2.2),
            3: pw.FlexColumnWidth(1.1),
            4: pw.FlexColumnWidth(1.3),
            5: pw.FlexColumnWidth(0.8),
            6: pw.FlexColumnWidth(1.2),
            7: pw.FlexColumnWidth(1.3),
          },
          cellAlignments: const {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerLeft,
            3: pw.Alignment.center,
            4: pw.Alignment.centerRight,
            5: pw.Alignment.center,
            6: pw.Alignment.centerRight,
            7: pw.Alignment.centerRight,
          },
          data: facturas.map((f) => [
            f.fechaEmision.split('T')[0],
            'F-${f.consecutivo}',
            f.receptorNombre,
            f.condicionVenta == "02" ? 'Crédito' : 'Contado',
            formatearColones(f.totalFactura - f.totalIva),
            _tarifaFactura(f),
            formatearColones(f.totalIva),
            formatearColones(f.totalFactura),
          ]).toList(),
        ),
        if (notas.isNotEmpty) ...[
          pw.SizedBox(height: 22),
          pw.Text('Notas de crédito (se restan de las ventas)', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.red800),
            cellStyle: const pw.TextStyle(fontSize: 9.5),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            headerPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            headers: const ['Fecha', 'Nota #', 'Anula', 'Cliente', 'Subtotal', 'IVA', 'Total'],
            cellAlignments: const {4: pw.Alignment.centerRight, 5: pw.Alignment.centerRight, 6: pw.Alignment.centerRight},
            data: [
              for (final n in notas)
                [
                  n.fechaEmision.split('T')[0],
                  n.consecutivo,
                  'F-${n.facturaConsecutivo ?? ''}',
                  n.receptorNombre,
                  '-${formatearColones(n.subtotal)}',
                  '-${formatearColones(n.montoIva)}',
                  '-${formatearColones(n.total)}',
                ],
            ],
          ),
        ],
        if (excluidas > 0) ...[
          pw.SizedBox(height: 10),
          pw.Text(
            'No se incluyen $excluidas comprobante${excluidas == 1 ? '' : 's'} rechazado${excluidas == 1 ? '' : 's'} o con error ante Hacienda (no son ventas).',
            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600, fontStyle: pw.FontStyle.italic),
          ),
        ],
        pw.SizedBox(height: 24),
        pw.Text('Detalle por tarifa de IVA (facturas)', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo)),
        pw.SizedBox(height: 8),
        pw.Builder(builder: (context) {
          final porTarifa = _agruparPorTarifa(facturas);
          final tarifas = porTarifa.base.keys.toList()..sort();
          return pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo),
            cellStyle: const pw.TextStyle(fontSize: 9.5),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            headerPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            headers: const ['Tarifa', 'Base', 'IVA', 'Total'],
            cellAlignments: const {
              0: pw.Alignment.center,
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
            data: tarifas.map((t) {
              final base = porTarifa.base[t] ?? 0;
              final iva = porTarifa.iva[t] ?? 0;
              return ['$t%', formatearColones(base), formatearColones(iva), formatearColones(base + iva)];
            }).toList(),
          );
        }),
        ..._seccionDolaresPdf('Facturas', 'Cliente', [for (final f in facturas) ('F-${f.consecutivo}', f.fechaEmision.split('T')[0], f.receptorNombre, _usdFactura(f))]),
      ],
    ));
    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Facturacion.pdf');
  }

  /// Exporta el listado de facturas a Excel: fila 1-2 el resumen de sumas
  /// (Subtotal/IVA/Total de todo el periodo), fila 4 el encabezado de la
  /// tabla y desde la fila 5 el detalle línea por línea -- y una hoja
  /// aparte con el desglose agrupado por tarifa de IVA.
  static Future<void> exportFacturasToExcel(List<Factura> todas, {List<NotaCredito> notasCredito = const []}) async {
    final facturas = todas.where(_ventaValida).toList();
    final excluidas = todas.length - facturas.length;
    final notas = notasCredito.where(_notaValida).toList();
    final notasSub = notas.fold<double>(0.0, (s, n) => s + n.subtotal);
    final notasIva = notas.fold<double>(0.0, (s, n) => s + n.montoIva);
    final notasTotal = notas.fold<double>(0.0, (s, n) => s + n.total);
    var excel = Excel.createExcel();
    excel['Dashboard']; // primera pestaña (ver _escribirDashboard)
    Sheet sheetObject = excel['Facturas'];
    final hayUsd = facturas.any((f) => _esUsd(_usdFactura(f)));

    final sumaSubtotal = facturas.fold<double>(0.0, (s, f) => s + (f.totalFactura - f.totalIva));
    final sumaIva = facturas.fold<double>(0.0, (s, f) => s + f.totalIva);
    final sumaTotal = facturas.fold<double>(0.0, (s, f) => s + f.totalFactura);

    sheetObject.appendRow([TextCellValue('Reporte de Facturación')]); // fila 1
    _estilarCeldaUltimaFila(sheetObject, 0, _estiloTitulo());
    sheetObject.appendRow([                                          // fila 2: ventas netas del periodo
      TextCellValue('Subtotal neto:'), DoubleCellValue(sumaSubtotal - notasSub),
      TextCellValue('IVA neto:'), DoubleCellValue(sumaIva - notasIva),
      TextCellValue('Ventas netas:'), DoubleCellValue(sumaTotal - notasTotal),
    ]);
    _estilarCeldaUltimaFila(sheetObject, 1, _estiloMoneda());
    _estilarCeldaUltimaFila(sheetObject, 3, _estiloMoneda());
    _estilarCeldaUltimaFila(sheetObject, 5, _estiloMoneda(negrita: true));
    sheetObject.appendRow([]); // fila 3: separador
    sheetObject.appendRow([    // fila 4: encabezado de la tabla
      TextCellValue('Fecha'),
      TextCellValue('Consecutivo'),
      TextCellValue('Cliente'),
      TextCellValue('Cédula'),
      TextCellValue('Condición'),
      TextCellValue('Subtotal'),
      TextCellValue('Tarifa'),
      TextCellValue('IVA'),
      TextCellValue('Total'),
      if (hayUsd) ..._encabezadosUsd.map((e) => TextCellValue(e)),
    ]);
    _estilarUltimaFila(sheetObject, hayUsd ? 14 : 9, _estiloEncabezadoTabla());

    for (var f in facturas) { // fila 5 en adelante: una por factura
      sheetObject.appendRow([
        TextCellValue(f.fechaEmision.split('T')[0]),
        TextCellValue(f.consecutivo),
        TextCellValue(f.receptorNombre),
        TextCellValue(f.receptorCedula ?? ''),
        TextCellValue(f.condicionVenta == "02" ? 'Crédito' : 'Contado'),
        DoubleCellValue(f.totalFactura - f.totalIva),
        TextCellValue(_tarifaFactura(f)),
        DoubleCellValue(f.totalIva),
        DoubleCellValue(f.totalFactura),
        if (hayUsd) ..._celdasUsd(_usdFactura(f)),
      ]);
      for (final col in [5, 7, 8]) {
        _estilarCeldaUltimaFila(sheetObject, col, _estiloMoneda());
      }
      if (hayUsd) _estilarUsdUltimaFila(sheetObject, 9);
    }
    sheetObject.appendRow([]);
    sheetObject.appendRow([
      TextCellValue('TOTAL'), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''),
      DoubleCellValue(sumaSubtotal), TextCellValue(''), DoubleCellValue(sumaIva), DoubleCellValue(sumaTotal),
      if (hayUsd) ..._totalesUsd(facturas.map(_usdFactura)),
    ]);
    _estilarCeldaUltimaFila(sheetObject, 0, _estiloTotalTexto());
    for (final col in [5, 7, 8]) {
      _estilarCeldaUltimaFila(sheetObject, col, _estiloTotalMoneda());
    }
    if (hayUsd) _estilarUsdUltimaFila(sheetObject, 9, total: true);
    if (notas.isNotEmpty) {
      // Las notas de crédito restan; abajo, las ventas netas.
      for (final (etiqueta, sub, iva, tot) in [
        ('(-) Notas de crédito (${notas.length})', -notasSub, -notasIva, -notasTotal),
        ('VENTAS NETAS', sumaSubtotal - notasSub, sumaIva - notasIva, sumaTotal - notasTotal),
      ]) {
        sheetObject.appendRow([
          TextCellValue(etiqueta), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''),
          DoubleCellValue(sub), TextCellValue(''), DoubleCellValue(iva), DoubleCellValue(tot),
        ]);
        _estilarCeldaUltimaFila(sheetObject, 0, _estiloTotalTexto());
        for (final col in [5, 7, 8]) {
          _estilarCeldaUltimaFila(sheetObject, col, _estiloTotalMoneda());
        }
      }
    }
    if (excluidas > 0) {
      sheetObject.appendRow([TextCellValue('No se incluyen $excluidas comprobante(s) rechazado(s) o con error ante Hacienda (no son ventas).')]);
      _estilarCeldaUltimaFila(sheetObject, 0, CellStyle(italic: true, fontColorHex: ExcelColor.fromHexString('FF6B7280')));
    }
    if (notas.isNotEmpty) {
      _escribirTabla(
        excel['Notas de crédito'],
        titulo: 'Notas de crédito del periodo (se restan de las ventas)',
        encabezados: const ['Fecha', 'Consecutivo', 'Anula factura', 'Cliente', 'Subtotal', 'IVA', 'Total'],
        filas: [
          for (final n in notas)
            [
              TextCellValue(n.fechaEmision.split('T')[0]),
              TextCellValue(n.consecutivo),
              TextCellValue('F-${n.facturaConsecutivo ?? ''}'),
              TextCellValue(n.receptorNombre),
              DoubleCellValue(-n.subtotal),
              DoubleCellValue(-n.montoIva),
              DoubleCellValue(-n.total),
            ],
        ],
        moneda: const {4, 5, 6},
        sumar: const {4, 5, 6},
      );
    }

    // Detalle por Tarifa: a la par de la tabla principal (no en otra hoja),
    // arrancando en la columna K (deja J de separación) y alineado con
    // las primeras filas del resumen.
    // K, o P si están las columnas en dólares (deja una de separación).
    final colTarifas = hayUsd ? 15 : 10;
    void celda(int col, int fila, CellValue valor) {
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: fila)).value = valor;
    }
    void estilarCelda(int col, int fila, CellStyle estilo) {
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: fila)).cellStyle = estilo;
    }

    celda(colTarifas, 0, TextCellValue('Detalle por Tarifa de IVA'));
    estilarCelda(colTarifas, 0, _estiloEncabezadoSeccion());
    celda(colTarifas, 1, TextCellValue('Tarifa'));
    celda(colTarifas + 1, 1, TextCellValue('Base'));
    celda(colTarifas + 2, 1, TextCellValue('IVA'));
    celda(colTarifas + 3, 1, TextCellValue('Total'));
    for (var i = 0; i < 4; i++) {
      estilarCelda(colTarifas + i, 1, _estiloEncabezadoTabla());
    }

    final porTarifa = _agruparPorTarifa(facturas);
    final tarifasOrdenadas = porTarifa.base.keys.toList()..sort();
    var filaTarifa = 2;
    for (final t in tarifasOrdenadas) {
      final base = porTarifa.base[t] ?? 0;
      final iva = porTarifa.iva[t] ?? 0;
      celda(colTarifas, filaTarifa, TextCellValue('$t%'));
      celda(colTarifas + 1, filaTarifa, DoubleCellValue(base));
      estilarCelda(colTarifas + 1, filaTarifa, _estiloMoneda());
      celda(colTarifas + 2, filaTarifa, DoubleCellValue(iva));
      estilarCelda(colTarifas + 2, filaTarifa, _estiloMoneda());
      celda(colTarifas + 3, filaTarifa, DoubleCellValue(base + iva));
      estilarCelda(colTarifas + 3, filaTarifa, _estiloMoneda());
      filaTarifa++;
    }
    final baseTotal = porTarifa.base.values.fold(0.0, (s, v) => s + v);
    final ivaTotal = porTarifa.iva.values.fold(0.0, (s, v) => s + v);
    celda(colTarifas, filaTarifa, TextCellValue('TOTAL'));
    estilarCelda(colTarifas, filaTarifa, _estiloTotalTexto());
    celda(colTarifas + 1, filaTarifa, DoubleCellValue(baseTotal));
    estilarCelda(colTarifas + 1, filaTarifa, _estiloTotalMoneda());
    celda(colTarifas + 2, filaTarifa, DoubleCellValue(ivaTotal));
    estilarCelda(colTarifas + 2, filaTarifa, _estiloTotalMoneda());
    celda(colTarifas + 3, filaTarifa, DoubleCellValue(baseTotal + ivaTotal));
    estilarCelda(colTarifas + 3, filaTarifa, _estiloTotalMoneda());
    _anchoColumnas(sheetObject, [14, 14, 26, 14, 12, 14, 10, 14, 14, if (hayUsd) ...[9, 13, 14, 12, 14], 3, 14, 14, 14, 14]);


    {
      // Mismo criterio que el resto del reporte: sin rechazadas y menos
      // las notas de crédito (una factura anulada ya está compensada por
      // su nota).
      final validas = facturas;
      final total = validas.fold(0.0, (a, f) => a + f.totalFactura) - notasTotal;
      final iva = validas.fold(0.0, (a, f) => a + f.totalIva) - notasIva;
      final credito = validas.where((f) => f.condicionVenta == '02');
      final porCobrar = credito.where((f) => !f.pagada).fold(0.0, (a, f) => a + f.totalFactura);
      final aceptadas = facturas.where((f) => f.estadoHacienda == '3').length;
      const estados = {'1': 'Sin enviar', '2': 'Procesando', '3': 'Aceptada', '4': 'Rechazada', '5': 'Error técnico', '6': 'Interno'};
      _escribirDashboard(
        excel,
        titulo: 'Dashboard de facturación',
        subtitulo: '${facturas.length} comprobante(s)${notas.isEmpty ? '' : ' y ${notas.length} nota(s) de crédito'}',
        indicadores: [
          ('Ventas netas', total, 'moneda', notas.isEmpty ? 'Sin rechazadas' : 'Sin rechazadas, menos notas de crédito'),
          ('Subtotal (sin IVA)', total - iva, 'moneda', null),
          ('IVA facturado', iva, 'moneda', null),
          ('Ticket promedio', _div(total, validas.length.toDouble()), 'moneda', 'Por comprobante'),
          ('Comprobantes', validas.length.toDouble(), 'numero', null),
          ('Aceptadas por Hacienda', _div(aceptadas.toDouble(), todas.length.toDouble()), 'porcentaje', '$aceptadas de ${todas.length}'),
          ('Ventas a crédito', _div(credito.fold(0.0, (a, f) => a + f.totalFactura), total), 'porcentaje', 'Del total facturado'),
          ('Pendiente de cobro', porCobrar, 'moneda', 'Facturas a crédito sin pagar'),
        ],
        graficos: [
          ('Ventas por cliente', _agrupar<Factura>(validas, (f) => f.receptorNombre, (f) => f.totalFactura), 'moneda'),
          ('Ventas por mes', _agrupar<Factura>(validas, (f) => _mesCorto(f.fechaEmision), (f) => f.totalFactura), 'moneda'),
          ('Contado vs. crédito', _agrupar<Factura>(validas, (f) => f.condicionVenta == '02' ? 'Crédito' : 'Contado', (f) => f.totalFactura), 'moneda'),
          ('Comprobantes por estado ante Hacienda', _agrupar<Factura>(todas, (f) => estados[f.estadoHacienda] ?? f.estadoHacienda, (_) => 1), 'numero'),
        ],
      );
    }
    _dashboardPrimero(excel);

    await _guardarExcel(excel, dialogTitle: 'Guardar Reporte de Facturación', fileName: 'reporte_facturacion.xlsx');
  }

  /// Exporta el reporte consolidado (GET /reportes/consolidado/, ver
  /// ReporteConsolidadoView) a PDF -- ventas, notas de crédito, compras,
  /// notas de débito y el resumen para la declaración de IVA, según lo que
  /// venga en la respuesta.
  static Future<void> exportReporteConsolidadoToPdf(Map<String, dynamic> reporte, String periodo) async {
    final negocioNombre = reporte['negocio_nombre']?.toString() ?? '';
    final pdf = pw.Document(theme: await _cargarTema());
    pdf.addPage(pw.MultiPage(pageTheme: _temaPagina(), build: (context) => _widgetsReporteConsolidado(reporte, periodo)));
    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Reporte_$negocioNombre.pdf');
  }

  /// Igual que exportReporteConsolidadoToPdf pero para varios negocios a la
  /// vez (selección múltiple o "todos" en la pestaña de Reportes del
  /// contador): arma un PDF único con una portada de resumen por cliente y
  /// luego el detalle completo de cada uno, cada uno arrancando en página
  /// nueva.
  static Future<void> exportReportesConsolidadosToPdf(List<Map<String, dynamic>> reportes, String periodo) async {
    final widgets = <pw.Widget>[
      pw.Header(
        level: 0,
        child: pw.Text('Reporte de Ventas y Compras — Resumen por Cliente', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      ),
      pw.Text('Periodo: $periodo', style: const pw.TextStyle(fontSize: 12)),
      pw.SizedBox(height: 12),
      pw.TableHelper.fromTextArray(
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        headers: const ['Cliente', 'Total Ventas', 'Total Compras', 'IVA a pagar'],
        data: reportes.map((r) {
          final resumen = r['resumen_declaracion'] as Map<String, dynamic>?;
          final ventas = r['ventas'] as Map<String, dynamic>?;
          final compras = r['compras'] as Map<String, dynamic>?;
          return [
            r['negocio_nombre']?.toString() ?? '',
            ventas != null ? formatearColones(double.tryParse(ventas['total'].toString()) ?? 0) : '-',
            compras != null ? formatearColones(double.tryParse(compras['total'].toString()) ?? 0) : '-',
            resumen != null ? formatearColones(double.tryParse(resumen['iva_a_pagar'].toString()) ?? 0) : '-',
          ];
        }).toList(),
      ),
    ];
    for (final reporte in reportes) {
      widgets.add(pw.NewPage());
      widgets.addAll(_widgetsReporteConsolidado(reporte, periodo));
    }
    final pdf = pw.Document(theme: await _cargarTema());
    pdf.addPage(pw.MultiPage(pageTheme: _temaPagina(), build: (context) => widgets));
    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Reportes_Clientes.pdf');
  }

  static List<pw.Widget> _widgetsReporteConsolidado(Map<String, dynamic> reporte, String periodo) {
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

    return widgets;
  }

  /// Exporta el reporte consolidado a Excel -- una hoja por sección que
  /// exista en la respuesta (Resumen Declaración/Ventas/Notas de
  /// Crédito/Compras/Notas de Débito).
  static Future<void> exportReporteConsolidadoToExcel(Map<String, dynamic> reporte) async {
    var excel = Excel.createExcel();
    excel['Dashboard']; // primera pestaña (ver _escribirDashboard)
    _escribirReporteConsolidadoEnExcel(excel, reporte);

    // NO se borra la hoja "Sheet1" que trae Excel.createExcel() por defecto:
    // el propio código del paquete excel (save_file.dart) advierte que
    // borrar/renombrar la hoja default es una operación insegura ("Maybe
    // overkill and unsafe... another safer method preferred"), y en la
    // práctica hacía que excel.encode() fallara silenciosamente y la
    // exportación no generara ningún archivo. Queda como una pestaña extra
    // vacía en el archivo, sin romper nada.
    final negocioNombre = reporte['negocio_nombre']?.toString() ?? 'reporte';

    {
      double n(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;
      final ventas = reporte['ventas'] as Map<String, dynamic>?;
      final compras = reporte['compras'] as Map<String, dynamic>?;
      final docsV = (ventas?['documentos'] as List?) ?? [];
      final docsC = (compras?['documentos'] as List?) ?? [];
      final ventasNetas = n(ventas?['total_neto']);
      final comprasTot = n(compras?['total_neto']);
      final ivaV = ((ventas?['desglose_impuestos'] as List?) ?? []).fold(0.0, (a, d) => a + n(d['monto_impuesto']));
      final ivaC = ((compras?['desglose_impuestos'] as List?) ?? []).fold(0.0, (a, d) => a + n(d['monto_impuesto']));
      _escribirDashboard(
        excel,
        titulo: 'Dashboard · ${reporte['negocio_nombre'] ?? ''}',
        subtitulo: 'Ventas y compras del periodo',
        indicadores: [
          ('Ventas netas', ventasNetas, 'moneda', 'Ventas menos notas de crédito'),
          ('Compras', comprasTot, 'moneda', 'Incluye notas de débito'),
          ('Resultado bruto', ventasNetas - comprasTot, 'moneda', 'Ventas netas - compras'),
          ('Margen bruto', _div(ventasNetas - comprasTot, ventasNetas), 'porcentaje', 'Aproximado'),
          ('IVA de ventas', ivaV, 'moneda', 'Débito fiscal'),
          ('IVA de compras', ivaC, 'moneda', 'Crédito fiscal (estimado)'),
          ('IVA a pagar', ivaV - ivaC, 'moneda', null),
          ('Facturas emitidas', docsV.length.toDouble(), 'numero', '${docsC.length} compra(s)'),
        ],
        graficos: [
          ('Ventas por cliente', _agrupar<dynamic>(docsV, (d) => d['cliente']?.toString() ?? '', (d) => n(d['total'])), 'moneda'),
          ('Compras por proveedor', _agrupar<dynamic>(docsC, (d) => d['proveedor']?.toString() ?? '', (d) => n(d['total'])), 'moneda'),
          ('Ventas por tarifa de IVA (base)', _agrupar<dynamic>((ventas?['desglose_impuestos'] as List?) ?? [], (d) => d['tarifa']?.toString() ?? '', (d) => n(d['base_imponible'])), 'moneda'),
        ],
      );
    }
    _dashboardPrimero(excel);

    await _guardarExcel(
      excel,
      dialogTitle: 'Guardar Reporte de Ventas y Compras',
      fileName: 'reporte_${negocioNombre.replaceAll(' ', '_')}.xlsx',
    );
  }

  /// Igual que exportReporteConsolidadoToExcel pero para varios negocios:
  /// una hoja "Resumen" con el total de cada cliente, y luego las hojas de
  /// detalle de cada uno con el nombre del cliente como prefijo (truncado a
  /// lo que entra en el límite de 31 caracteres que exige xlsx).
  static Future<void> exportReportesConsolidadosToExcel(List<Map<String, dynamic>> reportes, {String periodo = ''}) async {
    var excel = Excel.createExcel();
    excel['Dashboard']; // primera pestaña (ver _escribirDashboard)
    final hoja = excel['Resumen'];
    _escribirResumenClientes(hoja, reportes, periodo);

    for (var i = 0; i < reportes.length; i++) {
      final nombreCorto = (reportes[i]['negocio_nombre']?.toString() ?? 'Cliente ${i + 1}');
      final prefijo = '${i + 1}-${nombreCorto.length > 12 ? nombreCorto.substring(0, 12) : nombreCorto} ';
      _escribirReporteConsolidadoEnExcel(excel, reportes[i], prefijo: prefijo);
    }


    {
      double n(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;
      final ventasPorCliente = <String, double>{};
      final ivaPorCliente = <String, double>{};
      double ventas = 0, compras = 0, iva = 0;
      var conMovimiento = 0;
      for (final r in reportes) {
        final nombre = r['negocio_nombre']?.toString() ?? '';
        final v = n((r['ventas'] as Map?)?['total_neto']);
        final c = n((r['compras'] as Map?)?['total_neto']);
        final i = n((r['resumen_declaracion'] as Map?)?['iva_a_pagar']);
        ventas += v;
        compras += c;
        iva += i;
        if (v != 0 || c != 0) conMovimiento++;
        ventasPorCliente[nombre] = v;
        ivaPorCliente[nombre] = i;
      }
      _escribirDashboard(
        excel,
        titulo: 'Dashboard de la cartera',
        subtitulo: [if (periodo.isNotEmpty) 'Periodo: $periodo', '${reportes.length} cliente(s)'].join('   ·   '),
        indicadores: [
          ('Ventas netas (todos)', ventas, 'moneda', null),
          ('Compras (todos)', compras, 'moneda', null),
          ('IVA a pagar (todos)', iva, 'moneda', 'Suma de los saldos por cliente'),
          ('Clientes con movimiento', conMovimiento.toDouble(), 'numero', 'De ${reportes.length} en el reporte'),
        ],
        graficos: [
          ('Ventas netas por cliente', ventasPorCliente, 'moneda'),
          ('IVA a pagar por cliente', ivaPorCliente, 'moneda'),
        ],
      );
    }
    _dashboardPrimero(excel);

    await _guardarExcel(
      excel,
      dialogTitle: 'Guardar Reportes de Ventas y Compras',
      fileName: 'reportes_clientes.xlsx',
    );
  }

  /// Hoja "Resumen" del Excel de varios clientes: totales por cliente
  /// (subtotal, IVA y total de ventas y compras, notas de crédito, IVA a
  /// pagar), el detalle por tarifa de IVA de cada uno y los totales por
  /// tarifa de toda la cartera. Los datos vienen tal cual de
  /// /reportes/consolidado/ (ver ReporteConsolidadoView).
  static void _escribirResumenClientes(Sheet hoja, List<Map<String, dynamic>> reportes, String periodo) {
    double n(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;
    double sumar(List? docs, String campo) => (docs ?? []).fold(0.0, (a, d) => a + n((d as Map)[campo]));

    // Anchos: cliente ancho, el resto montos.
    _anchoColumnas(hoja, [34, 17, 15, 16, 17, 17, 15, 17, 17]);

    hoja.appendRow([TextCellValue('Resumen de ventas, compras e IVA por cliente')]);
    _estilarCeldaUltimaFila(hoja, 0, _estiloTitulo());
    hoja.appendRow([TextCellValue([
      if (periodo.isNotEmpty) 'Periodo: $periodo',
      '${reportes.length} cliente(s)',
      'Generado: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
    ].join('   ·   '))]);
    _estilarCeldaUltimaFila(hoja, 0, _estiloSubtitulo());
    hoja.appendRow([]);

    // ---------------- 1. Totales por cliente
    hoja.appendRow([TextCellValue('Totales por cliente')]);
    _estilarCeldaUltimaFila(hoja, 0, _estiloEncabezadoSeccion());
    final grupos = [
      '', 'VENTAS', '', '', '', 'COMPRAS', '', '', '',
    ];
    hoja.appendRow(grupos.map((g) => TextCellValue(g)).toList());
    _estilarUltimaFila(hoja, 9, CellStyle(bold: true, fontColorHex: _colorMarca, horizontalAlign: HorizontalAlign.Center));
    final filaGrupos = hoja.maxRows - 1;
    // "VENTAS" sobre sus 4 columnas y "COMPRAS" sobre sus 3.
    hoja.merge(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: filaGrupos), CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: filaGrupos), customValue: TextCellValue('VENTAS'));
    hoja.merge(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: filaGrupos), CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: filaGrupos), customValue: TextCellValue('COMPRAS'));
    final encabezados = [
      'Cliente', 'Subtotal', 'IVA', 'Notas de crédito', 'Total ventas',
      'Subtotal', 'IVA (estimado)', 'Total compras', 'IVA a pagar',
    ];
    hoja.appendRow(encabezados.map((e) => TextCellValue(e)).toList());
    _estilarUltimaFila(hoja, encabezados.length, _estiloEncabezadoTabla());

    final totales = List<double>.filled(8, 0);
    for (final r in reportes) {
      final ventas = r['ventas'] as Map<String, dynamic>?;
      final compras = r['compras'] as Map<String, dynamic>?;
      final resumen = r['resumen_declaracion'] as Map<String, dynamic>?;
      final valores = <double?>[
        ventas == null ? null : sumar(ventas['documentos'] as List?, 'subtotal'),
        ventas == null ? null : sumar(ventas['documentos'] as List?, 'monto_iva'),
        ventas == null ? null : n(ventas['total_notas_credito']),
        ventas == null ? null : n(ventas['total']),
        compras == null ? null : sumar(compras['documentos'] as List?, 'subtotal_estimado'),
        compras == null ? null : sumar(compras['documentos'] as List?, 'monto_iva_estimado'),
        compras == null ? null : n(compras['total']),
        resumen == null ? null : n(resumen['iva_a_pagar']),
      ];
      hoja.appendRow([
        TextCellValue(r['negocio_nombre']?.toString() ?? ''),
        for (final v in valores) v == null ? TextCellValue('-') : DoubleCellValue(v),
      ]);
      for (var c = 0; c < valores.length; c++) {
        if (valores[c] != null) {
          totales[c] += valores[c]!;
          _estilarCeldaUltimaFila(hoja, c + 1, _estiloMoneda(negrita: c == 3 || c == 6 || c == 7));
        }
      }
    }
    hoja.appendRow([TextCellValue('TOTALES'), for (final t in totales) DoubleCellValue(t)]);
    _estilarCeldaUltimaFila(hoja, 0, _estiloTotalTexto());
    for (var c = 1; c <= totales.length; c++) {
      _estilarCeldaUltimaFila(hoja, c, _estiloTotalMoneda());
    }
    hoja.appendRow([]);
    hoja.appendRow([]);

    // ---------------- 2. Detalle por tarifa de IVA de cada cliente
    hoja.appendRow([TextCellValue('Detalle por tarifa de IVA')]);
    _estilarCeldaUltimaFila(hoja, 0, _estiloEncabezadoSeccion());
    final encTarifa = ['Cliente', 'Tarifa', 'Ventas: base imponible', 'Ventas: IVA', 'Compras: base imponible', 'Compras: IVA'];
    hoja.appendRow(encTarifa.map((e) => TextCellValue(e)).toList());
    _estilarUltimaFila(hoja, encTarifa.length, _estiloEncabezadoTabla());

    // tarifa -> [base ventas, iva ventas, base compras, iva compras] para toda la cartera
    final porTarifaGeneral = <String, List<double>>{};
    final estiloCliente = CellStyle(bold: true, fontColorHex: _colorMarca);

    for (final r in reportes) {
      final ventas = r['ventas'] as Map<String, dynamic>?;
      final compras = r['compras'] as Map<String, dynamic>?;
      final porTarifa = <String, List<double>>{};
      for (final d in (ventas?['desglose_impuestos'] as List? ?? [])) {
        final fila = porTarifa.putIfAbsent(d['tarifa']?.toString() ?? '-', () => List<double>.filled(4, 0));
        fila[0] += n(d['base_imponible']);
        fila[1] += n(d['monto_impuesto']);
      }
      for (final d in (compras?['desglose_impuestos'] as List? ?? [])) {
        final fila = porTarifa.putIfAbsent(d['tarifa']?.toString() ?? '-', () => List<double>.filled(4, 0));
        fila[2] += n(d['base_imponible']);
        fila[3] += n(d['monto_impuesto']);
      }
      final nombre = r['negocio_nombre']?.toString() ?? '';
      if (porTarifa.isEmpty) {
        hoja.appendRow([TextCellValue(nombre), TextCellValue('Sin movimientos en el periodo')]);
        _estilarCeldaUltimaFila(hoja, 0, estiloCliente);
        _estilarCeldaUltimaFila(hoja, 1, _estiloSubtitulo());
        continue;
      }
      final subtotal = List<double>.filled(4, 0);
      var primera = true;
      for (final e in porTarifa.entries) {
        hoja.appendRow([
          TextCellValue(primera ? nombre : ''),
          TextCellValue(e.key),
          for (final v in e.value) DoubleCellValue(v),
        ]);
        if (primera) _estilarCeldaUltimaFila(hoja, 0, estiloCliente);
        for (var c = 2; c < 6; c++) {
          _estilarCeldaUltimaFila(hoja, c, _estiloMoneda());
        }
        primera = false;
        final general = porTarifaGeneral.putIfAbsent(e.key, () => List<double>.filled(4, 0));
        for (var i = 0; i < 4; i++) {
          subtotal[i] += e.value[i];
          general[i] += e.value[i];
        }
      }
      if (porTarifa.length > 1) {
        hoja.appendRow([TextCellValue(''), TextCellValue('Subtotal $nombre'), for (final v in subtotal) DoubleCellValue(v)]);
        _estilarCeldaUltimaFila(hoja, 1, _estiloTotalTexto());
        for (var c = 2; c < 6; c++) {
          _estilarCeldaUltimaFila(hoja, c, _estiloTotalMoneda());
        }
      }
    }
    hoja.appendRow([]);
    hoja.appendRow([]);

    // ---------------- 3. Totales por tarifa (toda la cartera)
    hoja.appendRow([TextCellValue('Totales por tarifa (todos los clientes)')]);
    _estilarCeldaUltimaFila(hoja, 0, _estiloEncabezadoSeccion());
    final encGeneral = ['Tarifa', 'Ventas: base imponible', 'Ventas: IVA', 'Compras: base imponible', 'Compras: IVA', 'IVA neto'];
    hoja.appendRow(encGeneral.map((e) => TextCellValue(e)).toList());
    _estilarUltimaFila(hoja, encGeneral.length, _estiloEncabezadoTabla());
    final granTotal = List<double>.filled(5, 0);
    for (final e in porTarifaGeneral.entries) {
      final neto = e.value[1] - e.value[3];
      final fila = [...e.value, neto];
      hoja.appendRow([TextCellValue(e.key), for (final v in fila) DoubleCellValue(v)]);
      for (var c = 1; c < 6; c++) {
        _estilarCeldaUltimaFila(hoja, c, _estiloMoneda(negrita: c == 5));
      }
      for (var i = 0; i < 5; i++) {
        granTotal[i] += fila[i];
      }
    }
    hoja.appendRow([TextCellValue('TOTAL'), for (final v in granTotal) DoubleCellValue(v)]);
    _estilarCeldaUltimaFila(hoja, 0, _estiloTotalTexto());
    for (var c = 1; c < 6; c++) {
      _estilarCeldaUltimaFila(hoja, c, _estiloTotalMoneda());
    }

    hoja.appendRow([]);
    hoja.appendRow([TextCellValue(
      'Notas: la base imponible de ventas ya descuenta las notas de crédito. El IVA de compras se calcula con la '
      'tarifa que cada producto tiene asignada en el catálogo. El detalle documento por documento de cada cliente '
      'está en las hojas siguientes.',
    )]);
    _estilarCeldaUltimaFila(hoja, 0, _estiloSubtitulo());
  }

  /// Escribe las hojas de un reporte consolidado (Ventas/Compras/Notas/
  /// Desgloses) dentro de un Excel ya creado. `prefijo` distingue las hojas
  /// cuando se combinan varios reportes en un mismo archivo (ver
  /// exportReportesConsolidadosToExcel) -- los nombres de hoja en xlsx no
  /// pueden pasar de 31 caracteres, de ahí el truncado del prefijo.
  static void _escribirReporteConsolidadoEnExcel(Excel excel, Map<String, dynamic> reporte, {String prefijo = ''}) {
    final ventas = reporte['ventas'] as Map<String, dynamic>?;
    final compras = reporte['compras'] as Map<String, dynamic>?;
    final resumen = reporte['resumen_declaracion'] as Map<String, dynamic>?;
    final negocio = reporte['negocio_nombre']?.toString() ?? '';
    final periodo = [reporte['fecha_inicio'], reporte['fecha_fin']].where((x) => x != null && x.toString().isNotEmpty).join(' a ');
    final subtitulo = [if (negocio.isNotEmpty) negocio, if (periodo.isNotEmpty) 'Periodo: $periodo'].join('   ·   ');
    String fecha(dynamic v) => (v?.toString() ?? '').split('T').first;

    String nombreHoja(String base) {
      final nombre = '$prefijo$base';
      return nombre.length > 31 ? nombre.substring(0, 31) : nombre;
    }

    List<List<CellValue>> filasDesglose(List desglose) => [
          for (final d in desglose)
            [
              TextCellValue(d['tarifa']?.toString() ?? ''),
              DoubleCellValue(_numeroDe(d['base_imponible'])),
              DoubleCellValue(_numeroDe(d['monto_impuesto'])),
            ],
        ];

    if (resumen != null) {
      final hoja = excel[nombreHoja('Resumen Declaracion')];
      _escribirTabla(
        hoja,
        titulo: 'Resumen para la declaración de IVA (D-104)',
        subtitulo: subtitulo,
        seccion: 'Ventas gravadas (netas de notas de crédito)',
        encabezados: const ['Tarifa', 'Base imponible', 'IVA'],
        filas: filasDesglose((resumen['ventas_por_tarifa'] as List?) ?? []),
        moneda: const {1, 2},
        sumar: const {1, 2},
        anchos: const [44, 18, 18],
        vacio: 'Sin ventas gravadas.',
      );
      _escribirTabla(
        hoja,
        seccion: 'Compras gravadas (crédito fiscal estimado)',
        encabezados: const ['Tarifa', 'Base imponible', 'IVA'],
        filas: filasDesglose((resumen['compras_por_tarifa'] as List?) ?? []),
        moneda: const {1, 2},
        sumar: const {1, 2},
        vacio: 'Sin compras gravadas.',
      );
      hoja.appendRow([]);
      hoja.appendRow([TextCellValue('IVA A PAGAR (ventas - crédito fiscal de compras)'), TextCellValue(''), DoubleCellValue(_numeroDe(resumen['iva_a_pagar']))]);
      _estilarCeldaUltimaFila(hoja, 0, CellStyle(bold: true, fontColorHex: ExcelColor.white, backgroundColorHex: _colorMarca));
      _estilarCeldaUltimaFila(hoja, 1, CellStyle(backgroundColorHex: _colorMarca));
      _estilarCeldaUltimaFila(hoja, 2, CellStyle(bold: true, fontColorHex: ExcelColor.white, backgroundColorHex: _colorMarca, numberFormat: NumFormat.standard_4, horizontalAlign: HorizontalAlign.Right));
    }

    if (ventas != null) {
      final documentos = (ventas['documentos'] as List?) ?? [];
      _escribirTabla(
        excel[nombreHoja('Ventas')],
        titulo: 'Ventas (${documentos.length} documento(s))',
        subtitulo: subtitulo,
        encabezados: const ['Fecha', 'Documento', 'Tipo', 'Cliente', 'Base', 'IVA', 'Total'],
        filas: [
          for (final f in documentos)
            [
              TextCellValue(fecha(f['fecha'])),
              TextCellValue(f['consecutivo']?.toString() ?? ''),
              TextCellValue(f['tipo_documento']?.toString() ?? ''),
              TextCellValue(f['cliente']?.toString() ?? ''),
              DoubleCellValue(_numeroDe(f['subtotal'])),
              DoubleCellValue(_numeroDe(f['monto_iva'])),
              DoubleCellValue(_numeroDe(f['total'])),
            ],
        ],
        moneda: const {4, 5, 6},
        sumar: const {4, 5, 6},
        vacio: 'Sin ventas en este periodo.',
      );

      final notasCredito = (ventas['notas_credito'] as List?) ?? [];
      if (notasCredito.isNotEmpty) {
        _escribirTabla(
          excel[nombreHoja('Notas de Credito')],
          titulo: 'Notas de crédito (${notasCredito.length})',
          subtitulo: subtitulo,
          encabezados: const ['Fecha', 'N.°', 'Anula factura', 'Motivo', 'Base', 'IVA', 'Total'],
          filas: [
            for (final n in notasCredito)
              [
                TextCellValue(fecha(n['fecha'])),
                TextCellValue(n['consecutivo']?.toString() ?? ''),
                TextCellValue(n['factura_anulada']?.toString() ?? ''),
                TextCellValue(n['motivo']?.toString() ?? ''),
                DoubleCellValue(_numeroDe(n['subtotal'])),
                DoubleCellValue(_numeroDe(n['monto_iva'])),
                DoubleCellValue(_numeroDe(n['total'])),
              ],
          ],
          moneda: const {4, 5, 6},
          sumar: const {4, 5, 6},
        );
      }

      final desglose = (ventas['desglose_impuestos'] as List?) ?? [];
      if (desglose.isNotEmpty) {
        _escribirTabla(
          excel[nombreHoja('Desglose IVA Ventas')],
          titulo: 'Desglose de IVA de ventas por tarifa',
          subtitulo: subtitulo,
          encabezados: const ['Tarifa', 'Base imponible', 'IVA'],
          filas: filasDesglose(desglose),
          moneda: const {1, 2},
          sumar: const {1, 2},
          anchos: const [24, 18, 18],
        );
      }
    }

    if (compras != null) {
      final documentos = (compras['documentos'] as List?) ?? [];
      _escribirTabla(
        excel[nombreHoja('Compras')],
        titulo: 'Compras (${documentos.length} documento(s))',
        subtitulo: subtitulo,
        encabezados: const ['Fecha', 'Proveedor', 'N.° factura proveedor', 'Base (est.)', 'IVA (est.)', 'Total'],
        filas: [
          for (final c in documentos)
            [
              TextCellValue(fecha(c['fecha'])),
              TextCellValue(c['proveedor']?.toString() ?? ''),
              TextCellValue(c['numero_factura_proveedor']?.toString() ?? ''),
              DoubleCellValue(_numeroDe(c['subtotal_estimado'])),
              DoubleCellValue(_numeroDe(c['monto_iva_estimado'])),
              DoubleCellValue(_numeroDe(c['total'])),
            ],
        ],
        moneda: const {3, 4, 5},
        sumar: const {3, 4, 5},
        vacio: 'Sin compras en este periodo.',
      );

      final notasDebito = (compras['notas_debito'] as List?) ?? [];
      if (notasDebito.isNotEmpty) {
        _escribirTabla(
          excel[nombreHoja('Notas de Debito')],
          titulo: 'Notas de débito de proveedores (${notasDebito.length})',
          subtitulo: subtitulo,
          encabezados: const ['Fecha', 'N.°', 'Proveedor', 'Motivo', 'Monto'],
          filas: [
            for (final n in notasDebito)
              [
                TextCellValue(fecha(n['fecha'])),
                TextCellValue(n['numero_documento']?.toString() ?? ''),
                TextCellValue(n['proveedor']?.toString() ?? ''),
                TextCellValue(n['motivo']?.toString() ?? ''),
                DoubleCellValue(_numeroDe(n['monto'])),
              ],
          ],
          moneda: const {4},
          sumar: const {4},
        );
      }

      final desglose = (compras['desglose_impuestos'] as List?) ?? [];
      if (desglose.isNotEmpty) {
        final hoja = excel[nombreHoja('Desglose IVA Compras')];
        _escribirTabla(
          hoja,
          titulo: 'Desglose de IVA de compras por tarifa (estimado)',
          subtitulo: subtitulo,
          encabezados: const ['Tarifa', 'Base imponible', 'IVA'],
          filas: filasDesglose(desglose),
          moneda: const {1, 2},
          sumar: const {1, 2},
          anchos: const [24, 18, 18],
        );
        final nota = compras['nota_desglose']?.toString() ?? '';
        if (nota.isNotEmpty) {
          hoja.appendRow([]);
          hoja.appendRow([TextCellValue(nota)]);
          _estilarCeldaUltimaFila(hoja, 0, CellStyle(italic: true, fontSize: 9, fontColorHex: ExcelColor.fromHexString('FF6B7280')));
        }
      }
    }
  }

  /// Exporta el listado general de Cuentas por Cobrar a PDF
  static Future<void> exportSaldosToPdf(List<Map<String, dynamic>> saldos, String negocioNombre) async {
    final pdf = pw.Document(theme: await _cargarTema());
    pdf.addPage(pw.MultiPage(
      pageTheme: _temaPagina(),
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
    excel['Dashboard']; // primera pestaña (ver _escribirDashboard)
    final ordenados = [...saldos]..sort((a, b) => _numeroDe(b['saldo']).compareTo(_numeroDe(a['saldo'])));
    _escribirTabla(
      excel['Saldos'],
      titulo: 'Cuentas por cobrar',
      subtitulo: '${saldos.length} cliente(s), de mayor a menor saldo',
      encabezados: const ['Cliente', 'Cédula', 'Saldo pendiente'],
      filas: [
        for (final item in ordenados)
          [
            TextCellValue(item['nombre']?.toString() ?? ''),
            TextCellValue(item['cedula']?.toString() ?? ''),
            DoubleCellValue(_numeroDe(item['saldo'])),
          ],
      ],
      moneda: const {2},
      sumar: const {2},
    );

    {
      double n(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;
      final conSaldo = saldos.where((x) => n(x['saldo']) > 0).toList();
      final total = conSaldo.fold(0.0, (a, x) => a + n(x['saldo']));
      final mayor = conSaldo.fold(0.0, (a, x) => n(x['saldo']) > a ? n(x['saldo']) : a);
      _escribirDashboard(
        excel,
        titulo: 'Dashboard de cuentas por cobrar',
        indicadores: [
          ('Total por cobrar', total, 'moneda', null),
          ('Clientes con saldo', conSaldo.length.toDouble(), 'numero', null),
          ('Saldo promedio', _div(total, conSaldo.length.toDouble()), 'moneda', 'Por cliente con saldo'),
          ('Concentración del mayor', _div(mayor, total), 'porcentaje', 'Peso del cliente que más debe'),
        ],
        graficos: [
          ('Saldo pendiente por cliente', _agrupar<Map<String, dynamic>>(conSaldo, (x) => x['nombre']?.toString() ?? '', (x) => n(x['saldo'])), 'moneda'),
        ],
      );
    }
    _dashboardPrimero(excel);

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
      pageTheme: _temaPagina(),
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
    excel['Dashboard']; // primera pestaña (ver _escribirDashboard)
    var saldoAcumulado = 0.0;
    _escribirTabla(
      excel['Historial'],
      titulo: 'Estado de cuenta · $clienteNombre',
      subtitulo: '${historial.length} movimiento(s)',
      encabezados: const ['Fecha', 'Tipo', 'Detalle', 'Cargo', 'Abono', 'Saldo'],
      filas: [
        for (final item in historial)
          () {
            final esFactura = item['tipo'] == 'FACTURA';
            final monto = _numeroDe(item['monto']);
            saldoAcumulado += esFactura ? monto : -monto;
            return <CellValue>[
              TextCellValue(item['fecha']?.toString() ?? ''),
              TextCellValue(esFactura ? 'Factura' : 'Abono'),
              TextCellValue(esFactura ? 'F-${item['numero']}' : 'Recibo de abono'),
              DoubleCellValue(esFactura ? monto : 0),
              DoubleCellValue(esFactura ? 0 : monto),
              DoubleCellValue(saldoAcumulado),
            ];
          }(),
      ],
      moneda: const {3, 4, 5},
      sumar: const {3, 4},
    );

    {
      double n(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;
      final facturado = historial.where((x) => x['tipo'] == 'FACTURA').fold(0.0, (a, x) => a + n(x['monto']));
      final abonado = historial.where((x) => x['tipo'] != 'FACTURA').fold(0.0, (a, x) => a + n(x['monto']));
      _escribirDashboard(
        excel,
        titulo: 'Estado de cuenta · $clienteNombre',
        indicadores: [
          ('Total facturado', facturado, 'moneda', null),
          ('Total abonado', abonado, 'moneda', null),
          ('Saldo pendiente', facturado - abonado, 'moneda', null),
          ('Cobrado', _div(abonado, facturado), 'porcentaje', 'Del total facturado'),
        ],
        graficos: [
          ('Facturado vs. abonado', {'Facturado': facturado, 'Abonado': abonado, 'Saldo pendiente': facturado - abonado}, 'moneda'),
          ('Movimientos por mes', _agrupar<dynamic>(historial, (x) => _mesCorto(x['fecha']?.toString() ?? ''), (x) => n(x['monto'])), 'moneda'),
        ],
      );
    }
    _dashboardPrimero(excel);

    await _guardarExcel(excel, dialogTitle: 'Guardar Historial de $clienteNombre', fileName: 'historial_${clienteNombre.replaceAll(' ', '_')}.xlsx');
  }

  /// Exporta (o comparte) una factura individual con su detalle de productos
  static Future<void> exportFacturaDetalleToPdf(Factura factura, {bool share = false, List<NotaCredito> notasCredito = const []}) async {
    final pdf = pw.Document(theme: await _cargarTema());
    final subtotal = factura.totalFactura - factura.totalIva;
    // AUDITORIA.md hallazgo A3 -- suma de los descuentos por línea, en
    // colones igual que el resto (se convierte más abajo junto con todo lo
    // demás cuando la factura es en dólares).
    final totalDescuentoColones = factura.detalles.fold(0.0, (s, d) => s + d.montoDescuento);
    final totalExoneradoColones = factura.detalles.fold(0.0, (s, d) => s + d.montoExoneracion);
    final logo = await _cargarLogo(factura.logoNegocioUrl);
    final subtotalAcreditado = notasCredito.fold(0.0, (s, n) => s + n.subtotal);
    final ivaAcreditado = notasCredito.fold(0.0, (s, n) => s + n.montoIva);
    final totalAcreditado = subtotalAcreditado + ivaAcreditado;
    // DetalleFactura/totales siempre están en colones (ver Factura.moneda);
    // si esta factura se emitió en dólares, se convierte acá para que el
    // PDF que se descarga/comparte muestre la moneda real del comprobante,
    // igual que ya hace el XML/Alanube al enviarla a Hacienda.
    final esUsd = factura.moneda == 'USD' && factura.tipoCambio > 0;
    final factorMoneda = esUsd ? 1 / factura.tipoCambio : 1.0;
    String fmt(num v) => esUsd ? formatearDolares(v * factorMoneda) : formatearColones(v * factorMoneda);

    pdf.addPage(pw.MultiPage(
      pageTheme: _temaPagina(),
      build: (pw.Context context) => [
        _encabezadoDocumento(
          info: factura.negocioInfo,
          nombreNegocio: factura.nombreNegocio,
          logo: logo,
          titulo: factura.esInterno
              ? 'TIQUETE INTERNO (NO FISCAL)'
              : (factura.esTiquete ? 'TIQUETE ELECTRÓNICO' : 'FACTURA ELECTRÓNICA'),
          datos: [
            'N.° ${factura.consecutivo}',
            'Fecha: ${factura.fechaEmision.split('T')[0]}',
            'Condición: ${factura.condicionVenta == "02" ? 'Crédito' : 'Contado'}',
            if (esUsd) 'Dólares (US\$) · T.C. ${formatearColones(factura.tipoCambio)}',
          ],
          color: PdfColors.indigo,
        ),
        pw.SizedBox(height: 14),
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
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo),
          cellStyle: const pw.TextStyle(fontSize: 10),
          cellAlignment: pw.Alignment.centerLeft,
          // Sin esto las 5 columnas se repartían en partes iguales: el
          // nombre del producto se comía el ancho que necesitaban los
          // montos, y esos números terminaban partiéndose en dos líneas
          // (se veía "descuadrado" -- cada fila con distinta altura).
          columnWidths: const {
            0: pw.FlexColumnWidth(3),
            1: pw.FlexColumnWidth(1),
            2: pw.FlexColumnWidth(1.8),
            3: pw.FlexColumnWidth(1.5),
            4: pw.FlexColumnWidth(1.8),
          },
          cellAlignments: const {
            1: pw.Alignment.center,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
          },
          headers: const ['Producto', 'Cant', 'Precio Unit.', 'IVA', 'Total'],
          data: factura.detalles.isEmpty
              ? [
                  ['Sin detalle de líneas registrado.', '', '', '', ''],
                ]
              : factura.detalles.map((d) => [
                    d.nombreProducto,
                    d.cantidad.toString(),
                    fmt(d.precioUnitario),
                    fmt(d.montoIva),
                    fmt(d.total),
                  ]).toList(),
        ),
        pw.SizedBox(height: 20),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              if (totalDescuentoColones > 0) ...[
                pw.Text('Subtotal bruto: ${fmt(subtotal + totalDescuentoColones)}'),
                pw.Text('Descuento: -${fmt(totalDescuentoColones)}', style: const pw.TextStyle(color: PdfColors.green800)),
              ],
              pw.Text('Subtotal: ${fmt(subtotal)}'),
              if (totalExoneradoColones > 0)
                pw.Text('IVA exonerado: -${fmt(totalExoneradoColones)}', style: const pw.TextStyle(color: PdfColors.green800)),
              pw.Text('IVA: ${fmt(factura.totalIva)}'),
              pw.SizedBox(width: 180, child: pw.Divider()),
              pw.Text(
                notasCredito.isEmpty ? 'TOTAL: ${fmt(factura.totalFactura)}' : 'Total Factura Original: ${fmt(factura.totalFactura)}',
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
                        cellAlignment: pw.Alignment.centerLeft,
                        columnWidths: const {
                          0: pw.FlexColumnWidth(3),
                          1: pw.FlexColumnWidth(1),
                          2: pw.FlexColumnWidth(1.8),
                          3: pw.FlexColumnWidth(1.5),
                          4: pw.FlexColumnWidth(1.8),
                        },
                        cellAlignments: const {
                          1: pw.Alignment.center,
                          2: pw.Alignment.centerRight,
                          3: pw.Alignment.centerRight,
                          4: pw.Alignment.centerRight,
                        },
                        headers: const ['Producto', 'Cant', 'Precio Unit.', 'IVA', 'Total'],
                        data: n.detalles.map((d) => [
                              d.nombreProducto,
                              d.cantidad.toString(),
                              fmt(d.precioUnitario),
                              fmt(d.montoIva),
                              fmt(d.total),
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
                            pw.Text('Subtotal: -${fmt(n.subtotal)}', style: const pw.TextStyle(color: PdfColors.red900, fontSize: 10)),
                            pw.Text('IVA: -${fmt(n.montoIva)}', style: const pw.TextStyle(color: PdfColors.red900, fontSize: 10)),
                            pw.Text('Total NC: -${fmt(n.total)}', style: pw.TextStyle(color: PdfColors.red900, fontSize: 12, fontWeight: pw.FontWeight.bold)),
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
                pw.Text('Subtotal neto: ${fmt(subtotal - subtotalAcreditado)}'),
                pw.Text('IVA neto: ${fmt(factura.totalIva - ivaAcreditado)}'),
                pw.SizedBox(width: 180, child: pw.Divider()),
                pw.Text(
                  'TOTAL NETO: ${fmt(factura.totalFactura - totalAcreditado)}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16, color: PdfColors.indigo),
                ),
              ],
            ),
          ),
        ],
        _piePagina(),
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
      pageTheme: _temaPagina(),
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
        pageTheme: _temaPagina(),
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
        pageTheme: _temaPagina(),
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
        pageTheme: _temaPagina(),
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
        pageTheme: _temaPagina(),
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
        pageTheme: _temaPagina(),
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
          ..._seccionDolaresPdf('Facturas', 'Cliente', [for (final f in facturas) ('F-${f.consecutivo}', f.fechaEmision.split('T')[0], f.receptorNombre, _usdFactura(f))], color: PdfColors.teal800),
          ..._seccionDolaresPdf('Notas de crédito', 'Cliente', [for (final n in notasCredito) (n.consecutivo, n.fechaEmision.split('T')[0], n.receptorNombre, _usdNota(n))], color: PdfColors.teal800),
          ..._seccionDolaresPdf('Compras', 'Proveedor', [for (final c in compras) (c.numeroFacturaProveedor.isNotEmpty ? c.numeroFacturaProveedor : 'Compra', c.fechaCompra.split('T')[0], c.nombreProveedor ?? 'Sin especificar', _usdCompra(c))], color: PdfColors.teal800),
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
    excel['Dashboard']; // primera pestaña (ver _escribirDashboard)

    final resumen = excel['Resumen'];
    excel.setDefaultSheet('Resumen');
    _anchoColumnas(resumen, [32, 18, 18]);

    resumen.appendRow([TextCellValue('Declaración de IVA - $negocioNombre')]);
    _estilarCeldaUltimaFila(resumen, 0, _estiloTitulo());
    resumen.appendRow([TextCellValue('Periodo: $periodo')]);
    _estilarCeldaUltimaFila(resumen, 0, _estiloSubtitulo());
    resumen.appendRow([]);

    resumen.appendRow([TextCellValue('Concepto'), TextCellValue('Monto')]);
    _estilarUltimaFila(resumen, 2, _estiloEncabezadoTabla());
    for (final fila in [
      ['Ventas gravadas', numDe('ventas_gravadas'), false],
      ['IVA de ventas (débito fiscal)', numDe('debito_fiscal'), false],
      ['Compras netas', numDe('compras_totales'), false],
      ['IVA de compras estimado (crédito fiscal)', numDe('credito_fiscal'), false],
      ['Saldo del periodo', numDe('saldo_iva'), true],
    ]) {
      resumen.appendRow([TextCellValue(fila[0] as String), DoubleCellValue(fila[1] as double)]);
      if (fila[2] as bool) {
        _estilarCeldaUltimaFila(resumen, 0, _estiloTotalTexto());
        _estilarCeldaUltimaFila(resumen, 1, _estiloTotalMoneda());
      } else {
        _estilarCeldaUltimaFila(resumen, 1, _estiloMoneda());
      }
    }
    resumen.appendRow([]);

    void tablaPorTarifa(String titulo, List tarifas) {
      resumen.appendRow([TextCellValue(titulo)]);
      _estilarCeldaUltimaFila(resumen, 0, _estiloEncabezadoSeccion());
      resumen.appendRow([TextCellValue('Tarifa'), TextCellValue('Base'), TextCellValue('IVA')]);
      _estilarUltimaFila(resumen, 3, _estiloEncabezadoTabla());
      for (final t in tarifas) {
        resumen.appendRow([
          TextCellValue('${t['tarifa']}%'),
          DoubleCellValue(double.tryParse(t['base'].toString()) ?? 0),
          DoubleCellValue(double.tryParse(t['iva'].toString()) ?? 0),
        ]);
        _estilarCeldaUltimaFila(resumen, 1, _estiloMoneda());
        _estilarCeldaUltimaFila(resumen, 2, _estiloMoneda());
      }
      resumen.appendRow([]);
    }

    tablaPorTarifa('Débito fiscal por tarifa', (declaracion['debito_por_tarifa'] as List?) ?? []);
    tablaPorTarifa('Crédito fiscal por tarifa', (declaracion['credito_por_tarifa'] as List?) ?? []);

    final hojaFacturas = excel['Facturas'];
    final facturasUsd = facturas.any((f) => _esUsd(_usdFactura(f)));
    _anchoColumnas(hojaFacturas, [14, 12, 28, 14, 12, 15, 13, 15, 16, if (facturasUsd) ...[9, 13, 14, 12, 14]]);
    hojaFacturas.appendRow([
      TextCellValue('Consecutivo'), TextCellValue('Fecha'), TextCellValue('Cliente'), TextCellValue('Cédula'),
      TextCellValue('Condición'), TextCellValue('Subtotal'), TextCellValue('IVA'), TextCellValue('Total'), TextCellValue('Estado'),
      if (facturasUsd) ..._encabezadosUsd.map((e) => TextCellValue(e)),
    ]);
    _estilarUltimaFila(hojaFacturas, facturasUsd ? 14 : 9, _estiloEncabezadoTabla());
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
        if (facturasUsd) ..._celdasUsd(_usdFactura(f)),
      ]);
      for (final col in [5, 6, 7]) {
        _estilarCeldaUltimaFila(hojaFacturas, col, _estiloMoneda());
      }
      if (facturasUsd) _estilarUsdUltimaFila(hojaFacturas, 9);
    }
    hojaFacturas.appendRow([]);
    hojaFacturas.appendRow([
      TextCellValue('TOTAL'), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''),
      DoubleCellValue(facturas.fold(0.0, (s, f) => s + (f.totalFactura - f.totalIva))),
      DoubleCellValue(facturas.fold(0.0, (s, f) => s + f.totalIva)),
      DoubleCellValue(facturas.fold(0.0, (s, f) => s + f.totalFactura)),
      TextCellValue(''),
      if (facturasUsd) ..._totalesUsd(facturas.map(_usdFactura)),
    ]);
    _estilarCeldaUltimaFila(hojaFacturas, 0, _estiloTotalTexto());
    for (final col in [5, 6, 7]) {
      _estilarCeldaUltimaFila(hojaFacturas, col, _estiloTotalMoneda());
    }
    if (facturasUsd) _estilarUsdUltimaFila(hojaFacturas, 9, total: true);

    final hojaNotas = excel['Notas de Credito'];
    final notasUsd = notasCredito.any((n) => _esUsd(_usdNota(n)));
    _anchoColumnas(hojaNotas, [14, 12, 16, 28, 15, 13, 15, if (notasUsd) ...[9, 13, 14, 12, 14]]);
    hojaNotas.appendRow([
      TextCellValue('Consecutivo'), TextCellValue('Fecha'), TextCellValue('Anula Factura'),
      TextCellValue('Cliente'), TextCellValue('Subtotal'), TextCellValue('IVA'), TextCellValue('Total'),
      if (notasUsd) ..._encabezadosUsd.map((e) => TextCellValue(e)),
    ]);
    _estilarUltimaFila(hojaNotas, notasUsd ? 12 : 7, _estiloEncabezadoTabla());
    for (final n in notasCredito) {
      hojaNotas.appendRow([
        TextCellValue(n.consecutivo),
        TextCellValue(n.fechaEmision.split('T').first),
        TextCellValue('F-${n.facturaConsecutivo ?? ''}'),
        TextCellValue(n.receptorNombre),
        DoubleCellValue(n.subtotal),
        DoubleCellValue(n.montoIva),
        DoubleCellValue(n.total),
        if (notasUsd) ..._celdasUsd(_usdNota(n)),
      ]);
      for (final col in [4, 5, 6]) {
        _estilarCeldaUltimaFila(hojaNotas, col, _estiloMoneda());
      }
      if (notasUsd) _estilarUsdUltimaFila(hojaNotas, 7);
    }

    final hojaCompras = excel['Compras'];
    final comprasUsd = compras.any((c) => _esUsd(_usdCompra(c)));
    _anchoColumnas(hojaCompras, [28, 12, 22, 15, if (comprasUsd) ...[9, 13, 14, 12, 14]]);
    hojaCompras.appendRow([
      TextCellValue('Proveedor'), TextCellValue('Fecha'), TextCellValue('N° Factura Proveedor'), TextCellValue('Total'),
      if (comprasUsd) ..._encabezadosUsd.map((e) => TextCellValue(e)),
    ]);
    _estilarUltimaFila(hojaCompras, comprasUsd ? 9 : 4, _estiloEncabezadoTabla());
    for (final c in compras) {
      hojaCompras.appendRow([
        TextCellValue(c.nombreProveedor ?? 'Sin especificar'),
        TextCellValue(c.fechaCompra.split('T').first),
        TextCellValue(c.numeroFacturaProveedor),
        DoubleCellValue(c.totalCompra),
        if (comprasUsd) ..._celdasUsd(_usdCompra(c)),
      ]);
      _estilarCeldaUltimaFila(hojaCompras, 3, _estiloMoneda());
      if (comprasUsd) _estilarUsdUltimaFila(hojaCompras, 4);
    }
    hojaCompras.appendRow([]);
    hojaCompras.appendRow([
      TextCellValue('TOTAL'), TextCellValue(''), TextCellValue(''), DoubleCellValue(compras.fold(0.0, (s, c) => s + c.totalCompra)),
      if (comprasUsd) ..._totalesUsd(compras.map(_usdCompra)),
    ]);
    _estilarCeldaUltimaFila(hojaCompras, 0, _estiloTotalTexto());
    _estilarCeldaUltimaFila(hojaCompras, 3, _estiloTotalMoneda());
    if (comprasUsd) _estilarUsdUltimaFila(hojaCompras, 4, total: true);

    excel.delete('Sheet1');


    {
      double t(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;
      final debito = numDe('debito_fiscal');
      final creditoF = numDe('credito_fiscal');
      _escribirDashboard(
        excel,
        titulo: 'Dashboard de IVA · $negocioNombre',
        subtitulo: 'Periodo: $periodo',
        indicadores: [
          ('Débito fiscal', debito, 'moneda', 'IVA de tus ventas'),
          ('Crédito fiscal', creditoF, 'moneda', 'IVA de tus compras'),
          (declaracion['a_pagar'] == true ? 'IVA a pagar' : 'Saldo a favor', numDe('saldo_iva').abs(), 'moneda', null),
          ('Crédito sobre débito', _div(creditoF, debito), 'porcentaje', 'Cuánto del IVA cobrado compensás'),
          ('Ventas gravadas', numDe('ventas_gravadas'), 'moneda', null),
          ('Compras totales', numDe('compras_totales'), 'moneda', null),
          ('Facturas', facturas.length.toDouble(), 'numero', '${notasCredito.length} nota(s) de crédito'),
          ('Compras', compras.length.toDouble(), 'numero', null),
        ],
        graficos: [
          ('Débito fiscal por tarifa', {for (final x in (declaracion['debito_por_tarifa'] as List?) ?? []) '${x['tarifa']}%': t(x['iva'])}, 'moneda'),
          ('Crédito fiscal por tarifa', {for (final x in (declaracion['credito_por_tarifa'] as List?) ?? []) '${x['tarifa']}%': t(x['iva'])}, 'moneda'),
          ('Ventas por cliente', _agrupar<Factura>(facturas, (f) => f.receptorNombre, (f) => f.totalFactura), 'moneda'),
          ('Compras por proveedor', _agrupar<Compra>(compras, (c) => c.nombreProveedor ?? '', (c) => c.totalCompra), 'moneda'),
        ],
      );
    }
    _dashboardPrimero(excel);

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
        pageTheme: _temaPagina(),
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
          ..._seccionDolaresPdf('Facturas', 'Cliente', [for (final f in facturas) ('F-${f.consecutivo}', f.fechaEmision.split('T')[0], f.receptorNombre, _usdFactura(f))], color: PdfColors.deepPurple800),
          ..._seccionDolaresPdf('Compras', 'Proveedor', [for (final c in compras) (c.numeroFacturaProveedor.isNotEmpty ? c.numeroFacturaProveedor : 'Compra', c.fechaCompra.split('T')[0], c.nombreProveedor ?? 'Sin especificar', _usdCompra(c))], color: PdfColors.deepPurple800),
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
    excel['Dashboard']; // primera pestaña (ver _escribirDashboard)
    final facturasUsd = facturas.any((f) => _esUsd(_usdFactura(f)));
    final comprasUsd = compras.any((c) => _esUsd(_usdCompra(c)));

    final resumen = excel['Resumen'];
    _escribirTabla(
      resumen,
      titulo: 'Declaración de Renta (D-101) · $negocioNombre',
      subtitulo: 'Periodo fiscal $periodoFiscal',
      encabezados: const ['Concepto', 'Monto'],
      filas: [
        [TextCellValue('Ingresos brutos (ventas)'), DoubleCellValue(numDe('ingresos_brutos'))],
        [TextCellValue('(-) Costo de ventas (compras)'), DoubleCellValue(numDe('costo_ventas'))],
        [TextCellValue('(-) Gastos deducibles'), DoubleCellValue(numDe('gastos_deducibles'))],
        [TextCellValue('Gastos no deducibles (no restan)'), DoubleCellValue(numDe('gastos_no_deducibles'))],
      ],
      moneda: const {1},
      anchos: const [40, 20, 16, 20],
    );
    for (final (concepto, clave) in const [('Renta líquida gravable', 'renta_liquida_gravable'), ('Impuesto estimado', 'impuesto_estimado')]) {
      resumen.appendRow([TextCellValue(concepto), DoubleCellValue(numDe(clave))]);
      _estilarCeldaUltimaFila(resumen, 0, _estiloTotalTexto());
      _estilarCeldaUltimaFila(resumen, 1, _estiloTotalMoneda());
    }
    final tramos = (declaracion['desglose_tramos'] as List?) ?? [];
    if (tramos.isNotEmpty) {
      _escribirTabla(
        resumen,
        seccion: 'Cálculo por tramo',
        encabezados: const ['Desde', 'Hasta', 'Tarifa', 'Impuesto'],
        filas: [
          for (final t in tramos)
            [
              DoubleCellValue(_numeroDe(t['desde'])),
              t['hasta'] == null ? TextCellValue('En adelante') : DoubleCellValue(_numeroDe(t['hasta'])),
              TextCellValue('${t['porcentaje']}%'),
              DoubleCellValue(_numeroDe(t['impuesto_tramo'])),
            ],
        ],
        moneda: const {0, 1, 3},
        sumar: const {3},
      );
    }

    _escribirTabla(
      excel['Facturas'],
      titulo: 'Facturas del periodo fiscal $periodoFiscal',
      subtitulo: negocioNombre,
      encabezados: ['Consecutivo', 'Fecha', 'Cliente', 'Subtotal', 'IVA', 'Total', if (facturasUsd) ..._encabezadosUsd],
      filas: [
        for (final f in facturas)
          [
            TextCellValue('F-${f.consecutivo}'),
            TextCellValue(f.fechaEmision.split('T').first),
            TextCellValue(f.receptorNombre),
            DoubleCellValue(f.totalFactura - f.totalIva),
            DoubleCellValue(f.totalIva),
            DoubleCellValue(f.totalFactura),
            if (facturasUsd) ..._celdasUsd(_usdFactura(f)),
          ],
      ],
      moneda: {3, 4, 5, if (facturasUsd) 7},
      dolares: {if (facturasUsd) ...{8, 9, 10}},
      sumar: {3, 4, 5, if (facturasUsd) ...{8, 9, 10}},
    );

    _escribirTabla(
      excel['Compras'],
      titulo: 'Compras del periodo fiscal $periodoFiscal',
      subtitulo: negocioNombre,
      encabezados: ['Proveedor', 'Fecha', 'N.° factura proveedor', 'Total', if (comprasUsd) ..._encabezadosUsd],
      filas: [
        for (final c in compras)
          [
            TextCellValue(c.nombreProveedor ?? 'Sin especificar'),
            TextCellValue(c.fechaCompra.split('T').first),
            TextCellValue(c.numeroFacturaProveedor),
            DoubleCellValue(c.totalCompra),
            if (comprasUsd) ..._celdasUsd(_usdCompra(c)),
          ],
      ],
      moneda: {3, if (comprasUsd) 5},
      dolares: {if (comprasUsd) ...{6, 7, 8}},
      sumar: {3, if (comprasUsd) ...{6, 7, 8}},
    );

    final hojaGastos = excel['Gastos'];
    _escribirTabla(
      hojaGastos,
      titulo: 'Gastos del periodo fiscal $periodoFiscal',
      subtitulo: negocioNombre,
      encabezados: const ['Fecha', 'Categoría', 'Descripción', 'Deducible', 'Monto'],
      filas: [
        for (final g in gastos)
          [
            TextCellValue(g.fecha),
            TextCellValue(g.categoriaLabel),
            TextCellValue(g.descripcion),
            TextCellValue(g.deducible ? 'Sí' : 'No'),
            DoubleCellValue(g.monto),
          ],
      ],
      moneda: const {4},
      sumar: const {4},
    );
    if (gastos.isNotEmpty) {
      hojaGastos.appendRow([
        TextCellValue('Deducible para Renta'), TextCellValue(''), TextCellValue(''), TextCellValue(''),
        DoubleCellValue(gastos.where((g) => g.deducible).fold(0.0, (s, g) => s + g.monto)),
      ]);
      _estilarCeldaUltimaFila(hojaGastos, 0, CellStyle(bold: true, fontColorHex: _colorMarca));
      _estilarCeldaUltimaFila(hojaGastos, 4, _estiloMoneda(negrita: true));
    }

    excel.delete('Sheet1');


    {
      double t(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;
      final ingresos = numDe('ingresos_brutos');
      final costo = numDe('costo_ventas');
      final gastos = numDe('gastos_deducibles');
      final renta = numDe('renta_liquida_gravable');
      _escribirDashboard(
        excel,
        titulo: 'Dashboard de Renta · $negocioNombre',
        subtitulo: 'Periodo fiscal: $periodoFiscal',
        indicadores: [
          ('Ingresos brutos', ingresos, 'moneda', null),
          ('Costo de ventas', costo, 'moneda', null),
          ('Gastos deducibles', gastos, 'moneda', null),
          ('Renta líquida gravable', renta, 'moneda', null),
          ('Margen neto', _div(renta, ingresos), 'porcentaje', 'Renta líquida / ingresos'),
          ('Impuesto estimado', numDe('impuesto_estimado'), 'moneda', null),
          ('Tasa efectiva', _div(numDe('impuesto_estimado'), renta), 'porcentaje', 'Impuesto / renta líquida'),
          ('Gastos no deducibles', numDe('gastos_no_deducibles'), 'moneda', null),
        ],
        graficos: [
          ('¿A dónde van tus ingresos?', {'Costo de ventas': costo, 'Gastos deducibles': gastos, 'Renta líquida': renta < 0 ? 0 : renta}, 'moneda'),
          ('Gastos deducibles por categoría', {for (final g in (declaracion['gastos_por_categoria'] as List?) ?? []) (_categoriasGastoPdf[g['categoria']] ?? g['categoria'].toString()): t(g['total'])}, 'moneda'),
          ('Ventas por cliente', _agrupar<Factura>(facturas, (f) => f.receptorNombre, (f) => f.totalFactura), 'moneda'),
        ],
      );
    }
    _dashboardPrimero(excel);

    await _guardarExcel(excel, dialogTitle: 'Guardar Declaración de Renta (Excel)', fileName: 'Declaracion_Renta_Detalle_$periodoFiscal.xlsx');
  }

  // =====================================================================
  // REPORTE DE RENTA (D-101) DEL CONTADOR -- uno o varios clientes de la
  // cartera. Cada elemento de [rentas] es la respuesta de
  // /facturas/declaracion-renta/ (ver calcular_declaracion_renta en el
  // backend), que trae además los datos del contribuyente (del perfil del
  // negocio), el detalle mes a mes y el año anterior.
  // =====================================================================

  static const _mesesLargos = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Setiembre', 'Octubre', 'Noviembre', 'Diciembre'];

  static double _nr(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;

  static String _nombreRenta(Map<String, dynamic> r) =>
      ((r['contribuyente'] as Map?)?['nombre_comercial'] ?? r['negocio_nombre'] ?? 'Cliente').toString();

  /// Tasa efectiva: impuesto / renta líquida gravable (0 si no hay renta).
  static double _tasaEfectiva(Map<String, dynamic> r) => _div(_nr(r['impuesto_estimado']), _nr(r['renta_liquida_gravable']));

  static Future<void> exportRentaContadorToPdf(List<Map<String, dynamic>> rentas, int anio) async {
    final pdf = pw.Document(theme: await _cargarTema());
    const indigo = PdfColor.fromInt(0xFF3730A3);
    const gris = PdfColors.grey700;

    pw.Widget titulo(String t) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
          child: pw.Text(t, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: indigo)),
        );

    pw.Widget tabla(List<String> encabezados, List<List<String>> filas, {List<int> numericas = const [], List<String>? total}) {
      final alineacion = {for (final c in numericas) c: pw.Alignment.centerRight};
      return pw.TableHelper.fromTextArray(
        headers: encabezados,
        data: [...filas, if (total != null) total],
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9.5),
        headerDecoration: const pw.BoxDecoration(color: indigo),
        cellStyle: const pw.TextStyle(fontSize: 9.5),
        cellAlignments: alineacion,
        headerAlignments: alineacion,
        oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF5F7FF)),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      );
    }

    List<pw.Widget> paginaCliente(Map<String, dynamic> r) {
      final c = (r['contribuyente'] as Map?) ?? {};
      final ingresos = _nr(r['ingresos_brutos']);
      final costo = _nr(r['costo_ventas']);
      final gastos = _nr(r['gastos_deducibles']);
      final renta = _nr(r['renta_liquida_gravable']);
      final impuesto = _nr(r['impuesto_estimado']);
      final anterior = (r['anio_anterior'] as Map?) ?? {};
      final detalle = (r['ingresos_detalle'] as Map?) ?? {};
      final tramos = (r['desglose_tramos'] as List?) ?? [];
      final porCategoria = (r['gastos_por_categoria'] as List?) ?? [];
      final mensual = (r['mensual'] as List?) ?? [];
      String campo(String k) => (c[k]?.toString() ?? '').trim();

      return [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Declaración de Renta (D-101)', style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold, color: indigo)),
                  pw.Text('Borrador para revisión del contador', style: const pw.TextStyle(fontSize: 10, color: gris)),
                ],
              ),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFEEF2FF), borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Text('Periodo fiscal $anio', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: indigo)),
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        // --- Datos del contribuyente
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(campo('nombre_legal').isNotEmpty ? campo('nombre_legal') : _nombreRenta(r),
                  style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold)),
              if (campo('nombre_legal').isNotEmpty && campo('nombre_legal') != campo('nombre_comercial'))
                pw.Text('Nombre comercial: ${campo('nombre_comercial')}', style: const pw.TextStyle(fontSize: 9.5, color: gris)),
              pw.SizedBox(height: 3),
              pw.Text('Cédula ${campo('tipo_cedula').toLowerCase()}: ${campo('cedula')}   ·   ${campo('tipo_contribuyente')}',
                  style: const pw.TextStyle(fontSize: 9.5)),
              if (campo('codigo_actividad').isNotEmpty)
                pw.Text('Actividad económica: ${campo('codigo_actividad')}${campo('actividad').isNotEmpty ? ' — ${campo('actividad')}' : ''}',
                    style: const pw.TextStyle(fontSize: 9.5)),
              if (campo('direccion').isNotEmpty) pw.Text('Dirección: ${campo('direccion')}', style: const pw.TextStyle(fontSize: 9.5, color: gris)),
              if (campo('correo').isNotEmpty || campo('telefono').isNotEmpty)
                pw.Text([if (campo('correo').isNotEmpty) campo('correo'), if (campo('telefono').isNotEmpty) campo('telefono')].join('   ·   '),
                    style: const pw.TextStyle(fontSize: 9.5, color: gris)),
            ],
          ),
        ),
        titulo('Estado de resultados fiscal'),
        tabla(
          ['Concepto', 'Monto'],
          [
            ['Ventas facturadas (sin IVA)', formatearColones(_nr(detalle['ventas_facturadas_sin_iva']))],
            ['(-) Notas de crédito (sin IVA)', formatearColones(_nr(detalle['notas_credito_sin_iva']))],
            ['(+) Otros ingresos', formatearColones(_nr(detalle['otros_ingresos']))],
            ['Ingresos brutos', formatearColones(ingresos)],
            ['(-) Costo de ventas (compras del periodo)', formatearColones(costo)],
            ['(-) Gastos deducibles', formatearColones(gastos)],
            ['Renta líquida gravable', formatearColones(renta)],
            ['Impuesto sobre la renta estimado', formatearColones(impuesto)],
            ['Tasa efectiva (impuesto / renta gravable)', '${(_tasaEfectiva(r) * 100).toStringAsFixed(2)}%'],
            if (_nr(r['gastos_no_deducibles']) > 0) ['Gastos no deducibles (no restan)', formatearColones(_nr(r['gastos_no_deducibles']))],
          ],
          numericas: [1],
        ),
        if (r['tarifa_unica_aplicada'] != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text('Se aplicó la tarifa única de ${r['tarifa_unica_aplicada']}% (los ingresos brutos superan el límite de tramos).',
                style: const pw.TextStyle(fontSize: 9, color: gris)),
          ),
        if (r['parametros_configurados'] == false)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text('Atención: no hay tramos de Hacienda cargados para $anio, el impuesto sale en cero hasta configurarlos.',
                style: pw.TextStyle(fontSize: 9, color: PdfColors.red700, fontWeight: pw.FontWeight.bold)),
          ),
        if (tramos.isNotEmpty) ...[
          titulo('Cálculo por tramo'),
          tabla(
            ['Desde', 'Hasta', 'Tarifa', 'Base en el tramo', 'Impuesto'],
            [
              for (final t in tramos)
                [
                  formatearColones(_nr(t['desde']), decimales: 0),
                  t['hasta'] == null ? 'En adelante' : formatearColones(_nr(t['hasta']), decimales: 0),
                  '${t['porcentaje']}%',
                  formatearColones(_nr(t['base_en_tramo'])),
                  formatearColones(_nr(t['impuesto_tramo'])),
                ],
            ],
            numericas: [0, 1, 2, 3, 4],
          ),
        ],
        if (porCategoria.isNotEmpty) ...[
          titulo('Gastos deducibles por categoría'),
          tabla(
            ['Categoría', 'Monto', '% del total'],
            [
              for (final g in porCategoria)
                [
                  _categoriasGastoPdf[g['categoria']] ?? g['categoria'].toString(),
                  formatearColones(_nr(g['total'])),
                  '${(_div(_nr(g['total']), gastos) * 100).toStringAsFixed(1)}%',
                ],
            ],
            numericas: [1, 2],
            total: ['Total', formatearColones(gastos), '100%'],
          ),
        ],
        if (mensual.isNotEmpty) ...[
          titulo('Detalle mes a mes'),
          tabla(
            ['Mes', 'Ingresos', 'Costos', 'Gastos deducibles', 'Renta'],
            [
              for (final m in mensual)
                [
                  _mesesLargos[((m['mes'] as num).toInt() - 1).clamp(0, 11)],
                  formatearColones(_nr(m['ingresos'])),
                  formatearColones(_nr(m['costos'])),
                  formatearColones(_nr(m['gastos_deducibles'])),
                  formatearColones(_nr(m['renta'])),
                ],
            ],
            numericas: [1, 2, 3, 4],
            total: ['Total', formatearColones(ingresos), formatearColones(costo), formatearColones(gastos), formatearColones(renta)],
          ),
        ],
        if (anterior.isNotEmpty) ...[
          titulo('Comparación con ${anterior['periodo_fiscal']}'),
          tabla(
            ['Concepto', '${anterior['periodo_fiscal']}', '$anio', 'Variación'],
            [
              for (final (etiqueta, clave) in const [
                ('Ingresos brutos', 'ingresos_brutos'),
                ('Renta líquida gravable', 'renta_liquida_gravable'),
                ('Impuesto estimado', 'impuesto_estimado'),
              ])
                [
                  etiqueta,
                  formatearColones(_nr(anterior[clave])),
                  formatearColones(_nr(r[clave])),
                  _nr(anterior[clave]) == 0
                      ? '-'
                      : '${((_nr(r[clave]) / _nr(anterior[clave]) - 1) * 100).toStringAsFixed(1)}%',
                ],
            ],
            numericas: [1, 2, 3],
          ),
        ],
        pw.SizedBox(height: 14),
        pw.Text(
          'Borrador de referencia generado con Equilibra a partir de lo registrado por el negocio. El costo de ventas se aproxima con las '
          'compras del periodo y no incluye depreciación fiscal detallada, pérdidas de periodos anteriores ni créditos personales. '
          'Revise los montos antes de presentar el D-101 ante Hacienda.',
          style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600, fontStyle: pw.FontStyle.italic),
        ),
      ];
    }

    final widgets = <pw.Widget>[];
    if (rentas.length > 1) {
      final totalImpuesto = rentas.fold(0.0, (a, r) => a + _nr(r['impuesto_estimado']));
      widgets.addAll([
        pw.Text('Renta estimada de la cartera (D-101)', style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold, color: indigo)),
        pw.Text('Periodo fiscal $anio   ·   ${rentas.length} clientes', style: const pw.TextStyle(fontSize: 10, color: gris)),
        pw.SizedBox(height: 12),
        tabla(
          ['Cliente', 'Cédula', 'Ingresos brutos', 'Renta gravable', 'Impuesto', 'Tasa ef.'],
          [
            for (final r in ([...rentas]..sort((a, b) => _nr(b['impuesto_estimado']).compareTo(_nr(a['impuesto_estimado'])))))
              [
                _nombreRenta(r),
                ((r['contribuyente'] as Map?)?['cedula'] ?? '').toString(),
                formatearColones(_nr(r['ingresos_brutos'])),
                formatearColones(_nr(r['renta_liquida_gravable'])),
                formatearColones(_nr(r['impuesto_estimado'])),
                '${(_tasaEfectiva(r) * 100).toStringAsFixed(1)}%',
              ],
          ],
          numericas: [2, 3, 4, 5],
          total: [
            'Total',
            '',
            formatearColones(rentas.fold(0.0, (a, r) => a + _nr(r['ingresos_brutos']))),
            formatearColones(rentas.fold(0.0, (a, r) => a + _nr(r['renta_liquida_gravable']))),
            formatearColones(totalImpuesto),
            '',
          ],
        ),
      ]);
    }
    for (var i = 0; i < rentas.length; i++) {
      if (widgets.isNotEmpty) widgets.add(pw.NewPage());
      widgets.addAll(paginaCliente(rentas[i]));
    }

    pdf.addPage(pw.MultiPage(
      pageTheme: _temaPagina(margin: const pw.EdgeInsets.all(32)),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Página ${context.pageNumber} de ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
      ),
      build: (context) => widgets,
    ));
    final nombre = rentas.length == 1 ? 'Renta_${anio}_${_nombreRenta(rentas.first).replaceAll(' ', '_')}.pdf' : 'Renta_${anio}_cartera.pdf';
    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: nombre);
  }

  static Future<void> exportRentaContadorToExcel(List<Map<String, dynamic>> rentas, int anio) async {
    final excel = Excel.createExcel();
    excel['Dashboard']; // primera pestaña (ver _escribirDashboard)

    // ---------------- Resumen de la cartera (una fila por cliente)
    final resumen = excel['Resumen'];
    _anchoColumnas(resumen, [34, 15, 22, 17, 17, 17, 17, 17, 11, 17]);
    resumen.appendRow([TextCellValue('Renta estimada (D-101) · Periodo fiscal $anio')]);
    _estilarCeldaUltimaFila(resumen, 0, _estiloTitulo());
    resumen.appendRow([TextCellValue('${rentas.length} cliente(s)   ·   Generado: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}')]);
    _estilarCeldaUltimaFila(resumen, 0, _estiloSubtitulo());
    resumen.appendRow([]);
    const encabezados = [
      'Cliente', 'Cédula', 'Tipo', 'Ingresos brutos', 'Costo de ventas', 'Gastos deducibles',
      'Renta gravable', 'Impuesto estimado', 'Tasa ef.', 'Impuesto año anterior',
    ];
    resumen.appendRow(encabezados.map((e) => TextCellValue(e)).toList());
    _estilarUltimaFila(resumen, encabezados.length, _estiloEncabezadoTabla());
    final totales = List<double>.filled(5, 0);
    final ordenadas = [...rentas]..sort((a, b) => _nr(b['impuesto_estimado']).compareTo(_nr(a['impuesto_estimado'])));
    for (final r in ordenadas) {
      final c = (r['contribuyente'] as Map?) ?? {};
      final valores = [_nr(r['ingresos_brutos']), _nr(r['costo_ventas']), _nr(r['gastos_deducibles']), _nr(r['renta_liquida_gravable']), _nr(r['impuesto_estimado'])];
      for (var k = 0; k < valores.length; k++) {
        totales[k] += valores[k];
      }
      resumen.appendRow([
        TextCellValue(_nombreRenta(r)),
        TextCellValue((c['cedula'] ?? '').toString()),
        TextCellValue((c['tipo_contribuyente'] ?? '').toString()),
        for (final v in valores) DoubleCellValue(v),
        DoubleCellValue(_tasaEfectiva(r)),
        DoubleCellValue(_nr((r['anio_anterior'] as Map?)?['impuesto_estimado'])),
      ]);
      for (var col = 3; col <= 7; col++) {
        _estilarCeldaUltimaFila(resumen, col, _estiloMoneda());
      }
      _estilarCeldaUltimaFila(resumen, 8, CellStyle(numberFormat: NumFormat.standard_10, horizontalAlign: HorizontalAlign.Right));
      _estilarCeldaUltimaFila(resumen, 9, _estiloMoneda());
    }
    resumen.appendRow([
      TextCellValue('TOTAL'), TextCellValue(''), TextCellValue(''),
      for (final t in totales) DoubleCellValue(t),
      TextCellValue(''), DoubleCellValue(rentas.fold(0.0, (a, r) => a + _nr((r['anio_anterior'] as Map?)?['impuesto_estimado']))),
    ]);
    _estilarUltimaFila(resumen, 3, _estiloTotalTexto());
    for (var col = 3; col <= 7; col++) {
      _estilarCeldaUltimaFila(resumen, col, _estiloTotalMoneda());
    }
    _estilarCeldaUltimaFila(resumen, 8, _estiloTotalTexto());
    _estilarCeldaUltimaFila(resumen, 9, _estiloTotalMoneda());

    // ---------------- Una hoja por cliente
    for (var i = 0; i < rentas.length; i++) {
      final r = rentas[i];
      final nombre = _nombreRenta(r);
      final hojaNombre = '${i + 1}-${nombre.length > 24 ? nombre.substring(0, 24) : nombre}'.replaceAll(RegExp(r'[\\/?*\[\]:]'), ' ');
      final hoja = excel[hojaNombre];
      _anchoColumnas(hoja, [38, 18, 18, 18, 18]);
      final c = (r['contribuyente'] as Map?) ?? {};
      final detalle = (r['ingresos_detalle'] as Map?) ?? {};

      void seccion(String t) {
        hoja.appendRow([]);
        hoja.appendRow([TextCellValue(t)]);
        _estilarCeldaUltimaFila(hoja, 0, _estiloEncabezadoSeccion());
      }

      void encabezado(List<String> columnas) {
        hoja.appendRow(columnas.map((e) => TextCellValue(e)).toList());
        _estilarUltimaFila(hoja, columnas.length, _estiloEncabezadoTabla());
      }

      void filaMonto(String concepto, double monto, {bool total = false}) {
        hoja.appendRow([TextCellValue(concepto), DoubleCellValue(monto)]);
        if (total) {
          _estilarCeldaUltimaFila(hoja, 0, _estiloTotalTexto());
          _estilarCeldaUltimaFila(hoja, 1, _estiloTotalMoneda());
        } else {
          _estilarCeldaUltimaFila(hoja, 1, _estiloMoneda());
        }
      }

      hoja.appendRow([TextCellValue('Declaración de Renta (D-101) · $anio')]);
      _estilarCeldaUltimaFila(hoja, 0, _estiloTitulo());
      hoja.appendRow([TextCellValue('Borrador para revisión del contador')]);
      _estilarCeldaUltimaFila(hoja, 0, _estiloSubtitulo());

      seccion('Datos del contribuyente');
      for (final (etiqueta, clave) in const [
        ('Nombre legal', 'nombre_legal'),
        ('Nombre comercial', 'nombre_comercial'),
        ('Cédula', 'cedula'),
        ('Tipo de cédula', 'tipo_cedula'),
        ('Tipo de contribuyente', 'tipo_contribuyente'),
        ('Código de actividad', 'codigo_actividad'),
        ('Actividad', 'actividad'),
        ('Dirección', 'direccion'),
        ('Correo', 'correo'),
        ('Teléfono', 'telefono'),
      ]) {
        final valor = (c[clave] ?? '').toString().trim();
        if (valor.isEmpty) continue;
        hoja.appendRow([TextCellValue(etiqueta), TextCellValue(valor)]);
        _estilarCeldaUltimaFila(hoja, 0, CellStyle(bold: true, fontColorHex: ExcelColor.fromHexString('FF4B5563')));
      }

      seccion('Estado de resultados fiscal');
      encabezado(['Concepto', 'Monto']);
      filaMonto('Ventas facturadas (sin IVA)', _nr(detalle['ventas_facturadas_sin_iva']));
      filaMonto('(-) Notas de crédito (sin IVA)', _nr(detalle['notas_credito_sin_iva']));
      filaMonto('(+) Otros ingresos', _nr(detalle['otros_ingresos']));
      filaMonto('Ingresos brutos', _nr(r['ingresos_brutos']), total: true);
      filaMonto('(-) Costo de ventas (compras)', _nr(r['costo_ventas']));
      filaMonto('(-) Gastos deducibles', _nr(r['gastos_deducibles']));
      filaMonto('Renta líquida gravable', _nr(r['renta_liquida_gravable']), total: true);
      filaMonto('Impuesto sobre la renta estimado', _nr(r['impuesto_estimado']), total: true);
      hoja.appendRow([TextCellValue('Tasa efectiva'), DoubleCellValue(_tasaEfectiva(r))]);
      _estilarCeldaUltimaFila(hoja, 1, CellStyle(numberFormat: NumFormat.standard_10, horizontalAlign: HorizontalAlign.Right));
      if (_nr(r['gastos_no_deducibles']) > 0) filaMonto('Gastos no deducibles (no restan)', _nr(r['gastos_no_deducibles']));

      final tramos = (r['desglose_tramos'] as List?) ?? [];
      if (tramos.isNotEmpty) {
        seccion('Cálculo por tramo');
        encabezado(['Desde', 'Hasta', 'Tarifa', 'Base en el tramo', 'Impuesto']);
        for (final t in tramos) {
          hoja.appendRow([
            DoubleCellValue(_nr(t['desde'])),
            t['hasta'] == null ? TextCellValue('En adelante') : DoubleCellValue(_nr(t['hasta'])),
            TextCellValue('${t['porcentaje']}%'),
            DoubleCellValue(_nr(t['base_en_tramo'])),
            DoubleCellValue(_nr(t['impuesto_tramo'])),
          ]);
          for (final col in [0, 1, 3, 4]) {
            _estilarCeldaUltimaFila(hoja, col, _estiloMoneda());
          }
        }
      }

      final porCategoria = (r['gastos_por_categoria'] as List?) ?? [];
      if (porCategoria.isNotEmpty) {
        seccion('Gastos deducibles por categoría');
        encabezado(['Categoría', 'Monto']);
        for (final g in porCategoria) {
          filaMonto(_categoriasGastoPdf[g['categoria']] ?? g['categoria'].toString(), _nr(g['total']));
        }
        filaMonto('Total', _nr(r['gastos_deducibles']), total: true);
      }

      final mensual = (r['mensual'] as List?) ?? [];
      if (mensual.isNotEmpty) {
        seccion('Detalle mes a mes');
        encabezado(['Mes', 'Ingresos', 'Costos', 'Gastos deducibles', 'Renta']);
        for (final m in mensual) {
          hoja.appendRow([
            TextCellValue(_mesesLargos[((m['mes'] as num).toInt() - 1).clamp(0, 11)]),
            DoubleCellValue(_nr(m['ingresos'])),
            DoubleCellValue(_nr(m['costos'])),
            DoubleCellValue(_nr(m['gastos_deducibles'])),
            DoubleCellValue(_nr(m['renta'])),
          ]);
          for (var col = 1; col <= 4; col++) {
            _estilarCeldaUltimaFila(hoja, col, _estiloMoneda());
          }
        }
        hoja.appendRow([
          TextCellValue('Total'),
          DoubleCellValue(_nr(r['ingresos_brutos'])),
          DoubleCellValue(_nr(r['costo_ventas'])),
          DoubleCellValue(_nr(r['gastos_deducibles'])),
          DoubleCellValue(_nr(r['renta_liquida_gravable'])),
        ]);
        _estilarCeldaUltimaFila(hoja, 0, _estiloTotalTexto());
        for (var col = 1; col <= 4; col++) {
          _estilarCeldaUltimaFila(hoja, col, _estiloTotalMoneda());
        }
      }

      final anterior = (r['anio_anterior'] as Map?) ?? {};
      if (anterior.isNotEmpty) {
        seccion('Comparación con ${anterior['periodo_fiscal']}');
        encabezado(['Concepto', '${anterior['periodo_fiscal']}', '$anio', 'Variación']);
        for (final (etiqueta, clave) in const [
          ('Ingresos brutos', 'ingresos_brutos'),
          ('Renta líquida gravable', 'renta_liquida_gravable'),
          ('Impuesto estimado', 'impuesto_estimado'),
        ]) {
          final antes = _nr(anterior[clave]);
          final ahora = _nr(r[clave]);
          hoja.appendRow([
            TextCellValue(etiqueta),
            DoubleCellValue(antes),
            DoubleCellValue(ahora),
            antes == 0 ? TextCellValue('-') : DoubleCellValue(ahora / antes - 1),
          ]);
          _estilarCeldaUltimaFila(hoja, 1, _estiloMoneda());
          _estilarCeldaUltimaFila(hoja, 2, _estiloMoneda());
          _estilarCeldaUltimaFila(hoja, 3, CellStyle(numberFormat: NumFormat.standard_10, horizontalAlign: HorizontalAlign.Right));
        }
      }
    }

    // ---------------- Dashboard
    if (rentas.length == 1) {
      final r = rentas.first;
      final ingresos = _nr(r['ingresos_brutos']);
      final costo = _nr(r['costo_ventas']);
      final gastos = _nr(r['gastos_deducibles']);
      final renta = _nr(r['renta_liquida_gravable']);
      final anteriorImpuesto = _nr((r['anio_anterior'] as Map?)?['impuesto_estimado']);
      _escribirDashboard(
        excel,
        titulo: 'Renta $anio · ${_nombreRenta(r)}',
        subtitulo: 'Cédula ${((r['contribuyente'] as Map?)?['cedula'] ?? '')}',
        indicadores: [
          ('Ingresos brutos', ingresos, 'moneda', null),
          ('Costo de ventas', costo, 'moneda', 'Compras del periodo'),
          ('Gastos deducibles', gastos, 'moneda', null),
          ('Renta líquida gravable', renta, 'moneda', null),
          ('Impuesto estimado', _nr(r['impuesto_estimado']), 'moneda', null),
          ('Tasa efectiva', _tasaEfectiva(r), 'porcentaje', 'Impuesto / renta gravable'),
          ('Margen neto', _div(renta, ingresos), 'porcentaje', 'Renta gravable / ingresos'),
          ('Impuesto año anterior', anteriorImpuesto, 'moneda', '${anio - 1}'),
        ],
        graficos: [
          ('¿A dónde van los ingresos?', {'Costo de ventas': costo, 'Gastos deducibles': gastos, 'Renta gravable': renta < 0 ? 0 : renta}, 'moneda'),
          ('Ingresos por mes', {for (final m in (r['mensual'] as List? ?? [])) _mesesLargos[((m['mes'] as num).toInt() - 1).clamp(0, 11)]: _nr(m['ingresos'])}, 'moneda'),
          ('Gastos deducibles por categoría', {for (final g in (r['gastos_por_categoria'] as List? ?? [])) (_categoriasGastoPdf[g['categoria']] ?? g['categoria'].toString()): _nr(g['total'])}, 'moneda'),
        ],
      );
    } else {
      _escribirDashboard(
        excel,
        titulo: 'Renta $anio de la cartera',
        subtitulo: '${rentas.length} clientes',
        indicadores: [
          ('Ingresos brutos (todos)', totales[0], 'moneda', null),
          ('Renta gravable (todos)', totales[3], 'moneda', null),
          ('Impuesto estimado (todos)', totales[4], 'moneda', null),
          ('Clientes con impuesto', rentas.where((r) => _nr(r['impuesto_estimado']) > 0).length.toDouble(), 'numero', 'De ${rentas.length}'),
        ],
        graficos: [
          ('Impuesto estimado por cliente', {for (final r in rentas) _nombreRenta(r): _nr(r['impuesto_estimado'])}, 'moneda'),
          ('Ingresos brutos por cliente', {for (final r in rentas) _nombreRenta(r): _nr(r['ingresos_brutos'])}, 'moneda'),
        ],
      );
    }
    _dashboardPrimero(excel);

    await _guardarExcel(
      excel,
      dialogTitle: 'Guardar reporte de Renta',
      fileName: rentas.length == 1 ? 'Renta_${anio}_${_nombreRenta(rentas.first).replaceAll(' ', '_')}.xlsx' : 'Renta_${anio}_cartera.xlsx',
    );
  }

  /// Exporta (o comparte) una Nota de Crédito con el detalle de lo que anula.
  static Future<void> exportNotaCreditoToPdf(NotaCredito nota, {bool share = false}) async {
    final pdf = pw.Document(theme: await _cargarTema());
    final logo = await _cargarLogo(nota.logoNegocioUrl);
    // DetalleNotaCredito/totales siempre están en colones (la nota no tiene
    // moneda propia, hereda la de la factura que anula -- ver
    // NotaCredito.facturaMoneda); si esa factura se emitió en dólares, se
    // convierte acá para que este PDF muestre la moneda real, igual que ya
    // hace exportFacturaDetalleToPdf.
    final esUsd = nota.facturaMoneda == 'USD' && nota.facturaTipoCambio > 0;
    final factorMoneda = esUsd ? 1 / nota.facturaTipoCambio : 1.0;
    String fmt(num v) => esUsd ? formatearDolares(v * factorMoneda) : formatearColones(v * factorMoneda);

    pdf.addPage(pw.MultiPage(
      pageTheme: _temaPagina(),
      build: (pw.Context context) => [
        _encabezadoDocumento(
          info: nota.negocioInfo,
          nombreNegocio: nota.nombreNegocio,
          logo: logo,
          titulo: 'NOTA DE CRÉDITO',
          datos: [
            'N.° ${nota.consecutivo}',
            'Fecha: ${nota.fechaEmision.split('T')[0]}',
            'Anula factura: ${nota.facturaConsecutivo ?? ''}',
            if (esUsd) 'Dólares (US\$) · T.C. ${formatearColones(nota.facturaTipoCambio)}',
          ],
          color: PdfColors.orange900,
        ),
        pw.SizedBox(height: 14),
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
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.orange900),
          cellStyle: const pw.TextStyle(fontSize: 10),
          cellAlignment: pw.Alignment.centerLeft,
          // Mismos anchos que la factura: sin esto las columnas se
          // repartían en partes iguales y los montos se partían en dos líneas.
          columnWidths: const {
            0: pw.FlexColumnWidth(3),
            1: pw.FlexColumnWidth(1),
            2: pw.FlexColumnWidth(1.8),
            3: pw.FlexColumnWidth(1.5),
            4: pw.FlexColumnWidth(1.8),
          },
          cellAlignments: const {
            1: pw.Alignment.center,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
          },
          headers: const ['Producto', 'Cant', 'Precio Unit.', 'IVA', 'Total'],
          data: nota.detalles.isEmpty
              ? [
                  ['Sin detalle de líneas registrado.', '', '', '', ''],
                ]
              : nota.detalles.map((d) => [
                    d.nombreProducto,
                    d.cantidad.toString(),
                    fmt(d.precioUnitario),
                    fmt(d.montoIva),
                    fmt(d.total),
                  ]).toList(),
        ),
        pw.SizedBox(height: 20),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Subtotal: ${fmt(nota.subtotal)}'),
              pw.Text('IVA: ${fmt(nota.montoIva)}'),
              pw.SizedBox(width: 180, child: pw.Divider()),
              pw.Text(
                'TOTAL ACREDITADO: ${fmt(nota.total)}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16, color: PdfColors.orange900),
              ),
            ],
          ),
        ),
        _piePagina(),
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
  /// IVA estimado de una compra: no se guarda un IVA propio por compra,
  /// se suma el de cada línea (estimado con la tarifa del producto, ver
  /// DetalleCompraSerializer) -- 0 si ninguna línea tiene impuesto asignado.
  static double _ivaEstimadoCompra(Compra c) => c.detalles.fold(0.0, (s, d) => s + (d.montoIva ?? 0));

  /// Tarifa de una compra para la columna del reporte: el porcentaje si
  /// todas sus líneas con impuesto asignado comparten la misma tarifa,
  /// "Mixta" si combinan varias, "-" si ninguna línea tiene impuesto
  /// asignado (no se puede estimar).
  static String _tarifaCompra(Compra c) {
    final tarifas = c.detalles.map((d) => d.tarifa).whereType<double>().toSet();
    if (tarifas.isEmpty) return '-';
    if (tarifas.length > 1) return 'Mixta';
    return '${tarifas.first.toStringAsFixed(0)}%';
  }

  /// Mismo agrupado por tarifa que _agruparPorTarifa (facturas), para compras.
  static ({Map<int, double> base, Map<int, double> iva}) _agruparPorTarifaCompra(List<Compra> compras) {
    final base = <int, double>{};
    final iva = <int, double>{};
    for (final c in compras) {
      for (final d in c.detalles) {
        if (d.tarifa == null) continue;
        final t = d.tarifa!.round();
        base[t] = (base[t] ?? 0) + d.subtotal;
        iva[t] = (iva[t] ?? 0) + (d.montoIva ?? 0);
      }
    }
    return (base: base, iva: iva);
  }

  /// Exporta el listado de compras a PDF -- mismo formato que el Reporte de
  /// Facturación: resumen de sumas arriba, columna Tarifa, y detalle por
  /// tarifa de IVA (estimado) debajo.
  static Future<void> exportComprasToPdf(List<Compra> compras, String negocioNombre, String periodo) async {
    final sumaSubtotal = compras.fold<double>(0.0, (s, c) => s + c.totalCompra);
    final sumaIva = compras.fold<double>(0.0, (s, c) => s + _ivaEstimadoCompra(c));
    final sumaTotal = sumaSubtotal + sumaIva;

    final pdf = pw.Document(theme: await _cargarTema());
    pdf.addPage(pw.MultiPage(
      pageTheme: _temaPagina(),
      build: (pw.Context context) => [
        pw.Header(
          level: 0,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Reporte de Compras', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo)),
                  pw.Text('Periodo: $periodo', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                ],
              ),
              pw.Text(negocioNombre, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: pw.BoxDecoration(color: PdfColors.indigo50, borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Subtotal: ${formatearColones(sumaSubtotal)}', style: const pw.TextStyle(fontSize: 12)),
              pw.Text('IVA (est.): ${formatearColones(sumaIva)}', style: const pw.TextStyle(fontSize: 12)),
              pw.Text('Total: ${formatearColones(sumaTotal)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13, color: PdfColors.indigo)),
            ],
          ),
        ),
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo),
          cellStyle: const pw.TextStyle(fontSize: 9.5),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          headerPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          headers: const ['Fecha', 'Proveedor', 'Factura Prov.', 'Subtotal', 'Tarifa', 'IVA', 'Total'],
          columnWidths: const {
            0: pw.FlexColumnWidth(1.3),
            1: pw.FlexColumnWidth(2.4),
            2: pw.FlexColumnWidth(1.6),
            3: pw.FlexColumnWidth(1.4),
            4: pw.FlexColumnWidth(0.9),
            5: pw.FlexColumnWidth(1.4),
            6: pw.FlexColumnWidth(1.4),
          },
          cellAlignments: const {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerLeft,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.center,
            5: pw.Alignment.centerRight,
            6: pw.Alignment.centerRight,
          },
          data: compras.map((c) {
            final iva = _ivaEstimadoCompra(c);
            return [
              c.fechaCompra.split('T')[0],
              c.nombreProveedor ?? 'Sin especificar',
              c.numeroFacturaProveedor,
              formatearColones(c.totalCompra),
              _tarifaCompra(c),
              formatearColones(iva),
              formatearColones(c.totalCompra + iva),
            ];
          }).toList(),
        ),
        pw.SizedBox(height: 24),
        pw.Text('Detalle por tarifa de IVA (estimado)', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo)),
        pw.SizedBox(height: 8),
        pw.Builder(builder: (context) {
          final porTarifa = _agruparPorTarifaCompra(compras);
          final tarifas = porTarifa.base.keys.toList()..sort();
          return pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo),
            cellStyle: const pw.TextStyle(fontSize: 9.5),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            headerPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            headers: const ['Tarifa', 'Base', 'IVA', 'Total'],
            cellAlignments: const {
              0: pw.Alignment.center,
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
            data: tarifas.map((t) {
              final base = porTarifa.base[t] ?? 0;
              final iva = porTarifa.iva[t] ?? 0;
              return ['$t%', formatearColones(base), formatearColones(iva), formatearColones(base + iva)];
            }).toList(),
          );
        }),
        ..._seccionDolaresPdf('Compras', 'Proveedor', [for (final c in compras) (c.numeroFacturaProveedor.isNotEmpty ? c.numeroFacturaProveedor : 'Compra', c.fechaCompra.split('T')[0], c.nombreProveedor ?? 'Sin especificar', _usdCompra(c))], color: PdfColors.orange800),
      ],
    ));
    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Reporte_Compras.pdf');
  }

  /// Exporta el listado de compras a Excel -- mismo formato que el Reporte
  /// de Facturación: fila 1-2 el resumen de sumas, fila 4 el encabezado,
  /// desde la fila 5 el detalle, y el Detalle por Tarifa a la par (columna L).
  static Future<void> exportComprasToExcel(List<Compra> compras) async {
    var excel = Excel.createExcel();
    excel['Dashboard']; // primera pestaña (ver _escribirDashboard)
    Sheet sheet = excel['Compras'];
    final hayUsd = compras.any((c) => _esUsd(_usdCompra(c)));

    final sumaSubtotal = compras.fold<double>(0.0, (s, c) => s + c.totalCompra);
    final sumaIva = compras.fold<double>(0.0, (s, c) => s + _ivaEstimadoCompra(c));
    final sumaTotal = sumaSubtotal + sumaIva;

    sheet.appendRow([TextCellValue('Reporte de Compras')]); // fila 1
    _estilarCeldaUltimaFila(sheet, 0, _estiloTitulo());
    sheet.appendRow([                                       // fila 2: sumas del periodo
      TextCellValue('Subtotal:'), DoubleCellValue(sumaSubtotal),
      TextCellValue('IVA (est.):'), DoubleCellValue(sumaIva),
      TextCellValue('Total:'), DoubleCellValue(sumaTotal),
    ]);
    _estilarCeldaUltimaFila(sheet, 1, _estiloMoneda());
    _estilarCeldaUltimaFila(sheet, 3, _estiloMoneda());
    _estilarCeldaUltimaFila(sheet, 5, _estiloMoneda(negrita: true));
    sheet.appendRow([]); // fila 3: separador
    sheet.appendRow([    // fila 4: encabezado
      TextCellValue('Fecha'),
      TextCellValue('Proveedor'),
      TextCellValue('Factura Proveedor'),
      TextCellValue('Subtotal'),
      TextCellValue('Tarifa'),
      TextCellValue('IVA'),
      TextCellValue('Total'),
      if (hayUsd) ..._encabezadosUsd.map((e) => TextCellValue(e)),
    ]);
    _estilarUltimaFila(sheet, hayUsd ? 12 : 7, _estiloEncabezadoTabla());
    for (var c in compras) { // fila 5 en adelante
      final iva = _ivaEstimadoCompra(c);
      sheet.appendRow([
        TextCellValue(c.fechaCompra.split('T')[0]),
        TextCellValue(c.nombreProveedor ?? 'Sin especificar'),
        TextCellValue(c.numeroFacturaProveedor),
        DoubleCellValue(c.totalCompra),
        TextCellValue(_tarifaCompra(c)),
        DoubleCellValue(iva),
        DoubleCellValue(c.totalCompra + iva),
        if (hayUsd) ..._celdasUsd(_usdCompra(c)),
      ]);
      for (final col in [3, 5, 6]) {
        _estilarCeldaUltimaFila(sheet, col, _estiloMoneda());
      }
      if (hayUsd) _estilarUsdUltimaFila(sheet, 7);
    }
    sheet.appendRow([]);
    sheet.appendRow([
      TextCellValue('TOTAL'), TextCellValue(''), TextCellValue(''),
      DoubleCellValue(sumaSubtotal), TextCellValue(''), DoubleCellValue(sumaIva), DoubleCellValue(sumaTotal),
      if (hayUsd) ..._totalesUsd(compras.map(_usdCompra)),
    ]);
    _estilarCeldaUltimaFila(sheet, 0, _estiloTotalTexto());
    for (final col in [3, 5, 6]) {
      _estilarCeldaUltimaFila(sheet, col, _estiloTotalMoneda());
    }
    if (hayUsd) _estilarUsdUltimaFila(sheet, 7, total: true);

    // J, u O si están las columnas en dólares (deja una de separación).
    final colTarifas = hayUsd ? 14 : 9;
    void celda(int col, int fila, CellValue valor) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: fila)).value = valor;
    }
    void estilarCelda(int col, int fila, CellStyle estilo) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: fila)).cellStyle = estilo;
    }

    celda(colTarifas, 0, TextCellValue('Detalle por Tarifa de IVA (estimado)'));
    estilarCelda(colTarifas, 0, _estiloEncabezadoSeccion());
    celda(colTarifas, 1, TextCellValue('Tarifa'));
    celda(colTarifas + 1, 1, TextCellValue('Base'));
    celda(colTarifas + 2, 1, TextCellValue('IVA'));
    celda(colTarifas + 3, 1, TextCellValue('Total'));
    for (var i = 0; i < 4; i++) {
      estilarCelda(colTarifas + i, 1, _estiloEncabezadoTabla());
    }

    final porTarifa = _agruparPorTarifaCompra(compras);
    final tarifasOrdenadas = porTarifa.base.keys.toList()..sort();
    var filaTarifa = 2;
    for (final t in tarifasOrdenadas) {
      final base = porTarifa.base[t] ?? 0;
      final iva = porTarifa.iva[t] ?? 0;
      celda(colTarifas, filaTarifa, TextCellValue('$t%'));
      celda(colTarifas + 1, filaTarifa, DoubleCellValue(base));
      estilarCelda(colTarifas + 1, filaTarifa, _estiloMoneda());
      celda(colTarifas + 2, filaTarifa, DoubleCellValue(iva));
      estilarCelda(colTarifas + 2, filaTarifa, _estiloMoneda());
      celda(colTarifas + 3, filaTarifa, DoubleCellValue(base + iva));
      estilarCelda(colTarifas + 3, filaTarifa, _estiloMoneda());
      filaTarifa++;
    }
    final baseTotal = porTarifa.base.values.fold(0.0, (s, v) => s + v);
    final ivaTotal = porTarifa.iva.values.fold(0.0, (s, v) => s + v);
    celda(colTarifas, filaTarifa, TextCellValue('TOTAL'));
    estilarCelda(colTarifas, filaTarifa, _estiloTotalTexto());
    celda(colTarifas + 1, filaTarifa, DoubleCellValue(baseTotal));
    estilarCelda(colTarifas + 1, filaTarifa, _estiloTotalMoneda());
    celda(colTarifas + 2, filaTarifa, DoubleCellValue(ivaTotal));
    estilarCelda(colTarifas + 2, filaTarifa, _estiloTotalMoneda());
    celda(colTarifas + 3, filaTarifa, DoubleCellValue(baseTotal + ivaTotal));
    estilarCelda(colTarifas + 3, filaTarifa, _estiloTotalMoneda());
    _anchoColumnas(sheet, [14, 28, 18, 14, 10, 14, 14, if (hayUsd) ...[9, 13, 14, 12, 14], 3, 3, 12, 14, 14, 14]);


    {
      final total = compras.fold(0.0, (a, c) => a + c.totalCompra);
      final credito = compras.where((c) => c.condicionCompra == '02');
      final porPagar = credito.where((c) => !c.pagada).fold(0.0, (a, c) => a + c.totalCompra);
      _escribirDashboard(
        excel,
        titulo: 'Dashboard de compras',
        subtitulo: '${compras.length} compra(s)',
        indicadores: [
          ('Total comprado', total, 'moneda', null),
          ('Compras', compras.length.toDouble(), 'numero', null),
          ('Compra promedio', _div(total, compras.length.toDouble()), 'moneda', null),
          ('Pendiente de pago', porPagar, 'moneda', 'Compras a crédito sin pagar'),
        ],
        graficos: [
          ('Compras por proveedor', _agrupar<Compra>(compras, (c) => c.nombreProveedor ?? '', (c) => c.totalCompra), 'moneda'),
          ('Compras por mes', _agrupar<Compra>(compras, (c) => _mesCorto(c.fechaCompra), (c) => c.totalCompra), 'moneda'),
          ('Contado vs. crédito', _agrupar<Compra>(compras, (c) => c.condicionCompra == '02' ? 'Crédito' : 'Contado', (c) => c.totalCompra), 'moneda'),
        ],
      );
    }
    _dashboardPrimero(excel);

    await _guardarExcel(excel, dialogTitle: 'Guardar Reporte de Compras', fileName: 'reporte_compras.xlsx');
  }

  /// Tarifa de un ingreso operativo: a diferencia de Compra, sí guarda su
  /// propio monto_iva, así que se calcula igual que declaracion_iva en el
  /// backend (IVA/subtotal), no se estima desde un producto.
  static String _tarifaIngreso(IngresoOperativo i) {
    if (i.monto == 0) return '-';
    return '${(i.montoIva / i.monto * 100).round()}%';
  }

  static ({Map<int, double> base, Map<int, double> iva}) _agruparPorTarifaIngreso(List<IngresoOperativo> ingresos) {
    final base = <int, double>{};
    final iva = <int, double>{};
    for (final i in ingresos) {
      if (i.monto == 0) continue;
      final t = (i.montoIva / i.monto * 100).round();
      base[t] = (base[t] ?? 0) + i.monto;
      iva[t] = (iva[t] ?? 0) + i.montoIva;
    }
    return (base: base, iva: iva);
  }

  /// Exporta el listado de ingresos operativos (ventas de negocios que no
  /// facturan con Equilibra) a PDF -- mismo formato que el Reporte de Compras.
  static Future<void> exportIngresosToPdf(List<IngresoOperativo> ingresos, String negocioNombre, String periodo) async {
    final sumaSubtotal = ingresos.fold<double>(0.0, (s, i) => s + i.monto);
    final sumaIva = ingresos.fold<double>(0.0, (s, i) => s + i.montoIva);
    final sumaTotal = sumaSubtotal + sumaIva;

    final pdf = pw.Document(theme: await _cargarTema());
    pdf.addPage(pw.MultiPage(
      pageTheme: _temaPagina(),
      build: (pw.Context context) => [
        pw.Header(
          level: 0,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Reporte de Ingresos', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Periodo: $periodo', style: const pw.TextStyle(fontSize: 12)),
                ],
              ),
              pw.Text(negocioNombre, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400), borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Subtotal: ${formatearColones(sumaSubtotal)}', style: const pw.TextStyle(fontSize: 12)),
              pw.Text('IVA: ${formatearColones(sumaIva)}', style: const pw.TextStyle(fontSize: 12)),
              pw.Text('Total: ${formatearColones(sumaTotal)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
            ],
          ),
        ),
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headers: const ['Fecha', 'Cliente', 'Referencia', 'Subtotal', 'Tarifa', 'IVA', 'Total'],
          data: ingresos.map((i) => [
            i.fecha,
            i.clienteNombre.isNotEmpty ? i.clienteNombre : 'Sin especificar',
            i.referencia,
            formatearColones(i.monto),
            _tarifaIngreso(i),
            formatearColones(i.montoIva),
            formatearColones(i.total),
          ]).toList(),
        ),
        pw.SizedBox(height: 24),
        pw.Text('Detalle por tarifa de IVA', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Builder(builder: (context) {
          final porTarifa = _agruparPorTarifaIngreso(ingresos);
          final tarifas = porTarifa.base.keys.toList()..sort();
          return pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headers: const ['Tarifa', 'Base', 'IVA', 'Total'],
            data: tarifas.map((t) {
              final base = porTarifa.base[t] ?? 0;
              final iva = porTarifa.iva[t] ?? 0;
              return ['$t%', formatearColones(base), formatearColones(iva), formatearColones(base + iva)];
            }).toList(),
          );
        }),
        ..._seccionDolaresPdf('Ingresos', 'Cliente', [for (final i in ingresos) (i.referencia.isNotEmpty ? i.referencia : 'Ingreso', i.fecha, i.clienteNombre.isNotEmpty ? i.clienteNombre : 'Sin especificar', _usdIngreso(i))]),
      ],
    ));
    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Reporte_Ingresos.pdf');
  }

  /// Exporta el listado de ingresos operativos a Excel -- mismo formato que
  /// el Reporte de Compras: resumen arriba, detalle desde la fila 5, y el
  /// Detalle por Tarifa a la par (columna L).
  static Future<void> exportIngresosToExcel(List<IngresoOperativo> ingresos) async {
    var excel = Excel.createExcel();
    excel['Dashboard']; // primera pestaña (ver _escribirDashboard)
    Sheet sheet = excel['Ingresos'];
    final hayUsd = ingresos.any((i) => _esUsd(_usdIngreso(i)));

    final sumaSubtotal = ingresos.fold<double>(0.0, (s, i) => s + i.monto);
    final sumaIva = ingresos.fold<double>(0.0, (s, i) => s + i.montoIva);
    final sumaTotal = sumaSubtotal + sumaIva;

    sheet.appendRow([TextCellValue('Reporte de Ingresos')]); // fila 1
    _estilarCeldaUltimaFila(sheet, 0, _estiloTitulo());
    sheet.appendRow([                                        // fila 2: sumas del periodo
      TextCellValue('Subtotal:'), DoubleCellValue(sumaSubtotal),
      TextCellValue('IVA:'), DoubleCellValue(sumaIva),
      TextCellValue('Total:'), DoubleCellValue(sumaTotal),
    ]);
    _estilarCeldaUltimaFila(sheet, 1, _estiloMoneda());
    _estilarCeldaUltimaFila(sheet, 3, _estiloMoneda());
    _estilarCeldaUltimaFila(sheet, 5, _estiloMoneda(negrita: true));
    sheet.appendRow([]); // fila 3: separador
    sheet.appendRow([    // fila 4: encabezado
      TextCellValue('Fecha'),
      TextCellValue('Cliente'),
      TextCellValue('Referencia'),
      TextCellValue('Subtotal'),
      TextCellValue('Tarifa'),
      TextCellValue('IVA'),
      TextCellValue('Total'),
      if (hayUsd) ..._encabezadosUsd.map((e) => TextCellValue(e)),
    ]);
    _estilarUltimaFila(sheet, hayUsd ? 12 : 7, _estiloEncabezadoTabla());
    for (var i in ingresos) { // fila 5 en adelante
      sheet.appendRow([
        TextCellValue(i.fecha),
        TextCellValue(i.clienteNombre.isNotEmpty ? i.clienteNombre : 'Sin especificar'),
        TextCellValue(i.referencia),
        DoubleCellValue(i.monto),
        TextCellValue(_tarifaIngreso(i)),
        DoubleCellValue(i.montoIva),
        DoubleCellValue(i.total),
        if (hayUsd) ..._celdasUsd(_usdIngreso(i)),
      ]);
      for (final col in [3, 5, 6]) {
        _estilarCeldaUltimaFila(sheet, col, _estiloMoneda());
      }
      if (hayUsd) _estilarUsdUltimaFila(sheet, 7);
    }
    sheet.appendRow([]);
    sheet.appendRow([
      TextCellValue('TOTAL'), TextCellValue(''), TextCellValue(''),
      DoubleCellValue(sumaSubtotal), TextCellValue(''), DoubleCellValue(sumaIva), DoubleCellValue(sumaTotal),
      if (hayUsd) ..._totalesUsd(ingresos.map(_usdIngreso)),
    ]);
    _estilarCeldaUltimaFila(sheet, 0, _estiloTotalTexto());
    for (final col in [3, 5, 6]) {
      _estilarCeldaUltimaFila(sheet, col, _estiloTotalMoneda());
    }
    if (hayUsd) _estilarUsdUltimaFila(sheet, 7, total: true);

    // J, u O si están las columnas en dólares (deja una de separación).
    final colTarifas = hayUsd ? 14 : 9;
    void celda(int col, int fila, CellValue valor) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: fila)).value = valor;
    }
    void estilarCelda(int col, int fila, CellStyle estilo) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: fila)).cellStyle = estilo;
    }

    celda(colTarifas, 0, TextCellValue('Detalle por Tarifa de IVA'));
    estilarCelda(colTarifas, 0, _estiloEncabezadoSeccion());
    celda(colTarifas, 1, TextCellValue('Tarifa'));
    celda(colTarifas + 1, 1, TextCellValue('Base'));
    celda(colTarifas + 2, 1, TextCellValue('IVA'));
    celda(colTarifas + 3, 1, TextCellValue('Total'));
    for (var k = 0; k < 4; k++) {
      estilarCelda(colTarifas + k, 1, _estiloEncabezadoTabla());
    }

    final porTarifa = _agruparPorTarifaIngreso(ingresos);
    final tarifasOrdenadas = porTarifa.base.keys.toList()..sort();
    var filaTarifa = 2;
    for (final t in tarifasOrdenadas) {
      final base = porTarifa.base[t] ?? 0;
      final iva = porTarifa.iva[t] ?? 0;
      celda(colTarifas, filaTarifa, TextCellValue('$t%'));
      celda(colTarifas + 1, filaTarifa, DoubleCellValue(base));
      estilarCelda(colTarifas + 1, filaTarifa, _estiloMoneda());
      celda(colTarifas + 2, filaTarifa, DoubleCellValue(iva));
      estilarCelda(colTarifas + 2, filaTarifa, _estiloMoneda());
      celda(colTarifas + 3, filaTarifa, DoubleCellValue(base + iva));
      estilarCelda(colTarifas + 3, filaTarifa, _estiloMoneda());
      filaTarifa++;
    }
    final baseTotal = porTarifa.base.values.fold(0.0, (s, v) => s + v);
    final ivaTotal = porTarifa.iva.values.fold(0.0, (s, v) => s + v);
    celda(colTarifas, filaTarifa, TextCellValue('TOTAL'));
    estilarCelda(colTarifas, filaTarifa, _estiloTotalTexto());
    celda(colTarifas + 1, filaTarifa, DoubleCellValue(baseTotal));
    estilarCelda(colTarifas + 1, filaTarifa, _estiloTotalMoneda());
    celda(colTarifas + 2, filaTarifa, DoubleCellValue(ivaTotal));
    estilarCelda(colTarifas + 2, filaTarifa, _estiloTotalMoneda());
    celda(colTarifas + 3, filaTarifa, DoubleCellValue(baseTotal + ivaTotal));
    estilarCelda(colTarifas + 3, filaTarifa, _estiloTotalMoneda());
    _anchoColumnas(sheet, [12, 28, 18, 14, 10, 14, 14, if (hayUsd) ...[9, 13, 14, 12, 14], 3, 3, 12, 14, 14, 14]);


    {
      final subtotal = ingresos.fold(0.0, (a, x) => a + x.monto);
      final iva = ingresos.fold(0.0, (a, x) => a + x.montoIva);
      _escribirDashboard(
        excel,
        titulo: 'Dashboard de ingresos',
        subtitulo: '${ingresos.length} ingreso(s)',
        indicadores: [
          ('Total de ingresos', subtotal + iva, 'moneda', null),
          ('Subtotal', subtotal, 'moneda', 'Antes de impuesto'),
          ('IVA', iva, 'moneda', null),
          ('Ingreso promedio', _div(subtotal + iva, ingresos.length.toDouble()), 'moneda', null),
        ],
        graficos: [
          ('Ingresos por cliente', _agrupar<IngresoOperativo>(ingresos, (x) => x.clienteNombre, (x) => x.monto + x.montoIva), 'moneda'),
          ('Ingresos por mes', _agrupar<IngresoOperativo>(ingresos, (x) => _mesCorto(x.fecha), (x) => x.monto + x.montoIva), 'moneda'),
          ('Contado vs. crédito', _agrupar<IngresoOperativo>(ingresos, (x) => x.condicionVenta == '02' ? 'Crédito' : 'Contado', (x) => x.monto + x.montoIva), 'moneda'),
        ],
      );
    }
    _dashboardPrimero(excel);

    await _guardarExcel(excel, dialogTitle: 'Guardar Reporte de Ingresos', fileName: 'reporte_ingresos.xlsx');
  }

  /// Exporta el listado de gastos operativos (Reportes) a PDF
  static Future<void> exportGastosToPdf(List<GastoOperativo> gastos, String negocioNombre, String periodo) async {
    final pdf = pw.Document(theme: await _cargarTema());
    pdf.addPage(pw.MultiPage(
      pageTheme: _temaPagina(),
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
    excel['Dashboard']; // primera pestaña (ver _escribirDashboard)
    final hojaGastos = excel['Gastos'];
    _escribirTabla(
      hojaGastos,
      titulo: 'Reporte de gastos',
      subtitulo: '${gastos.length} gasto(s)',
      encabezados: const ['Fecha', 'Categoría', 'Descripción', 'Proveedor', 'Deducible', 'Monto'],
      filas: [
        for (final g in gastos)
          [
            TextCellValue(g.fecha),
            TextCellValue(g.categoriaLabel),
            TextCellValue(g.descripcion),
            TextCellValue(g.nombreProveedor ?? ''),
            TextCellValue(g.deducible ? 'Sí' : 'No'),
            DoubleCellValue(g.monto),
          ],
      ],
      moneda: const {5},
      sumar: const {5},
    );
    if (gastos.isNotEmpty) {
      hojaGastos.appendRow([
        TextCellValue('Deducible para Renta'), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''),
        DoubleCellValue(gastos.where((g) => g.deducible).fold(0.0, (a, g) => a + g.monto)),
      ]);
      _estilarCeldaUltimaFila(hojaGastos, 0, CellStyle(bold: true, fontColorHex: _colorMarca));
      _estilarCeldaUltimaFila(hojaGastos, 5, _estiloMoneda(negrita: true));
    }

    {
      final total = gastos.fold(0.0, (a, g) => a + g.monto);
      final deducible = gastos.where((g) => g.deducible).fold(0.0, (a, g) => a + g.monto);
      _escribirDashboard(
        excel,
        titulo: 'Dashboard de gastos',
        subtitulo: '${gastos.length} gasto(s)',
        indicadores: [
          ('Total de gastos', total, 'moneda', null),
          ('Deducibles', deducible, 'moneda', 'Cuentan para Renta'),
          ('% deducible', _div(deducible, total), 'porcentaje', null),
          ('Gasto promedio', _div(total, gastos.length.toDouble()), 'moneda', null),
        ],
        graficos: [
          ('Gastos por categoría', _agrupar<GastoOperativo>(gastos, (g) => _categoriasGastoPdf[g.categoria] ?? g.categoria, (g) => g.monto), 'moneda'),
          ('Gastos por proveedor', _agrupar<GastoOperativo>(gastos, (g) => g.nombreProveedor ?? '', (g) => g.monto), 'moneda'),
          ('Gastos por mes', _agrupar<GastoOperativo>(gastos, (g) => _mesCorto(g.fecha), (g) => g.monto), 'moneda'),
        ],
      );
    }
    _dashboardPrimero(excel);

    await _guardarExcel(excel, dialogTitle: 'Guardar Reporte de Gastos', fileName: 'reporte_gastos.xlsx');
  }

  /// Exporta el listado de notas de crédito (Reportes) a PDF
  static Future<void> exportNotasCreditoToPdf(List<NotaCredito> notas, String negocioNombre, String periodo) async {
    final pdf = pw.Document(theme: await _cargarTema());
    pdf.addPage(pw.MultiPage(
      pageTheme: _temaPagina(),
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
        ..._seccionDolaresPdf('Notas de crédito', 'Cliente', [for (final n in notas) (n.consecutivo, n.fechaEmision.split('T')[0], n.receptorNombre, _usdNota(n))]),
      ],
    ));
    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Reporte_NotasCredito.pdf');
  }

  /// Exporta el listado de notas de crédito (Reportes) a Excel
  static Future<void> exportNotasCreditoToExcel(List<NotaCredito> notas) async {
    var excel = Excel.createExcel();
    excel['Dashboard']; // primera pestaña (ver _escribirDashboard)
    final notasUsd = notas.any((n) => _esUsd(_usdNota(n)));
    _escribirTabla(
      excel['NotasCredito'],
      titulo: 'Reporte de notas de crédito',
      subtitulo: '${notas.length} nota(s)',
      encabezados: ['Fecha', 'Consecutivo', 'Anula factura', 'Cliente', 'Motivo', 'Subtotal', 'IVA', 'Total', if (notasUsd) ..._encabezadosUsd],
      filas: [
        for (final n in notas)
          [
            TextCellValue(n.fechaEmision.split('T')[0]),
            TextCellValue(n.consecutivo),
            TextCellValue('F-${n.facturaConsecutivo ?? ''}'),
            TextCellValue(n.receptorNombre),
            TextCellValue(n.motivo),
            DoubleCellValue(n.subtotal),
            DoubleCellValue(n.montoIva),
            DoubleCellValue(n.total),
            if (notasUsd) ..._celdasUsd(_usdNota(n)),
          ],
      ],
      moneda: const {5, 6, 7},
      sumar: const {5, 6, 7},
    );

    {
      final total = notas.fold(0.0, (a, x) => a + x.total);
      _escribirDashboard(
        excel,
        titulo: 'Dashboard de notas de crédito',
        subtitulo: '${notas.length} nota(s)',
        indicadores: [
          ('Total acreditado', total, 'moneda', null),
          ('IVA revertido', notas.fold(0.0, (a, x) => a + x.montoIva), 'moneda', null),
          ('Notas emitidas', notas.length.toDouble(), 'numero', null),
          ('Monto promedio', _div(total, notas.length.toDouble()), 'moneda', null),
        ],
        graficos: [
          ('Notas por cliente', _agrupar<NotaCredito>(notas, (x) => x.receptorNombre, (x) => x.total), 'moneda'),
          ('Notas por motivo', _agrupar<NotaCredito>(notas, (x) => x.motivo, (x) => x.total), 'moneda'),
        ],
      );
    }
    _dashboardPrimero(excel);

    await _guardarExcel(excel, dialogTitle: 'Guardar Reporte de Notas de Crédito', fileName: 'reporte_notas_credito.xlsx');
  }
}
