import 'package:despacho_app/widgets/calculadora.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('precedencia: × y ÷ antes que + y −', () {
    expect(evaluarCalculadora('2+3×4'), 14);
    expect(evaluarCalculadora('10-6÷3'), 8);
    expect(evaluarCalculadora('1.5×2'), 3);
  });

  test('porcentaje: después de + o − es del total; si no, divide entre 100', () {
    expect(evaluarCalculadora('1000+13%'), 1130);
    expect(evaluarCalculadora('1000-10%'), 900);
    expect(evaluarCalculadora('200×15%'), 30);
    expect(evaluarCalculadora('50%'), 0.5);
  });

  test('negativos y expresiones inválidas', () {
    expect(evaluarCalculadora('-5+2'), -3);
    expect(evaluarCalculadora('3×-2'), -6);
    expect(evaluarCalculadora('5÷0'), isNull);
    expect(evaluarCalculadora('5+'), isNull);
    expect(evaluarCalculadora(''), isNull);
  });
}
