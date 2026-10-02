import 'package:despacho_app/compra_model.dart';
import 'package:despacho_app/export_service.dart';
import 'package:despacho_app/factura.dart';
import 'package:despacho_app/ingreso_operativo.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ventas y compras en dólares: los reportes en Excel llevan columnas con
/// la moneda, el tipo de cambio y los montos en US$ (los montos guardados
/// están en colones y se dividen por el tipo de cambio de cada documento).
void main() {
  late List<int> bytes;
  setUp(() => ExportService.capturarExcelParaPruebas = (b, _) => bytes = b);
  tearDown(() => ExportService.capturarExcelParaPruebas = null);

  List<List<String>> filas(String hoja) => Excel.decodeBytes(bytes)
      .tables[hoja]!
      .rows
      .map((r) => r.map((c) => c?.value?.toString() ?? '').toList())
      .toList();

  Factura factura(int id, String moneda, double tc, double subtotal, double iva) => Factura.fromJson({
        'id': id, 'negocio': 1, 'tipo_documento': '01', 'es_interno': false, 'consecutivo': '0010000101000000011$id',
        'fecha_emision': '2026-09-0${id}T10:00:00Z', 'receptor_nombre': 'Cliente $id',
        'total_iva': iva, 'total_factura': subtotal + iva, 'pagada': true, 'anulada': false,
        'estado_hacienda': '3', 'condicion_venta': '01', 'plazo_credito': 0,
        'detalles': [], 'nombre_negocio': 'Negocio', 'moneda': moneda, 'tipo_cambio': tc,
      });

  test('Facturas: columnas en dólares solo si hay alguna en USD', () async {
    // US$1.500 + 13% a 460 = ₡690.000 + ₡89.700
    await ExportService.exportFacturasToExcel([factura(1, 'USD', 460, 690000, 89700), factura(2, 'CRC', 1, 10000, 1300)]);
    final f = filas('Facturas');
    final encabezado = f.firstWhere((r) => r.contains('Consecutivo'));
    expect(encabezado.sublist(9, 14), ['Moneda', 'Tipo de cambio', 'Subtotal USD', 'IVA USD', 'Total USD']);
    final usd = f.firstWhere((r) => r.contains('Cliente 1'));
    expect(usd.sublist(9, 14), ['USD', '460', '1500', '195', '1695']);
    final crc = f.firstWhere((r) => r.contains('Cliente 2'));
    expect(crc[9], 'CRC');
    expect(crc[10], '');
    final total = f.lastWhere((r) => r.isNotEmpty && r.first == 'TOTAL');
    expect(total.sublist(11, 14), ['1500', '195', '1695']);

    await ExportService.exportFacturasToExcel([factura(2, 'CRC', 1, 10000, 1300)]);
    expect(filas('Facturas').firstWhere((r) => r.contains('Consecutivo')).contains('Moneda'), isFalse);
  });

  test('Compras e ingresos en dólares', () async {
    await ExportService.exportComprasToExcel([
      Compra.fromJson({
        'id': 1, 'proveedor': 1, 'nombre_proveedor': 'Proveedor USA', 'numero_factura_proveedor': 'INV-9',
        'fecha_compra': '2026-09-10T10:00:00Z', 'total_compra': 50000.0, 'condicion_compra': '01', 'pagada': true,
        'detalles_compra': [], 'notas_debito': [], 'moneda': 'USD', 'tipo_cambio': 500,
      }),
    ]);
    final c = filas('Compras').firstWhere((r) => r.contains('Proveedor USA'));
    expect(c.sublist(7, 11), ['USD', '500', '100', '0']);

    await ExportService.exportIngresosToExcel([
      IngresoOperativo.fromJson({
        'id': 1, 'fecha': '2026-09-10', 'cliente_nombre': 'Turista', 'cliente_cedula': '1', 'descripcion': 'Tour',
        'referencia': 'R-1', 'monto': 46000, 'monto_iva': 5980, 'condicion_venta': '01', 'moneda': 'USD', 'tipo_cambio': 460,
      }),
    ]);
    final i = filas('Ingresos').firstWhere((r) => r.contains('Turista'));
    expect(i.sublist(7, 12), ['USD', '460', '100', '13', '113']);
  });

  test('Declaración de IVA detallada: facturas en dólares', () async {
    await ExportService.exportDeclaracionIvaDetalladaExcel(
      negocioNombre: 'Negocio',
      periodo: 'Septiembre 2026',
      declaracion: const {'debito_fiscal': '89700', 'credito_fiscal': '0', 'saldo_iva': '89700', 'a_pagar': true},
      facturas: [factura(1, 'USD', 460, 690000, 89700)],
      notasCredito: const [],
      compras: const [],
    );
    final f = filas('Facturas').firstWhere((r) => r.contains('Cliente 1'));
    expect(f.sublist(9, 14), ['USD', '460', '1500', '195', '1695']);
  });
}
