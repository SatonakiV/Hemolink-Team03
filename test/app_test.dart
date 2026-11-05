import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/main.dart' as app;

void main() {
  testWidgets('La base inicia sin errores', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
