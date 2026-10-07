import 'dart:convert';
import 'dart:typed_data';

import 'package:despacho_app/conciliacion_util.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CSV con débito y crédito separados, coma decimal y separador ;', () {
    const csv = 'Estado de cuenta BCR\n'
        'Fecha;Documento;Concepto;Débito;Crédito;Saldo\n'
        '05/09/2026;DEP1;Depósito cliente;;50.000,00;150.000,00\n'
        '12/09/2026;CH-101;Cheque 101;30.000,00;;120.000,00\n'
        '30/09/2026;;Comisión;1.500,00;;118.500,00\n'
        ';;Saldo final;;;118.500,00\n';
    final filas = leerEstadoDeCuenta(Uint8List.fromList(utf8.encode(csv)), 'bcr.csv');
    expect(filas.length, 3);
    expect(filas[0], {'fecha': '2026-09-05', 'descripcion': 'Depósito cliente', 'referencia': 'DEP1', 'monto': '50000.00'});
    expect(filas[1]['monto'], '-30000.00');
    expect(filas[2]['monto'], '-1500.00');
  });

  test('CSV con un solo monto con signo y fecha ISO', () {
    const csv = 'fecha,descripcion,referencia,monto\n2026-09-05,Depósito,DEP1,"1,234.50"\n2026-09-06,Cargo,,-25\n';
    final filas = leerEstadoDeCuenta(Uint8List.fromList(utf8.encode(csv)), 'banco.csv');
    expect(filas.map((f) => f['monto']).toList(), ['1234.50', '-25.00']);
  });

  test('sin encabezados reconocibles da un error claro', () {
    expect(() => leerEstadoDeCuenta(Uint8List.fromList(utf8.encode('a,b\n1,2\n')), 'x.csv'), throwsException);
  });
}
