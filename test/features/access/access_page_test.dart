import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/core/access/auth_session.dart';
import 'package:hemolink/main.dart';
import 'package:http/testing.dart';

import '../../core/access/auth_session_test.dart'
    show MemoryTokenStore, jsonResponse, nursingUser;

AuthSession sessionFor({String role = 'nursing', bool rejected = false}) =>
    AuthSession(
      tokenStore: MemoryTokenStore(),
      client: MockClient((request) async {
        if (request.url.path == '/api/login') {
          if (rejected) {
            return jsonResponse({
              'message': 'Credenciales inválidas o cuenta no verificada.',
            }, 401);
          }
          expect(jsonDecode(request.body)['password'], 'secret');
          return jsonResponse({
            'token': 'opaque',
            'user': {
              ...nursingUser,
              'role': role,
              'siteId': role == 'hospital' ? null : 'sede-central',
              'hospitalId': role == 'hospital' ? 'hospital-demo' : null,
            },
          });
        }
        if (request.url.path == '/api/logout') {
          return jsonResponse({'message': 'Sesión cerrada.'});
        }
        return jsonResponse({
          'items': [
            {'label': 'Registro persistente de prueba'},
          ],
        });
      }),
    );

Future<void> enter(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).at(0), 'user@test');
  await tester.enterText(find.byType(TextFormField).at(1), 'secret');
  await tester.ensureVisible(find.text('Entrar'));
  await tester.tap(find.text('Entrar'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('acceso pide credenciales y valida campos vacíos', (
    tester,
  ) async {
    await tester.pumpWidget(MainApp(session: sessionFor()));
    await tester.pumpAndSettle();
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('Enfermería'), findsNothing);
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('Ingresa tu contraseña.'), findsOneWidget);
  });

  testWidgets('credenciales rechazadas muestran error sin abrir sesión', (
    tester,
  ) async {
    await tester.pumpWidget(MainApp(session: sessionFor(rejected: true)));
    await tester.pumpAndSettle();
    await enter(tester);
    expect(
      find.text('Credenciales inválidas o cuenta no verificada.'),
      findsOneWidget,
    );
    expect(find.text('Cerrar sesión'), findsNothing);
  });

  for (final role in ['nursing', 'inventory', 'hospital']) {
    testWidgets('UT01.1-D: $role solo navega por sus módulos', (tester) async {
      await tester.pumpWidget(MainApp(session: sessionFor(role: role)));
      await tester.pumpAndSettle();
      await enter(tester);
      final module = switch (role) {
        'nursing' => 'Donantes',
        'inventory' => 'Inventario',
        _ => 'Solicitudes',
      };
      expect(
        find.widgetWithText(OutlinedButton, 'Donantes'),
        role == 'nursing' ? findsOneWidget : findsNothing,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Evaluaciones'),
        role == 'nursing' ? findsOneWidget : findsNothing,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Inventario'),
        role == 'inventory' ? findsOneWidget : findsNothing,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Solicitudes'),
        role == 'hospital' ? findsOneWidget : findsNothing,
      );
      await tester.tap(find.widgetWithText(OutlinedButton, module));
      await tester.pumpAndSettle();
      expect(find.text('Registro persistente de prueba'), findsOneWidget);
      await tester.ensureVisible(find.text('Cerrar sesión'));
      await tester.tap(find.text('Cerrar sesión'));
      await tester.pumpAndSettle();
      expect(find.text('Iniciar sesión'), findsOneWidget);
      expect(find.text('Registro persistente de prueba'), findsNothing);
    });
  }

  testWidgets('acceso y sesión se pueden recorrer a 320px sin desbordamiento', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MainApp(session: sessionFor()));
    await tester.pumpAndSettle();
    await enter(tester);
    await tester.ensureVisible(find.text('Cerrar sesión'));
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
