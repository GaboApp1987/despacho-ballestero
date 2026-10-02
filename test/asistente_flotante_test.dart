import 'package:despacho_app/widgets/asistente_flotante.dart';
import 'package:despacho_app/widgets/mascota_asistente.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Las estrellitas abren el mini chat, que se minimiza sin perder la conversación', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final clave = GlobalKey<NavigatorState>();
    var pantallaCompleta = 0;
    final config = ConfigAsistente(
      secciones: const {'inicio': 'Inicio'},
      onNavegar: (_) {},
      abrirPantallaCompleta: () => pantallaCompleta++,
    );
    await tester.pumpWidget(MaterialApp(
      navigatorKey: clave,
      builder: (context, child) => AsistenteFlotante(navigatorKey: clave, child: child!),
      home: const Scaffold(body: Text('pantalla')),
    ));
    final estrellas = find.byType(MascotaAsistente);
    expect(estrellas, findsNothing);

    AsistenteFlotante.registrar(config);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Asistente Equilibra'), findsNothing); // minimizado (Offstage)

    await tester.tap(estrellas.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Asistente Equilibra'), findsOneWidget);

    // Lo que se escribió queda al minimizar y volver a abrir.
    await tester.enterText(find.byType(TextField).first, 'hola');
    await tester.tap(find.byTooltip('Minimizar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Asistente Equilibra'), findsNothing);
    await tester.tap(estrellas.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, 'hola');

    await tester.tap(find.byTooltip('Abrir en pantalla completa'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(pantallaCompleta, 1);

    AsistenteFlotante.quitar(config);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(estrellas, findsNothing);
  });
}
