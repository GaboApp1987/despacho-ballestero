import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reproduce lo mismo que ExportService._escribirReporteConsolidadoEnExcel
/// escribe, con datos con la forma real de ReporteConsolidadoView (backend),
/// para ver si excel.encode() falla o devuelve null -- eso es lo único que
/// hace que "no pase nada" al tocar el ícono de Excel (ver _guardarExcel,
/// que hace excel.encode()! sin capturar el error).
void main() {
  test('excel.encode() no debe ser null con un reporte real', () {
    final reporte = {
      "negocio_id": 1,
      "negocio_nombre": "Ferretería La Unión S.A.",
      "fecha_inicio": "2026-09-01",
      "fecha_fin": "2026-09-30",
      "ventas": {
        "documentos": [
          {
            "id": 10, "consecutivo": "00100001010000000123", "tipo_documento": "Factura Electrónica",
            "fecha": "2026-09-05T10:00:00Z", "cliente": "Juan Pérez", "estado_hacienda": "aceptado",
            "subtotal": 1000.0, "monto_iva": 130.0, "total": 1130.0,
          },
        ],
        "cantidad": 1,
        "total": 1130.0,
        "notas_credito": [
          {
            "id": 5, "consecutivo": "00100001030000000003", "factura_anulada": "00100001010000000100",
            "fecha": "2026-09-06T10:00:00Z", "motivo": "Devolución", "estado_hacienda": "aceptado",
            "subtotal": 100.0, "monto_iva": 13.0, "total": 113.0,
          },
        ],
        "total_notas_credito": 113.0,
        "total_neto": 1017.0,
        "desglose_impuestos": [
          {"tarifa": "IVA 13%", "base_imponible": 900.0, "monto_impuesto": 117.0},
        ],
      },
      "compras": {
        "documentos": [
          {
            "id": 20, "fecha": "2026-09-03T10:00:00Z", "proveedor": "Distribuidora XYZ",
            "numero_factura_proveedor": "F-9001", "subtotal_estimado": 500.0, "monto_iva_estimado": 65.0,
            "total": 565.0, "es_estimado": true,
          },
        ],
        "total": 565.0,
        "notas_debito": [
          {"id": 3, "numero_documento": "ND-1", "proveedor": "Distribuidora XYZ", "motivo": "Ajuste", "monto": 50.0},
        ],
        "total_notas_debito": 50.0,
        "total_neto": 615.0,
        "desglose_impuestos": [
          {"tarifa": "IVA 13%", "base_imponible": 500.0, "monto_impuesto": 65.0},
        ],
        "nota_desglose": "Estimado según la tarifa de impuesto del producto en el catálogo.",
      },
      "resumen_declaracion": {
        "ventas_por_tarifa": [
          {"tarifa": "IVA 13%", "base_imponible": 900.0, "monto_impuesto": 117.0},
        ],
        "compras_por_tarifa": [
          {"tarifa": "IVA 13%", "base_imponible": 500.0, "monto_impuesto": 65.0},
        ],
        "iva_a_pagar": 52.0,
      },
    };

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

    final bytes = excel.encode();
    expect(bytes, isNotNull, reason: 'excel.encode() devolvió null');
    expect(bytes!.length, greaterThan(0));
  });
}
