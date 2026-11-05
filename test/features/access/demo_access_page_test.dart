import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/main.dart';

void main() {
  testWidgets('muestra los tres perfiles como acceso de prueba', (
    tester,
  ) async {
    await tester.pumpWidget(const MainApp());

    expect(find.text('Acceso de prueba'), findsOneWidget);
    expect(find.text('Enfermería'), findsOneWidget);
    expect(find.text('Inventario'), findsOneWidget);
    expect(find.text('Hospital'), findsOneWidget);
    expect(find.text('Cuentas ficticias · sesión local'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('enfermería muestra su sede y permiso de donantes', (
    tester,
  ) async {
    await tester.pumpWidget(const MainApp());
    await tester.tap(find.text('Enfermería'));
    await tester.pumpAndSettle();

    expect(find.text('Sesión de prueba'), findsOneWidget);
    expect(find.text('Sede demo'), findsOneWidget);
    expect(find.text('Gestión de donantes habilitada'), findsOneWidget);
  });

  testWidgets('inventario no muestra acceso a datos de donantes', (
    tester,
  ) async {
    await tester.pumpWidget(const MainApp());
    await tester.tap(find.text('Inventario'));
    await tester.pumpAndSettle();

    expect(find.text('Sede demo'), findsOneWidget);
    expect(find.text('Sin acceso a datos de donantes'), findsOneWidget);
    expect(find.text('Gestión de donantes habilitada'), findsNothing);
  });

  testWidgets('hospital muestra su institución sin acceso a donantes', (
    tester,
  ) async {
    await tester.pumpWidget(const MainApp());
    await tester.tap(find.text('Hospital'));
    await tester.pumpAndSettle();

    expect(find.text('Hospital demo'), findsOneWidget);
    expect(find.text('Sede demo'), findsNothing);
    expect(find.text('Sin acceso a datos de donantes'), findsOneWidget);
  });

  testWidgets('cerrar sesión vuelve a la selección y permite cambiar de rol', (
    tester,
  ) async {
    await tester.pumpWidget(const MainApp());
    await tester.tap(find.text('Enfermería'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cerrar sesión de prueba'));
    await tester.pumpAndSettle();

    expect(find.text('Acceso de prueba'), findsOneWidget);
    expect(find.text('Gestión de donantes habilitada'), findsNothing);

    await tester.tap(find.text('Hospital'));
    await tester.pumpAndSettle();

    expect(find.text('Hospital demo'), findsOneWidget);
    expect(find.text('Sin acceso a datos de donantes'), findsOneWidget);
  });

  testWidgets(
    'la pantalla permite recorrer el acceso en una ventana estrecha',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MainApp());

      await tester.ensureVisible(find.text('Hospital'));
      await tester.tap(find.text('Hospital'));
      await tester.pumpAndSettle();

      expect(find.text('Hospital demo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
