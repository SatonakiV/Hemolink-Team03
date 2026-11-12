import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/core/access/auth_session.dart';
import 'package:hemolink/main.dart';
import 'package:http/testing.dart';

import '../../core/access/auth_session_test.dart'
    show MemoryTokenStore, jsonResponse, nursingUser;
import '../donantes/donantes_page_test.dart' show RepoConsulta;

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

  testWidgets('el listado admite evaluaciones de la API sin label', (
    tester,
  ) async {
    final session = AuthSession(
      tokenStore: MemoryTokenStore(),
      client: MockClient((request) async {
        if (request.url.path == '/api/login') {
          return jsonResponse({'token': 'opaque', 'user': nursingUser});
        }
        return jsonResponse({
          'items': [
            {
              'id': 'EV001',
              'donanteId': 'DON001',
              'resultado': 'apto',
              'fechaEvaluacion': '2026-11-05',
              'fechaFinVigencia': '2026-11-20',
              'responsableId': 'ENF001',
              'fechaRegistro': '2026-11-08T15:00:00Z',
            },
            {'label': 'Evaluación ficticia de prueba'},
          ],
        });
      }),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(MainApp(session: session));
    await tester.pumpAndSettle();
    await enter(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Evaluaciones'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Apto · Donante DON001 · 2026-11-05'), findsOneWidget);
    expect(find.text('Evaluación ficticia de prueba'), findsOneWidget);
  });

  for (final role in ['nursing', 'inventory', 'hospital']) {
    testWidgets('UT01.1-D: $role solo navega por sus módulos', (tester) async {
      await tester.pumpWidget(
        MainApp(
          session: sessionFor(role: role),
          donantes: RepoConsulta(),
        ),
      );
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
      if (role == 'nursing') {
        expect(find.text('María Soto'), findsOneWidget);
        await tester.tap(find.text('María Soto'));
        await tester.pumpAndSettle();
        expect(find.text('Ficha del donante'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
      } else {
        expect(find.text('Registro persistente de prueba'), findsOneWidget);
      }
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
