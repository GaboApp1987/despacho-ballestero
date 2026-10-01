import 'package:despacho_app/export_service.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reporte de Renta (D-101) del contador: Dashboard primero, Resumen de la
/// cartera y una hoja por cliente con los datos del contribuyente.
void main() {
  late List<int> bytes;
  late String nombreArchivo;
  setUp(() => ExportService.capturarExcelParaPruebas = (b, n) {
        bytes = b;
        nombreArchivo = n;
      });
  tearDown(() => ExportService.capturarExcelParaPruebas = null);

  Map<String, dynamic> renta(String nombre, String cedula, double ingresos, double impuesto) => {
        'negocio_nombre': nombre,
        'periodo_fiscal': 2026,
        'tipo_contribuyente': 'juridica',
        'ingresos_brutos': '$ingresos',
        'costo_ventas': '${ingresos * 0.4}',
        'gastos_deducibles': '${ingresos * 0.2}',
        'gastos_no_deducibles': '0',
        'gastos_por_categoria': [
          {'categoria': 'alquiler', 'total': '${ingresos * 0.15}'},
          {'categoria': 'servicios', 'total': '${ingresos * 0.05}'},
        ],
        'renta_liquida_gravable': '${ingresos * 0.4}',
        'impuesto_estimado': '$impuesto',
        'tarifa_unica_aplicada': null,
        'desglose_tramos': [
          {'desde': '0', 'hasta': '5000000', 'porcentaje': '5', 'base_en_tramo': '5000000', 'impuesto_tramo': '250000'},
        ],
        'parametros_configurados': true,
        'contribuyente': {
          'nombre_comercial': nombre, 'nombre_legal': '$nombre S.A.', 'cedula': cedula, 'tipo_cedula': 'Jurídica',
          'tipo_contribuyente': 'Persona Jurídica', 'codigo_actividad': '620100', 'actividad': 'Comercio',
          'direccion': 'Heredia', 'correo': 'a@b.com', 'telefono': '8888-8888',
        },
        'ingresos_detalle': {'ventas_facturadas_sin_iva': '$ingresos', 'notas_credito_sin_iva': '0', 'otros_ingresos': '0'},
        'mensual': [
          for (var m = 1; m <= 12; m++)
            {'mes': m, 'ingresos': '${ingresos / 12}', 'costos': '0', 'gastos_deducibles': '0', 'renta': '${ingresos / 12}'},
        ],
        'anio_anterior': {'periodo_fiscal': 2025, 'ingresos_brutos': '1000', 'renta_liquida_gravable': '500', 'impuesto_estimado': '${impuesto / 2}'},
      };

  test('Excel de Renta de la cartera', () async {
    await ExportService.exportRentaContadorToExcel([
      renta('Soda La Esquina', '3101111111', 20000000, 900000),
      renta('Ferretería El Tornillo', '3101222222', 50000000, 2500000),
    ], 2026);
    final excel = Excel.decodeBytes(bytes);
    final hojas = excel.tables.keys.toList();
    expect(hojas.first, 'Dashboard');
    expect(hojas, contains('Resumen'));
    expect(hojas.where((h) => h.startsWith('1-') || h.startsWith('2-')).length, 2);
    expect(hojas.contains('Sheet1'), isFalse);
    final resumen = excel.tables['Resumen']!.rows.expand((r) => r).whereType<Data>().map((c) => c.value.toString()).join(' | ');
    // Ordenado por impuesto: la Ferretería primero.
    expect(resumen.indexOf('Ferretería'), lessThan(resumen.indexOf('Soda')));
    expect(resumen, contains('TOTAL'));
    final cliente = excel.tables[hojas.firstWhere((h) => h.startsWith('1-'))]!.rows.expand((r) => r).whereType<Data>().map((c) => c.value.toString()).join(' | ');
    expect(cliente, contains('Datos del contribuyente'));
    expect(cliente, contains('Soda La Esquina S.A.'));
    expect(cliente, contains('Detalle mes a mes'));
    expect(cliente, contains('Comparación con 2025'));
    expect(nombreArchivo, 'Renta_2026_cartera.xlsx');
  });

  test('Excel de Renta de un cliente', () async {
    await ExportService.exportRentaContadorToExcel([renta('Soda La Esquina', '3101111111', 20000000, 900000)], 2026);
    final dash = Excel.decodeBytes(bytes).tables['Dashboard']!.rows.expand((r) => r).whereType<Data>().map((c) => c.value.toString()).join(' | ');
    expect(dash, contains('Renta 2026 · Soda La Esquina'));
    expect(dash, contains('█'));
    expect(nombreArchivo, 'Renta_2026_Soda_La_Esquina.xlsx');
  });
}
