import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/features/donantes/data/api_donante_repository.dart';
import 'package:hemolink/features/donantes/domain/donante.dart';
import 'package:hemolink/features/donantes/presentation/donantes_page.dart';

import 'donantes_page_test.dart' show RepoConsulta, donante, sesionPrueba;

class RepoAlta extends RepoConsulta {
  final enviados = <DatosDonante>[];
  final cambios = <(String, DatosDonante)>[];
  Future<Donante> Function(DatosDonante) registrar = (_) async => donante;
  @override
  Future<Donante> guardar(DatosDonante datos) {
    enviados.add(datos);
    return registrar(datos);
  }

  @override
  Future<Donante> actualizar(String id, DatosDonante datos) async {
    cambios.add((id, datos));
    return Donante(
      id: id,
      rut: datos.rut!,
      nombre: datos.nombre!,
      fechaNacimiento: datos.fechaNacimiento!,
      pesoKg: datos.pesoKg!,
      grupoAbo: datos.grupoAbo!,
      factorRh: datos.factorRh!,
      telefono: datos.telefono!,
      usuarioRegistroId: donante.usuarioRegistroId,
      fechaRegistro: donante.fechaRegistro,
      usuarioModificacionId: 'ENF002',
      fechaModificacion: DateTime.utc(2026, 11, 11),
    );
  }
}

Future<void> escribir(WidgetTester tester, String campo, String valor) async {
  final finder = find.byKey(Key('alta-$campo'));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, valor);
}

Future<void> seleccionar(
  WidgetTester tester,
  String campo,
  String valor,
) async {
  final finder = find.byKey(Key('alta-$campo'));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  await tester.tap(find.text(valor).last);
  await tester.pumpAndSettle();
}

Future<void> completar(WidgetTester tester) async {
  await escribir(tester, 'rut', '12.345.678-5');
  await escribir(tester, 'nombre', ' María Soto ');
  await escribir(tester, 'fecha-nacimiento', '10/05/1998');
  await escribir(tester, 'peso', '70,5');
  await seleccionar(tester, 'grupo-abo', 'O');
  await seleccionar(tester, 'factor-rh', 'Positivo');
  await escribir(tester, 'telefono', '912345678');
}

Future<void> guardar(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Guardar donante'));
  await tester.tap(find.text('Guardar donante'));
  await tester.pump();
}

