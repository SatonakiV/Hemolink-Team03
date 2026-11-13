import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/features/donantes/data/api_donante_repository.dart';
import 'package:hemolink/features/donantes/domain/donante.dart';
import 'package:hemolink/features/donantes/presentation/donantes_page.dart';

import 'donantes_page_test.dart' show RepoConsulta, donante, sesionPrueba;

class _RepoEdicion extends RepoConsulta {
  Donante guardado = donante;
  final intentos = <(String, DatosDonante)>[];
  DonanteApiException? fallo;

  _RepoEdicion() {
    ficha = (_) async => guardado;
  }

  @override
  Future<Donante> actualizar(String id, DatosDonante datos) async {
    intentos.add((id, datos));
    if (fallo case final error?) throw error;
    guardado = Donante(
      id: id,
      rut: datos.rut!,
      nombre: datos.nombre!,
      fechaNacimiento: datos.fechaNacimiento!,
      pesoKg: datos.pesoKg!,
      grupoAbo: datos.grupoAbo!,
      factorRh: datos.factorRh!,
      telefono: datos.telefono!,
      usuarioRegistroId: guardado.usuarioRegistroId,
      fechaRegistro: guardado.fechaRegistro,
      usuarioModificacionId: 'ENF002',
      fechaModificacion: DateTime.utc(2026, 11, 12),
    );
    return guardado;
  }
}

Future<void> _abrirEdicion(WidgetTester tester, _RepoEdicion repo) async {
  final sesion = await sesionPrueba(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: DonanteFichaPage(
        sesion: sesion,
        repositorio: repo,
        donanteId: donante.id,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Editar antecedentes'));
  await tester.pumpAndSettle();
  expect(_texto(tester, 'nombre'), donante.nombre);
  expect(_texto(tester, 'rut'), donante.rut);
}

String _texto(WidgetTester tester, String campo) => tester
    .widget<TextField>(find.byKey(Key('edicion-$campo')))
    .controller!
    .text;

Future<void> _escribir(WidgetTester tester, String campo, String valor) async {
  final entrada = find.byKey(Key('edicion-$campo'));
  await tester.ensureVisible(entrada);
  await tester.enterText(entrada, valor);
}

Future<void> _seleccionar(
  WidgetTester tester,
  String campo,
  String valor,
) async {
  final entrada = find.byKey(Key('edicion-$campo'));
  await tester.ensureVisible(entrada);
  await tester.tap(entrada);
  await tester.pumpAndSettle();
  await tester.tap(find.text(valor).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('UT04.6-C/CP04-09: cancelar vuelve a la ficha sin escribir', (
    tester,
  ) async {
    final repo = _RepoEdicion();
    await _abrirEdicion(tester, repo);
    await _escribir(tester, 'nombre', 'Cambio que debe descartarse');
    await _escribir(tester, 'telefono', '988887777');
    await _seleccionar(tester, 'grupo-abo', 'A');
    await _seleccionar(tester, 'factor-rh', 'Negativo');
    await tester.ensureVisible(find.text('Cancelar'));
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.text('Ficha del donante'), findsOneWidget);
    expect(find.text(donante.nombre), findsOneWidget);
    expect(find.text('Cambio que debe descartarse'), findsNothing);
    expect(repo.intentos, isEmpty);
    expect(await repo.buscarPorId(donante.id), same(donante));
    expect(find.text('Antecedentes actualizados correctamente.'), findsNothing);

    // Volver a abrir debe precargar la versión guardada, sin el borrador.
    await tester.tap(find.text('Editar antecedentes'));
    await tester.pumpAndSettle();
    expect(_texto(tester, 'nombre'), donante.nombre);
    expect(_texto(tester, 'telefono'), donante.telefono);
    expect(find.text('O'), findsOneWidget);
    expect(find.text('Positivo'), findsOneWidget);
    expect(repo.intentos, isEmpty);
  });

  for (final codigo in [409, 500]) {
    testWidgets(
      'UT04.6-C/CP04-08: error $codigo conserva ficha y borrador; permite corregir y guardar',
      (tester) async {
        final repo = _RepoEdicion()
          ..fallo = DonanteApiException(
            codigo,
            codigo == 409 ? 'RUT duplicado.' : 'Fallo al guardar.',
            errores: codigo == 409
                ? {'rut': 'Ya existe un donante con ese RUT.'}
                : const {},
          );
        await _abrirEdicion(tester, repo);
        final borrador = {
          'rut': codigo == 409 ? '11.111.111-1' : '12.345.678-5',
          'nombre': 'Donante Corregido',
          'fecha-nacimiento': '20/06/1996',
          'peso': '74,5',
          'telefono': '988887777',
        };
        for (final campo in borrador.entries) {
          await _escribir(tester, campo.key, campo.value);
        }
        await _seleccionar(tester, 'grupo-abo', 'A');
        await _seleccionar(tester, 'factor-rh', 'Negativo');
        await tester.ensureVisible(find.text('Guardar cambios'));
        await tester.tap(find.text('Guardar cambios'));
        await tester.pumpAndSettle();

        expect(repo.intentos, hasLength(1));
        expect(repo.intentos.single.$1, donante.id);
        expect(await repo.buscarPorId(donante.id), same(donante));
        expect(find.text('Editar donante'), findsOneWidget);
        expect(find.text(repo.fallo!.mensaje), findsOneWidget);
        expect(
          find.text('Antecedentes actualizados correctamente.'),
          findsNothing,
        );
        for (final campo in borrador.entries) {
          expect(_texto(tester, campo.key), campo.value);
        }
        expect(find.text('A'), findsOneWidget);
        expect(find.text('Negativo'), findsOneWidget);

        if (codigo == 409) {
          expect(
            tester
                .widget<TextField>(find.byKey(const Key('edicion-rut')))
                .decoration!
                .errorText,
            'Ya existe un donante con ese RUT.',
          );
          await _escribir(tester, 'rut', '12.345.678-5');
        }
        repo.fallo = null;
        final boton = find.text(
          codigo == 500 ? 'Reintentar' : 'Guardar cambios',
        );
        await tester.ensureVisible(boton);
        await tester.tap(boton);
        await tester.pumpAndSettle();

        expect(repo.intentos, hasLength(2));
        expect(repo.intentos.last.$1, donante.id);
        expect(repo.guardado.nombre, 'Donante Corregido');
        expect(repo.guardado.telefono, '988887777');
        expect(repo.guardado.pesoKg, 74.5);
        expect(repo.guardado.fechaNacimiento, DateTime(1996, 6, 20));
        expect(repo.guardado.grupoAbo, 'A');
        expect(repo.guardado.factorRh, 'negativo');
        expect(repo.guardado.rut, donante.rut);
        expect(find.text('Ficha del donante'), findsOneWidget);
        expect(find.text('Donante Corregido'), findsOneWidget);
        expect(
          find.text('Antecedentes actualizados correctamente.'),
          findsOneWidget,
        );
      },
    );
  }

  for (final rol in <String?>[null, 'inventory', 'hospital']) {
    testWidgets('UT04.6-D: acceso directo a edición bloqueado para $rol', (
      tester,
    ) async {
      final repo = _RepoEdicion();
      final sesion = await sesionPrueba(tester, rol: rol);
      await tester.pumpWidget(
        MaterialApp(
          home: EdicionDonantePage(
            sesion: sesion,
            repositorio: repo,
            donante: donante,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Tu sesión no permite gestionar donantes.'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Guardar cambios'), findsNothing);
      expect(repo.intentos, isEmpty);
      expect(await repo.buscarPorId(donante.id), same(donante));
    });
  }
}
