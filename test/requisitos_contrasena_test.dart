import 'package:despacho_app/widgets/requisitos_contrasena.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('largo, solo números y comunes', () {
    expect(RequisitosContrasena.cumpleLargo('abc1234'), isFalse);
    expect(RequisitosContrasena.cumpleLargo('abc12345'), isTrue);
    expect(RequisitosContrasena.noSoloNumeros('12345678'), isFalse);
    expect(RequisitosContrasena.noComun('Password'), isFalse);
    expect(RequisitosContrasena.noComun('Pupusa#2026'), isTrue);
  });

  test('parecida al usuario o al nombre', () {
    expect(RequisitosContrasena.noParecida('ana.tienda26', ['ana.tienda']), isFalse);
    expect(RequisitosContrasena.noParecida('tienda2026', ['ana.tienda']), isFalse);
    expect(RequisitosContrasena.noParecida('Cafe-con-leche7', ['ana.tienda', 'Ana Mora']), isTrue);
  });

  test('esValida junta todo', () {
    expect(RequisitosContrasena.esValida('Cafe-con-leche7', parecidos: ['ana.tienda']), isTrue);
    expect(RequisitosContrasena.esValida('ana.tienda1', parecidos: ['ana.tienda']), isFalse);
  });
}
