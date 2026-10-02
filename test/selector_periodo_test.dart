import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:despacho_app/widgets/selector_periodo.dart';

void main() {
  testWidgets('Selector de período: dos toques eligen de julio a setiembre', (tester) async {
    tester.view.physicalSize = const Size(600, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    DateTimeRange? resultado;
    await tester.pumpWidget(RepaintBoundary(key: const Key('c'), child: MaterialApp(
      
      home: Builder(builder: (context) => Scaffold(body: Center(child: ElevatedButton(
          onPressed: () async => resultado = await elegirPeriodo(context, inicial: DateTimeRange(start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 30))),
          child: const Text('abrir'),
        )))),
    )));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    // Rango julio -> setiembre con dos toques.
    await tester.tap(find.text('Jul'));
    await tester.pump();
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(resultado!.start, DateTime(2026, 7, 1));
    expect(resultado!.end, DateTime(2026, 9, 30));
  });
}