Future<void> montarAlta(
  WidgetTester tester,
  RepoAlta repo, {
  String? rol = 'nursing',
}) async {
  final sesion = await sesionPrueba(tester, rol: rol);
  await tester.pumpWidget(
    MaterialApp(
      home: AltaDonantePage(sesion: sesion, repositorio: repo),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'regresión HU04: el formulario compartido precarga datos y actualiza el mismo donante sin crear otro',
    (tester) async {
      final repo = RepoAlta();
      final sesion = await sesionPrueba(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: DonantesPage(sesion: sesion, repositorio: repo),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('María Soto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar antecedentes'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('edicion-rut')))
            .controller!
            .text,
        '12345678-5',
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('edicion-fecha-nacimiento')),
            )
            .controller!
            .text,
        '10/05/1998',
      );
      await tester.enterText(
        find.byKey(const Key('edicion-nombre')),
        'María Corregida',
      );
      await tester.ensureVisible(find.text('Guardar cambios'));
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();
      expect(repo.enviados, isEmpty);
      expect(repo.cambios.single.$1, donante.id);
      expect(repo.cambios.single.$2.nombre, 'María Corregida');
      expect(
        find.text('Antecedentes actualizados correctamente.'),
        findsOneWidget,
      );
      expect(find.text('María Corregida'), findsOneWidget);
      expect(find.text('D001'), findsOneWidget);
      expect(find.text('ENF001'), findsOneWidget);
    },
  );

  testWidgets(
    'UT01.3-A: campos obligatorios impiden enviar y señalan los siete errores',
    (tester) async {
      final repo = RepoAlta();
      await montarAlta(tester, repo);
      await guardar(tester);
      await tester.pumpAndSettle();
      expect(repo.enviados, isEmpty);
      for (final campo in [
        'rut',
        'nombre',
        'fecha-nacimiento',
        'peso',
        'telefono',
      ]) {
        final input = tester.widget<TextField>(find.byKey(Key('alta-$campo')));
        expect(input.decoration!.errorText, isNotEmpty, reason: campo);
      }
      for (final campo in ['grupo-abo', 'factor-rh']) {
        final input = tester.widget<DropdownButtonFormField<String>>(
          find.byKey(Key('alta-$campo')),
        );
        expect(input.decoration.errorText, isNotEmpty, reason: campo);
      }
    },
  );

  testWidgets(
    'UT01.3-A: rechaza RUT, peso y fecha imposible o futura sin enviar',
    (tester) async {
      final repo = RepoAlta();
      await montarAlta(tester, repo);
      await completar(tester);
      await escribir(tester, 'rut', '12.345.678-9');
      await escribir(tester, 'peso', '-1');
      await escribir(tester, 'fecha-nacimiento', '31/02/1998');
      await guardar(tester);
      await tester.pumpAndSettle();
      expect(repo.enviados, isEmpty);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('alta-fecha-nacimiento')))
            .decoration!
            .errorText,
        contains('válida'),
      );
      await escribir(tester, 'fecha-nacimiento', '01/01/2999');
      await guardar(tester);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('alta-fecha-nacimiento')))
            .decoration!
            .errorText,
        contains('futura'),
      );
      expect(repo.enviados, isEmpty);
    },
  );

  testWidgets(
    'UT01.3-B: solo confirma después de persistir y abre la ficha; al volver actualiza el listado',
    (tester) async {
      final pendiente = Completer<Donante>();
      final repo = RepoAlta()..registrar = (_) => pendiente.future;
      var creado = false;
      repo.consulta = (_, _) async => creado ? [donante] : [];
      final sesion = await sesionPrueba(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: DonantesPage(sesion: sesion, repositorio: repo),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registrar donante'));
      await tester.pumpAndSettle();
      await completar(tester);
      await guardar(tester);
      await guardar(tester);
      expect(repo.enviados, hasLength(1));
      expect(repo.enviados.single.rut, '12345678-5');
      expect(repo.enviados.single.nombre, 'María Soto');
      expect(repo.enviados.single.pesoKg, 70.5);
      expect(find.text('Donante registrado correctamente.'), findsNothing);
      expect(find.text('Ficha del donante'), findsNothing);
      expect(
        tester.widget<TextField>(find.byKey(const Key('alta-rut'))).enabled,
        isFalse,
      );
      // El botón atrás tampoco abandona una operación que aún se confirma.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Guardar donante'), findsOneWidget);
      creado = true;
      pendiente.complete(donante);
      await tester.pumpAndSettle();
      expect(find.text('Donante registrado correctamente.'), findsOneWidget);
      expect(find.text('Ficha del donante'), findsOneWidget);
      expect(find.text('María Soto'), findsOneWidget);
      expect(find.text('12345678-5'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('María Soto'), findsOneWidget);
      expect(find.text('Buscar'), findsOneWidget);
    },
  );

  testWidgets(
    'UT01.3-C: fallo conserva cada dato y permite reintentar sin falso éxito',
    (tester) async {
      final repo = RepoAlta()
        ..registrar = (_) async =>
            throw DonanteApiException(500, 'No se pudo guardar.');
      await montarAlta(tester, repo);
      await completar(tester);
      await guardar(tester);
      await tester.pumpAndSettle();
      expect(find.text('No se pudo guardar.'), findsOneWidget);
      expect(find.text('Donante registrado correctamente.'), findsNothing);
      for (final (campo, valor) in [
        ('rut', '12.345.678-5'),
        ('nombre', ' María Soto '),
        ('fecha-nacimiento', '10/05/1998'),
        ('peso', '70,5'),
        ('telefono', '912345678'),
      ]) {
        expect(
          tester
              .widget<TextField>(find.byKey(Key('alta-$campo')))
              .controller!
              .text,
          valor,
        );
      }
      expect(find.text('O'), findsOneWidget);
      expect(find.text('Positivo'), findsOneWidget);
      await tester.ensureVisible(find.text('Reintentar'));
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(repo.enviados, hasLength(2));
      expect(repo.enviados.last.rut, repo.enviados.first.rut);
    },
  );

  testWidgets(
    'CP01-02: RUT duplicado del servidor aparece junto al campo y mantiene lo escrito',
    (tester) async {
      final repo = RepoAlta()
        ..registrar = (_) async => throw DonanteApiException(
          409,
          'Duplicado.',
          errores: {'rut': 'Ya existe un donante con ese RUT.'},
        );
      await montarAlta(tester, repo);
      await completar(tester);
      await guardar(tester);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('alta-rut')))
            .decoration!
            .errorText,
        'Ya existe un donante con ese RUT.',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('alta-nombre')))
            .controller!
            .text,
        ' María Soto ',
      );
      expect(find.text('Donante registrado correctamente.'), findsNothing);
      await escribir(tester, 'rut', '6.000.000-k');
      await tester.pumpAndSettle();
      expect(find.text('Duplicado.'), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('alta-rut')))
            .decoration!
            .errorText,
        isNull,
      );
    },
  );

  for (final rol in <String?>[null, 'hospital', 'inventory']) {
    testWidgets('CP01-08: no hay alta con acceso directo de $rol', (
      tester,
    ) async {
      final repo = RepoAlta();
      await montarAlta(tester, repo, rol: rol);
      expect(
        find.text('Tu sesión no permite gestionar donantes.'),
        findsOneWidget,
      );
      expect(find.text('Guardar donante'), findsNothing);
      expect(repo.enviados, isEmpty);
    });
  }

  testWidgets(
    'CP01-10: formulario a 320px permite corregir, completar y cancelar sin guardar',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = RepoAlta();
      final sesion = await sesionPrueba(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: DonantesPage(sesion: sesion, repositorio: repo),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registrar donante'));
      await tester.pumpAndSettle();
      await guardar(tester);
      await tester.pumpAndSettle();
      await completar(tester);
      await tester.ensureVisible(find.text('Cancelar'));
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(repo.enviados, isEmpty);
      expect(find.text('Buscar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
