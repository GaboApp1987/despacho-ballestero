import 'package:despacho_app/plan.dart';
import 'package:despacho_app/widgets/tarjeta_plan_negocio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final prepago = Plan.fromJson({
    'id': 2, 'nombre': 'Prepago Anual', 'periodicidad': 'anual', 'precio_mensual': '14900.00',
    'limite_facturas_mensual': 60, 'limite_usuarios': 1, 'limite_consultas_ia': 5,
    'recarga_documentos': 25, 'recarga_precio': '4900.00', 'incluye': 'Lo esencial\n60 documentos al año',
  });
  final pyme = Plan.fromJson({
    'id': 5, 'nombre': 'Pyme Inventario', 'precio_mensual': '14900.00', 'limite_facturas_mensual': null,
    'limite_usuarios': 5, 'limite_consultas_ia': 150, 'destacado': true, 'para_quien': 'Comercios con inventario',
  });

  test('textos del plan', () {
    expect(prepago.textoDocumentos, '60 documentos al año');
    expect(prepago.precioMensualEquivalente!.round(), 1242);
    expect(pyme.resumenLimites, 'Documentos ilimitados · 5 usuarios · 150 consultas de IA al mes');
    expect(prepago.incluye, ['Lo esencial', '60 documentos al año']);
  });

  testWidgets('tarjeta del plan: precio por período, destacado y recargas', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(children: [
            SizedBox(width: 320, child: TarjetaPlanNegocio(plan: prepago)),
            SizedBox(width: 320, child: TarjetaPlanNegocio(plan: pyme, seleccionada: true)),
            const SizedBox(width: 320, child: UsoPlanNegocio(uso: {
              'periodicidad': 'mensual', 'documentos_usados': 310, 'documentos_limite': 300, 'documentos_extra': 10,
              'monto_documentos_extra': 1000.0, 'usuarios': 2, 'usuarios_limite': 3, 'consultas_ia': 7, 'consultas_ia_limite': null,
            })),
          ]),
        ),
      ),
    ));
    expect(find.textContaining('₡14.900', findRichText: true), findsNWidgets(2));
    expect(find.textContaining('/ año', findRichText: true), findsOneWidget);
    expect(find.text('★ Más popular'), findsOneWidget);
    expect(find.text('Recargas de 25 documentos a ₡4.900.'), findsOneWidget);
    expect(find.text('10 documentos extra este mes (₡1.000)'), findsOneWidget);
    expect(find.text('7 · ilimitado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
