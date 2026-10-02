import 'package:despacho_app/widgets/asistente_flotante.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('El botón flotante aparece solo con un panel registrado y abre su asistente', (tester) async {
    final clave = GlobalKey<NavigatorState>();
    var abiertas = 0;
    final config = ConfigAsistente(() => abiertas++);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: clave,
      builder: (context, child) => AsistenteFlotante(navigatorKey: clave, child: child!),
      home: const Scaffold(body: Text('pantalla')),
    ));
    final boton = find.byIcon(Icons.auto_awesome);
    expect(boton, findsNothing);

    AsistenteFlotante.registrar(config);
    await tester.pumpAndSettle();
    expect(boton, findsOneWidget);
    await tester.tap(boton);
    expect(abiertas, 1);

    // Mientras el asistente está abierto no se muestra.
    AsistenteFlotante.abierto.value = true;
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(find.ancestor(of: boton, matching: find.byType(AnimatedScale)).last).scale, 0);
    AsistenteFlotante.abierto.value = false;

    AsistenteFlotante.quitar(config);
    await tester.pumpAndSettle();
    expect(boton, findsNothing);
  });
}
