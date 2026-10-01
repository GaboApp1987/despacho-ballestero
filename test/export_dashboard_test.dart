import 'package:despacho_app/compra_model.dart';
import 'package:despacho_app/export_service.dart';
import 'package:despacho_app/factura.dart';
import 'package:despacho_app/gasto_operativo.dart';
import 'package:despacho_app/ingreso_operativo.dart';
import 'package:despacho_app/nota_credito.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

/// Todos los Excel exportados deben abrir en una pestaña "Dashboard" con
/// contenido (antes la primera pestaña era la "Sheet1" vacía), sin dejar esa
/// hoja vacía y sin romper excel.encode().
void main() {
  late List<int> bytes;
  setUp(() => ExportService.capturarExcelParaPruebas = (b, _) => bytes = b);
  tearDown(() => ExportService.capturarExcelParaPruebas = null);

  Excel abrir() => Excel.decodeBytes(bytes);

  void verificarDashboard(String nombre) {
    final excel = abrir();
    final hojas = excel.tables.keys.toList();
    expect(hojas.first, 'Dashboard', reason: '$nombre: el Dashboard debe ser la primera pestaña ($hojas)');
    expect(hojas.contains('Sheet1'), isFalse, reason: '$nombre: no debe quedar la hoja vacía');
    final dash = excel.tables['Dashboard']!;
    final textos = dash.rows.expand((r) => r).whereType<Data>().map((c) => c.value.toString()).join(' | ');
    expect(textos.contains('Dashboard') || textos.contains('Estado de cuenta'), isTrue, reason: '$nombre: falta el título');
    expect(textos.contains('█'), isTrue, reason: '$nombre: faltan las barras del gráfico');
  }

  final facturas = [
    for (var i = 0; i < 4; i++)
      Factura.fromJson({
        'id': i + 1, 'negocio': 1, 'tipo_documento': '01', 'es_interno': false, 'consecutivo': '0010000101000000000$i',
        'fecha_emision': '2026-09-0${i + 1}T10:00:00Z', 'receptor_nombre': i.isEven ? 'Constructora Arenal' : 'Soda La Esquina',
        'total_iva': 130.0 * (i + 1), 'total_factura': 1130.0 * (i + 1), 'pagada': i != 1, 'anulada': false,
        'estado_hacienda': i == 3 ? '4' : '3', 'condicion_venta': i == 1 ? '02' : '01', 'plazo_credito': 0,
        'detalles': [], 'nombre_negocio': 'Ferretería', 'moneda': 'CRC', 'tipo_cambio': 1,
      }),
  ];
  final compras = [
    for (var i = 0; i < 3; i++)
      Compra.fromJson({
        'id': i + 1, 'proveedor': 1, 'nombre_proveedor': i == 0 ? 'Distribuidora XYZ' : 'Cementos CR',
        'numero_factura_proveedor': 'F-$i', 'fecha_compra': '2026-09-1${i}T10:00:00Z', 'total_compra': 565.0 * (i + 1),
        'condicion_compra': i == 2 ? '02' : '01', 'pagada': i != 2, 'detalles_compra': [], 'notas_debito': [],
        'moneda': 'CRC', 'tipo_cambio': 1,
      }),
  ];
  final gastos = [
    for (var i = 0; i < 3; i++)
      GastoOperativo.fromJson({
        'id': i + 1, 'fecha': '2026-09-1$i', 'categoria': i == 0 ? 'alquiler' : 'servicios', 'descripcion': 'Gasto $i',
        'monto': 1000.0 * (i + 1), 'deducible': i != 2, 'nombre_proveedor': 'Proveedor $i',
      }),
  ];
  final ingresos = [
    for (var i = 0; i < 2; i++)
      IngresoOperativo.fromJson({
        'id': i + 1, 'fecha': '2026-09-1$i', 'cliente_nombre': 'Cliente $i', 'cliente_cedula': '1',
        'descripcion': 'Servicio', 'referencia': 'R$i', 'monto': 5000.0, 'monto_iva': 650.0, 'condicion_venta': '01',
        'moneda': 'CRC', 'tipo_cambio': 1,
      }),
  ];
  final notas = [
    NotaCredito.fromJson({
      'id': 1, 'negocio': 1, 'factura': 1, 'consecutivo': '0010000103', 'fecha_emision': '2026-09-05T10:00:00Z',
      'motivo': 'Devolución', 'receptor_nombre': 'Constructora Arenal', 'subtotal': 100.0, 'monto_iva': 13.0,
      'total': 113.0, 'estado_hacienda': '3', 'nombre_negocio': 'Ferretería', 'detalles': [],
    }),
  ];
  final reporte = {
    'negocio_nombre': 'Ferretería El Tornillo',
    'ventas': {
      'documentos': [
        {'consecutivo': '1', 'tipo_documento': 'Factura Electrónica', 'fecha': '2026-09-05T10:00:00Z', 'cliente': 'Juan', 'subtotal': 1000.0, 'monto_iva': 130.0, 'total': 1130.0},
      ],
      'total': 1130.0, 'notas_credito': [], 'total_notas_credito': 0.0, 'total_neto': 1130.0,
      'desglose_impuestos': [{'tarifa': 'IVA 13%', 'base_imponible': 1000.0, 'monto_impuesto': 130.0}],
    },
    'compras': {
      'documentos': [
        {'fecha': '2026-09-03T10:00:00Z', 'proveedor': 'XYZ', 'numero_factura_proveedor': 'F-1', 'subtotal_estimado': 500.0, 'monto_iva_estimado': 65.0, 'total': 565.0},
      ],
      'total': 565.0, 'notas_debito': [], 'total_notas_debito': 0.0, 'total_neto': 565.0,
      'desglose_impuestos': [{'tarifa': 'IVA 13%', 'base_imponible': 500.0, 'monto_impuesto': 65.0}],
    },
    'resumen_declaracion': {
      'ventas_por_tarifa': [{'tarifa': 'IVA 13%', 'base_imponible': 1000.0, 'monto_impuesto': 130.0}],
      'compras_por_tarifa': [{'tarifa': 'IVA 13%', 'base_imponible': 500.0, 'monto_impuesto': 65.0}],
      'iva_a_pagar': 65.0,
    },
  };

  test('Facturas', () async {
    await ExportService.exportFacturasToExcel(facturas);
    verificarDashboard('Facturas');
  });
  test('Reporte consolidado (un cliente)', () async {
    await ExportService.exportReporteConsolidadoToExcel(reporte);
    verificarDashboard('Consolidado');
  });
  test('Reportes de varios clientes', () async {
    await ExportService.exportReportesConsolidadosToExcel([reporte, {...reporte, 'negocio_nombre': 'Soda'}], periodo: 'set 2026');
    verificarDashboard('Varios clientes');
    expect(abrir().tables.keys.elementAt(1), 'Resumen');
  });
  test('Saldos', () async {
    await ExportService.exportSaldosToExcel([
      {'nombre': 'Constructora Arenal', 'cedula': '3101', 'saldo': '45000'},
      {'nombre': 'Soda La Esquina', 'cedula': '3102', 'saldo': '12000'},
    ]);
    verificarDashboard('Saldos');
  });
  test('Historial de cliente', () async {
    await ExportService.exportHistorialToExcel('Constructora Arenal', [
      {'fecha': '2026-09-01', 'tipo': 'FACTURA', 'numero': '1', 'monto': '10000'},
      {'fecha': '2026-09-10', 'tipo': 'ABONO', 'numero': '', 'monto': '4000'},
    ]);
    verificarDashboard('Historial');
  });
  test('Declaración de IVA', () async {
    await ExportService.exportDeclaracionIvaDetalladaExcel(
      negocioNombre: 'Ferretería', periodo: 'set 2026',
      declaracion: {
        'debito_fiscal': '1300', 'credito_fiscal': '650', 'saldo_iva': '650', 'a_pagar': true,
        'ventas_gravadas': '10000', 'compras_totales': '5650',
        'debito_por_tarifa': [{'tarifa': '13', 'base': '10000', 'iva': '1300'}],
        'credito_por_tarifa': [{'tarifa': '13', 'base': '5000', 'iva': '650'}],
      },
      facturas: facturas, notasCredito: notas, compras: compras,
    );
    verificarDashboard('IVA');
  });
  test('Declaración de Renta', () async {
    await ExportService.exportDeclaracionRentaDetalladaExcel(
      negocioNombre: 'Ferretería',
      declaracion: {
        'periodo_fiscal': '2026', 'ingresos_brutos': '100000', 'costo_ventas': '40000', 'gastos_deducibles': '20000',
        'gastos_no_deducibles': '5000', 'renta_liquida_gravable': '40000', 'impuesto_estimado': '4000',
        'gastos_por_categoria': [{'categoria': 'alquiler', 'total': '15000'}, {'categoria': 'servicios', 'total': '5000'}],
      },
      facturas: facturas, compras: compras, gastos: gastos,
    );
    verificarDashboard('Renta');
  });
  test('Compras', () async {
    await ExportService.exportComprasToExcel(compras);
    verificarDashboard('Compras');
  });
  test('Ingresos', () async {
    await ExportService.exportIngresosToExcel(ingresos);
    verificarDashboard('Ingresos');
  });
  test('Gastos', () async {
    await ExportService.exportGastosToExcel(gastos);
    verificarDashboard('Gastos');
  });
  test('Notas de crédito', () async {
    await ExportService.exportNotasCreditoToExcel(notas);
    verificarDashboard('Notas de crédito');
  });

  // ---- Formato de las pestañas de detalle (no solo el Dashboard): título,
  // encabezado con el color de marca y fila TOTAL con la suma correcta.
  String texto(Data? d) => d?.value?.toString() ?? '';

  void verificarTabla(String hoja, {required String titulo, required int columnaTotal, required double total}) {
    final filas = abrir().tables[hoja]!.rows;
    expect(texto(filas.first.first), startsWith(titulo), reason: '$hoja: falta el título');
    final conEncabezado = filas.where((r) => r.isNotEmpty && r.first?.cellStyle?.backgroundColor.colorHex == 'FF3730A3');
    expect(conEncabezado, isNotEmpty, reason: '$hoja: el encabezado no tiene el color de marca');
    final filaTotal = filas.lastWhere((r) => r.isNotEmpty && texto(r.first) == 'TOTAL');
    expect(double.parse(texto(filaTotal[columnaTotal])), closeTo(total, 0.01), reason: '$hoja: total incorrecto');
  }

  test('Formato: hojas de detalle del reporte de ventas y compras', () async {
    await ExportService.exportReporteConsolidadoToExcel(reporte);
    verificarTabla('Ventas', titulo: 'Ventas (1 documento(s))', columnaTotal: 6, total: 1130);
    verificarTabla('Compras', titulo: 'Compras (1 documento(s))', columnaTotal: 5, total: 565);
    verificarTabla('Desglose IVA Ventas', titulo: 'Desglose de IVA de ventas', columnaTotal: 2, total: 130);
    final resumen = abrir().tables['Resumen Declaracion']!.rows.expand((r) => r).map(texto).join(' | ');
    expect(resumen, contains('IVA A PAGAR'));
  });

  test('Formato: varios clientes con prefijo en cada hoja', () async {
    await ExportService.exportReportesConsolidadosToExcel([reporte, {...reporte, 'negocio_nombre': 'Soda'}], periodo: 'set 2026');
    final hojas = abrir().tables.keys.toList();
    final ventasSoda = hojas.firstWhere((h) => h.startsWith('2-Soda') && h.endsWith('Ventas'));
    verificarTabla(ventasSoda, titulo: 'Ventas', columnaTotal: 6, total: 1130);
  });

  test('Formato: saldos, estado de cuenta, gastos y notas', () async {
    await ExportService.exportSaldosToExcel([
      {'nombre': 'Soda La Esquina', 'cedula': '3102', 'saldo': '12000'},
      {'nombre': 'Constructora Arenal', 'cedula': '3101', 'saldo': '45000'},
    ]);
    verificarTabla('Saldos', titulo: 'Cuentas por cobrar', columnaTotal: 2, total: 57000);
    // De mayor a menor saldo.
    final saldos = abrir().tables['Saldos']!.rows;
    final encabezado = saldos.indexWhere((r) => r.isNotEmpty && texto(r.first) == 'Cliente');
    expect(texto(saldos[encabezado + 1].first), 'Constructora Arenal');

    await ExportService.exportHistorialToExcel('Constructora Arenal', [
      {'fecha': '2026-09-01', 'tipo': 'FACTURA', 'numero': '1', 'monto': '10000'},
      {'fecha': '2026-09-10', 'tipo': 'ABONO', 'numero': '', 'monto': '4000'},
    ]);
    verificarTabla('Historial', titulo: 'Estado de cuenta', columnaTotal: 3, total: 10000);
    final historial = abrir().tables['Historial']!.rows;
    final ultimoMovimiento = historial.lastWhere((r) => r.isNotEmpty && texto(r.first) == '2026-09-10');
    expect(double.parse(texto(ultimoMovimiento[5])), 6000, reason: 'saldo acumulado');

    await ExportService.exportGastosToExcel(gastos);
    verificarTabla('Gastos', titulo: 'Reporte de gastos', columnaTotal: 5, total: 6000);

    await ExportService.exportNotasCreditoToExcel(notas);
    verificarTabla('NotasCredito', titulo: 'Reporte de notas de crédito', columnaTotal: 7, total: 113);
  });

  test('Formato: declaración de Renta del negocio', () async {
    await ExportService.exportDeclaracionRentaDetalladaExcel(
      negocioNombre: 'Ferretería',
      declaracion: {
        'periodo_fiscal': '2026', 'ingresos_brutos': '100000', 'costo_ventas': '40000', 'gastos_deducibles': '20000',
        'gastos_no_deducibles': '5000', 'renta_liquida_gravable': '40000', 'impuesto_estimado': '4000',
        'gastos_por_categoria': [], 'desglose_tramos': [],
      },
      facturas: facturas, compras: compras, gastos: gastos,
    );
    verificarTabla('Facturas', titulo: 'Facturas del periodo fiscal 2026', columnaTotal: 5, total: facturas.fold(0.0, (a, f) => a + f.totalFactura));
    verificarTabla('Compras', titulo: 'Compras del periodo fiscal 2026', columnaTotal: 3, total: compras.fold(0.0, (a, c) => a + c.totalCompra));
  });
}
