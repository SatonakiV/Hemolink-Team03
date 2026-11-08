import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/main.dart';

import 'features/access/access_page_test.dart' show sessionFor;

void main() {
  testWidgets('La base inicia sin errores', (tester) async {
    await tester.pumpWidget(MainApp(session: sessionFor()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
