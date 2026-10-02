import 'dart:convert';
import 'dart:io';

import 'package:despacho_app/widgets/flujo_caja_modalidades.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Resultados reales de gestion/flujo_caja.py (generados con el backend).
Map<String, dynamic> _fixture(String tipo) =>
    Map<String, dynamic>.from((json.decode(File('test/fixtures_flujo_caja.json').readAsStringSync()) as Map)[tipo] as Map);

Widget _envolver(Widget hijo, {double ancho = 1200}) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: SizedBox(width: ancho, child: hijo))),
    );

void main() {
  test('formatoMonto pone el signo antes del símbolo', () {
    expect(formatoMonto(-3868363.4, '₡'), '-₡3,868,363');
    expect(formatoMonto(1000, r'$'), r'$1,000');
  });

  testWidgets('vista previa de empresa nueva: indicadores de proyecto y estado', (tester) async {
    tester.view.physicalSize = const Size(1300, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_envolver(VistaPreviaFlujo(resultado: _fixture('nueva'), simbolo: '₡')));
    expect(find.text('Inversión inicial'), findsWidgets);
    expect(find.text('TIR anual'), findsOneWidget);
    expect(find.textContaining('VAN'), findsOneWidget);
    expect(find.text('ACTIVIDADES DE OPERACIÓN'), findsOneWidget);
    expect(find.text('SALDO FINAL DE CAJA'), findsOneWidget);
    expect(find.text('Aguinaldo', findRichText: false), findsNothing); // va con sangría
    expect(find.text('   Aguinaldo'), findsOneWidget);
    expect(find.textContaining('Pesimista'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vista previa de empresa en marcha en pantalla angosta', (tester) async {
    tester.view.physicalSize = const Size(400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_envolver(VistaPreviaFlujo(resultado: _fixture('existente'), simbolo: '₡'), ancho: 380));
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('TIR anual'), findsNothing);
    expect(find.text('Cobertura de deuda'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el editor arma los parámetros que espera el backend', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Map<String, dynamic>? ultimo;
    final clave = GlobalKey<EditorParametrosFlujoState>();
    await tester.pumpWidget(_envolver(EditorParametrosFlujo(
      key: clave,
      tipo: 'nueva',
      parametros: const {
        'ventas': {'mes1': 2000000},
        'prestamos_nuevos': [
          {'nombre': 'BN', 'monto': 7000000, 'tasa_anual': 12, 'plazo_meses': 60}
        ],
        'inversiones': [
          {'concepto': 'Equipo', 'mes': 0, 'monto': 8000000}
        ],
      },
      onChanged: (p) => ultimo = p,
    )));
    await tester.pump();
    expect(ultimo, isNotNull);
    expect(ultimo!['ventas']['mes1'], 2000000);
    expect(ultimo!['ventas']['meses_rampa'], 6);
    expect(ultimo!['prestamos_nuevos'][0]['tasa_anual'], 12);
    expect(ultimo!['inversiones'][0], {'concepto': 'Equipo', 'monto': 8000000, 'mes': 0});
    expect(ultimo!['planilla']['aguinaldo'], true);

    // Cambiar el costo de ventas se refleja en los parámetros.
    await tester.tap(find.text('Costo de ventas, cobros y pagos'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Costo de ventas'), '55');
    expect(ultimo!['costo_ventas_pct'], 55);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor de empresa en marcha: digitar la historia mes a mes', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Map<String, dynamic>? ultimo;
    await tester.pumpWidget(_envolver(EditorParametrosFlujo(tipo: 'existente', parametros: const {}, onChanged: (p) => ultimo = p)));
    await tester.pump();
    expect(find.text('Importar historial de Equilibra'), findsNothing); // sin negocio de la cartera
    await tester.tap(find.text('Digitar mes a mes'));
    await tester.pump();
    final campos = find.descendant(of: find.byType(Wrap), matching: find.byType(TextField));
    expect(campos, findsNWidgets(12));
    await tester.enterText(campos.first, '3000000');
    expect((ultimo!['ventas']['historico'] as List).length, 1);
    expect(ultimo!['ventas']['historico'][0]['ventas'], 3000000);
    expect(ultimo!['cobro']['contado'], 70);
  });
}
