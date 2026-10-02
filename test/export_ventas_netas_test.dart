import 'package:despacho_app/export_service.dart';
import 'package:despacho_app/factura.dart';
import 'package:despacho_app/nota_credito.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reporte de ventas: las rechazadas (o con error) no cuentan y las notas
/// de crédito se restan.
void main() {
  late List<int> bytes;
  setUp(() => ExportService.capturarExcelParaPruebas = (b, _) => bytes = b);
  tearDown(() => ExportService.capturarExcelParaPruebas = null);

  Factura factura(int id, String estado, double total) => Factura.fromJson({
        'id': id, 'negocio': 1, 'tipo_documento': '01', 'es_interno': false, 'consecutivo': '00100001010000000$id',
        'fecha_emision': '2026-09-0${id}T10:00:00Z', 'receptor_nombre': 'Cliente $id',
        'total_iva': total * 13 / 113, 'total_factura': total, 'pagada': true, 'anulada': false,
        'estado_hacienda': estado, 'condicion_venta': '01', 'plazo_credito': 0,
        'detalles': [], 'nombre_negocio': 'Negocio', 'moneda': 'CRC', 'tipo_cambio': 1,
      });

  test('Ventas netas: sin rechazadas y menos notas de crédito', () async {
    await ExportService.exportFacturasToExcel(
      [factura(1, '3', 1130), factura(2, '3', 2260), factura(3, '4', 5650)],
      notasCredito: [
        NotaCredito.fromJson({
          'id': 1, 'negocio': 1, 'factura': 1, 'consecutivo': 'NC-1', 'fecha_emision': '2026-09-05T10:00:00Z',
          'motivo': 'Devolución', 'receptor_nombre': 'Cliente 1', 'subtotal': 1000.0, 'monto_iva': 130.0,
          'total': 1130.0, 'estado_hacienda': '3', 'nombre_negocio': 'Negocio', 'detalles': [],
        }),
      ],
    );
    final excel = Excel.decodeBytes(bytes);
    final filas = excel.tables['Facturas']!.rows.map((r) => r.map((c) => c?.value?.toString() ?? '').toList()).toList();
    expect(filas.any((r) => r.contains('Cliente 3')), isFalse, reason: 'la rechazada no va');
    final netas = filas.firstWhere((r) => r.isNotEmpty && r.first == 'VENTAS NETAS');
    expect(double.parse(netas[8]), 2260);
    expect(filas.any((r) => r.isNotEmpty && r.first.startsWith('No se incluyen 1 comprobante')), isTrue);
    expect(excel.tables.containsKey('Notas de crédito'), isTrue);
    expect(double.parse(filas[1][5]), 2260, reason: 'fila de resumen: ventas netas');
  });
}
