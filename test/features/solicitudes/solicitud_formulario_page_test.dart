import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/features/solicitudes/data/api_solicitud_repository.dart';
import 'package:hemolink/features/solicitudes/domain/solicitud.dart';
import 'package:hemolink/features/solicitudes/presentation/solicitud_formulario_page.dart';

import 'solicitudes_page_test.dart'
    show RepoSolicitudesPrueba, crearSolicitudEjemplo, sesionConRol;

Future<void> _seleccionar(
  WidgetTester tester,
  String key,
  String opcion,
) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  await tester.tap(find.text(opcion).last);
  await tester.pumpAndSettle();
}

Future<void> _llenarValido(WidgetTester tester) async {
  await _seleccionar(tester, 'solicitud-grupo-abo', 'AB');
  await _seleccionar(tester, 'solicitud-factor-rh', 'Negativo');
  await tester.enterText(find.byKey(const Key('solicitud-cantidad')), '3');
  await _seleccionar(tester, 'solicitud-prioridad', 'Normal');
}

void main() {
  testWidgets(
    'UT06.2-A: validación bloquea envíos inválidos y señala cada campo',
    (tester) async {
      final sesion = await sesionConRol('hospital');
      addTearDown(sesion.dispose);
      final repo = RepoSolicitudesPrueba();

      await tester.pumpWidget(
        MaterialApp(
          home: SolicitudFormularioPage(sesion: sesion, repositorio: repo),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Guardar solicitud'));
      await tester.tap(find.text('Guardar solicitud'));
      await tester.pumpAndSettle();
      expect(repo.llamadasCrear, isEmpty);

      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const Key('solicitud-grupo-abo')),
            )
            .decoration
            .errorText,
        isNotEmpty,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const Key('solicitud-factor-rh')),
            )
            .decoration
            .errorText,
        isNotEmpty,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('solicitud-cantidad')))
            .decoration!
            .errorText,
        isNotEmpty,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const Key('solicitud-prioridad')),
            )
            .decoration
            .errorText,
        isNotEmpty,
      );

      await _llenarValido(tester);
      for (final mala in ['0', '-1', '2.5']) {
        await tester.enterText(find.byKey(const Key('solicitud-cantidad')), mala);
        await tester.ensureVisible(find.text('Guardar solicitud'));
        await tester.tap(find.text('Guardar solicitud'));
        await tester.pumpAndSettle();
        expect(repo.llamadasCrear, isEmpty);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('solicitud-cantidad')))
              .decoration!
              .errorText,
          isNotEmpty,
          reason: 'Debe bloquear cantidad "$mala"',
        );
      }
    },
  );

  testWidgets(
    'UT06.2-C: fallo conserva entradas, no confirma y permite reintentar; cancelar evita escritura',
    (tester) async {
      final sesion = await sesionConRol('hospital');
      addTearDown(sesion.dispose);
      final repo = RepoSolicitudesPrueba()
        ..alCrear = (_) async =>
            throw const SolicitudApiException(500, 'No se pudo guardar.');

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<Solicitud>(
                      builder: (_) => SolicitudFormularioPage(
                        sesion: sesion,
                        repositorio: repo,
                      ),
                    ),
                  ),
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      await _llenarValido(tester);
      await tester.ensureVisible(find.text('Guardar solicitud'));
      await tester.tap(find.text('Guardar solicitud'));
      await tester.pumpAndSettle();

      expect(repo.llamadasCrear, hasLength(1));
      expect(find.text('No se pudo guardar.'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('solicitud-cantidad')))
            .controller!
            .text,
        '3',
      );
      expect(find.text('AB'), findsOneWidget);
      expect(find.text('Negativo'), findsOneWidget);
      expect(find.text('Normal'), findsOneWidget);

      await tester.ensureVisible(find.text('Cancelar'));
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Abrir'), findsOneWidget);

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await _llenarValido(tester);
      await tester.ensureVisible(find.text('Cancelar'));
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(repo.llamadasCrear, hasLength(1));
    },
  );

  testWidgets('bloquea doble envío mientras la solicitud está en curso', (
    tester,
  ) async {
    final sesion = await sesionConRol('hospital');
    addTearDown(sesion.dispose);
    final pendiente = Completer<Solicitud>();
    final repo = RepoSolicitudesPrueba()..alCrear = (_) => pendiente.future;

    await tester.pumpWidget(
      MaterialApp(
        home: SolicitudFormularioPage(sesion: sesion, repositorio: repo),
      ),
    );
    await tester.pumpAndSettle();

    await _llenarValido(tester);
    await tester.ensureVisible(find.text('Guardar solicitud'));
    await tester.tap(find.text('Guardar solicitud'));
    await tester.pump();
    await tester.tap(find.text('Guardar solicitud'));
    await tester.pump();

    expect(repo.llamadasCrear, hasLength(1));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    pendiente.complete(crearSolicitudEjemplo());
    await tester.pumpAndSettle();
  });

  testWidgets('rechaza acceso directo si el rol no es hospital', (
    tester,
  ) async {
    final sesion = await sesionConRol('inventory');
    addTearDown(sesion.dispose);
    final repo = RepoSolicitudesPrueba();

    await tester.pumpWidget(
      MaterialApp(
        home: SolicitudFormularioPage(sesion: sesion, repositorio: repo),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Solo el personal de hospital autorizado puede ingresar solicitudes.'),
      findsOneWidget,
    );
    expect(find.text('Guardar solicitud'), findsNothing);
    expect(repo.llamadasCrear, isEmpty);
  });
}
