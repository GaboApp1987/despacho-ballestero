import 'package:despacho_app/declaracion_fiscal_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final ivaEjemplo = <String, dynamic>{
  'periodo': {'fecha_inicio': '2026-09-01', 'fecha_fin': '2026-09-30'},
  'ventas_gravadas': '2500000.00',
  'debito_fiscal': '325000.00',
  'debito_por_tarifa': [
    {'tarifa': '13.00', 'base': '2400000.00', 'iva': '312000.00'},
    {'tarifa': '1.00', 'base': '100000.00', 'iva': '1000.00'},
  ],
  'compras_totales': '900000.00',
  'credito_fiscal': '117000.00',
  'credito_por_tarifa': [
    {'tarifa': '13.00', 'base': '900000.00', 'iva': '117000.00'},
  ],
  'saldo_iva': '208000.00',
  'a_pagar': true,
  'cantidad_facturas': 34,
  'cantidad_notas_credito': 2,
  'cantidad_compras': 11,
  'lineas_compra_sin_impuesto': 3,
};

final rentaEjemplo = <String, dynamic>{
  'periodo_fiscal': 2025,
  'tipo_contribuyente': 'fisica',
  'ingresos_brutos': '24000000.00',
  'costo_ventas': '9000000.00',
  'gastos_deducibles': '5000000.00',
  'gastos_no_deducibles': '300000.00',
  'gastos_por_categoria': [
    {'categoria': 'alquiler', 'total': '3000000.00'},
    {'categoria': 'servicios', 'total': '2000000.00'},
  ],
  'renta_liquida_gravable': '10000000.00',
  'impuesto_estimado': '1150000.00',
  'tarifa_unica_aplicada': null,
  'desglose_tramos': [
    {'desde': '0', 'hasta': '6244000', 'porcentaje': '0', 'impuesto_tramo': '0'},
    {'desde': '6244000', 'hasta': null, 'porcentaje': '10', 'impuesto_tramo': '375600'},
  ],
  'parametros_configurados': true,
  'mensual': [
    for (var m = 1; m <= 12; m++)
      {'mes': m, 'ingresos': '${1500000 + m * 60000}', 'costos': '700000', 'gastos_deducibles': '400000', 'renta': '${400000 + m * 60000}'},
  ],
  'anio_anterior': {'periodo_fiscal': 2024, 'ingresos_brutos': '20000000.00', 'renta_liquida_gravable': '8000000', 'impuesto_estimado': '900000'},
};

Future<void> _pintar(WidgetTester tester, double ancho) async {
  tester.view.physicalSize = Size(ancho, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: RepaintBoundary(
          key: const Key('captura'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [buildDeclaracionIva(ivaEjemplo), const SizedBox(height: 20), buildDeclaracionRenta(rentaEjemplo)]),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Declaraciones en escritorio: sin desbordes', (tester) async {
    await _pintar(tester, 1100);
    expect(tester.takeException(), isNull);
    expect(find.text('IVA A PAGAR'), findsOneWidget);
    expect(find.text('IMPUESTO ESTIMADO'), findsOneWidget);
    expect(find.text('Mes a mes'), findsOneWidget);
    // Los detalles se abren al tocarlos.
    await tester.tap(find.text('Detalle por tarifa de IVA'));
    await tester.tap(find.text('Gastos deducibles por categoría'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Alquiler'), findsOneWidget);
  });

  testWidgets('Declaraciones en celular: sin desbordes', (tester) async {
    await _pintar(tester, 360);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Detalle por tarifa de IVA'));
    await tester.tap(find.text('Cómo se calcula el impuesto (tramos)'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
