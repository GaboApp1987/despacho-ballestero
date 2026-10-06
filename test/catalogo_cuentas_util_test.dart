import 'package:despacho_app/catalogo_cuentas_util.dart';
import 'package:despacho_app/cuenta_contable.dart';
import 'package:flutter_test/flutter_test.dart';

CuentaContable _c(int id, String codigo, {int? padre, bool detalle = true}) =>
    CuentaContable(id: id, negocio: 1, codigo: codigo, nombre: codigo, cuentaPadre: padre, esDetalle: detalle);

void main() {
  test('siguiente código: después de la última hermana, mismo largo', () {
    final cuentas = [_c(1, '1100', detalle: false), _c(2, '1101', padre: 1), _c(3, '1108', padre: 1)];
    expect(siguienteCodigo(cuentas[0], cuentas), '1109');
  });

  test('primera subcuenta de una mayor terminada en 00 (catálogo estándar CR)', () {
    final cuentas = [_c(1, '1200', detalle: false)];
    expect(siguienteCodigo(cuentas[0], cuentas), '1201');
  });

  test('formato con puntos', () {
    final cuentas = [_c(1, '1.1', detalle: false), _c(2, '1.1.09', padre: 1)];
    expect(siguienteCodigo(cuentas[0], cuentas), '1.1.10');
    final sola = [_c(5, '2.1', detalle: false)];
    expect(siguienteCodigo(sola[0], sola), '2.1.01');
  });

  test('salta códigos ya usados', () {
    final cuentas = [_c(1, '5100', detalle: false), _c(2, '5101')];
    expect(siguienteCodigo(cuentas[0], cuentas), '5102');
  });

  test('niveles del árbol', () {
    final cuentas = [_c(1, '1000', detalle: false), _c(2, '1100', padre: 1, detalle: false), _c(3, '1101', padre: 2)];
    expect(nivelesCatalogo(cuentas), {1: 0, 2: 1, 3: 2});
  });
}
