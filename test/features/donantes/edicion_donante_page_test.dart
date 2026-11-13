import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/core/access/auth_session.dart';
import 'package:hemolink/features/donantes/data/api_donante_repository.dart';
import 'package:hemolink/features/donantes/data/donante_repository.dart';
import 'package:hemolink/features/donantes/domain/donante.dart';
import 'package:hemolink/features/donantes/presentation/donantes_page.dart';
import 'package:http/testing.dart';

import '../../core/access/auth_session_test.dart'
    show MemoryTokenStore, jsonResponse, nursingUser;

class RepoPrueba implements DonanteRepository {
  Future<List<Donante>> Function(String?, String?) consulta = (_, _) async => [];
  Future<Donante?> Function(String) ficha = (_) async => null;
  Future<Donante> Function(String, DatosDonante) actualizarFn =
      (_, _) => throw UnimplementedError();

  final llamadasActualizar = <(String, DatosDonante)>[];

  @override
  Future<List<Donante>> buscar({String? rut, String? nombre}) =>
      consulta(rut, nombre);

  @override
  Future<Donante?> buscarPorId(String id) => ficha(id);

  @override
  Future<Donante> guardar(DatosDonante datos) => throw UnimplementedError();

  @override
  Future<Donante> actualizar(String id, DatosDonante datos) {
    llamadasActualizar.add((id, datos));
    return actualizarFn(id, datos);
  }
}

final donanteInicial = Donante(
  id: 'DON-001',
  rut: '12345678-5',
  nombre: 'María Soto',
  fechaNacimiento: DateTime(1998, 5, 10),
  pesoKg: 68.5,
  grupoAbo: 'O',
  factorRh: 'positivo',
  telefono: '912345678',
  usuarioRegistroId: 'ENF-ORIGINAL',
  fechaRegistro: DateTime.utc(2026, 11, 1),
);

Future<AuthSession> sesionPrueba(
  WidgetTester tester, {
  String? rol = 'nursing',
}) async {
  final sesion = AuthSession(
    tokenStore: MemoryTokenStore(),
    client: MockClient(
      (_) async => jsonResponse({
        'token': 'token-test',
        'user': {
          ...nursingUser,
          'role': rol ?? 'nursing',
          'siteId': rol == 'hospital' ? null : 'sede-central',
          'hospitalId': rol == 'hospital' ? 'hospital-demo' : null,
        },
      }),
    ),
  );
  addTearDown(sesion.dispose);
  if (rol != null) await sesion.login('test@test', 'secret');
  return sesion;
}

Future<void> montarFicha(
  WidgetTester tester,
  RepoPrueba repo, {
  String? rol = 'nursing',
}) async {
  final sesion = await sesionPrueba(tester, rol: rol);
  await tester.pumpWidget(
    MaterialApp(
      home: DonanteFichaPage(
        sesion: sesion,
        repositorio: repo,
        donanteId: 'DON-001',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('T04.5: GUI de edición del donante', () {
    testWidgets('UT04.5-A: la carga inicial conserva los datos del donante correcto', (
      tester,
    ) async {
      final repo = RepoPrueba()..ficha = (_) async => donanteInicial;
      await montarFicha(tester, repo);

      expect(find.text('Editar antecedentes'), findsOneWidget);
      await tester.tap(find.text('Editar antecedentes'));
      await tester.pumpAndSettle();

      // Verifica campos precargados
      expect(find.text('Editar donante'), findsOneWidget);
      final rutField = tester.widget<TextField>(find.byKey(const Key('edicion-rut')));
      final nombreField =
          tester.widget<TextField>(find.byKey(const Key('edicion-nombre')));
      final fechaField =
          tester.widget<TextField>(find.byKey(const Key('edicion-fecha-nacimiento')));
      final pesoField =
          tester.widget<TextField>(find.byKey(const Key('edicion-peso')));
      final telefonoField =
          tester.widget<TextField>(find.byKey(const Key('edicion-telefono')));

      expect(rutField.controller?.text, '12345678-5');
      expect(nombreField.controller?.text, 'María Soto');
      expect(fechaField.controller?.text, '10/05/1998');
      expect(pesoField.controller?.text, '68.5');
      expect(telefonoField.controller?.text, '912345678');
      expect(find.text('Guardar cambios'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
    });

    testWidgets('UT04.5-B: Cancelar no invoca guardado', (tester) async {
      final repo = RepoPrueba()..ficha = (_) async => donanteInicial;
      await montarFicha(tester, repo);

      await tester.tap(find.text('Editar antecedentes'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('edicion-nombre')),
        'Nombre Modificado',
      );
      await tester.ensureVisible(find.text('Cancelar'));
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(repo.llamadasActualizar, isEmpty);
      // Volvió a la ficha con los valores persistidos
      expect(find.text('María Soto'), findsOneWidget);
      expect(find.text('Nombre Modificado'), findsNothing);
    });

    testWidgets('UT04.5-C: validación fallida expone el error', (tester) async {
      final repo = RepoPrueba()..ficha = (_) async => donanteInicial;
      await montarFicha(tester, repo);

      await tester.tap(find.text('Editar antecedentes'));
      await tester.pumpAndSettle();

      // Datos inválidos
      await tester.enterText(find.byKey(const Key('edicion-rut')), '12.345.678-9'); // DV incorrecto
      await tester.enterText(find.byKey(const Key('edicion-nombre')), '');
      await tester.enterText(find.byKey(const Key('edicion-peso')), '-10');
      await tester.enterText(find.byKey(const Key('edicion-telefono')), '');

      await tester.ensureVisible(find.text('Guardar cambios'));
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();

      expect(repo.llamadasActualizar, isEmpty);
      expect(find.text('Ingresa un RUT con formato y dígito verificador válidos.'), findsOneWidget);
      expect(find.text('El nombre es obligatorio.'), findsOneWidget);
      expect(find.text('El peso debe ser un número positivo en kilogramos.'), findsOneWidget);
      expect(find.text('El teléfono es obligatorio.'), findsOneWidget);
    });

    testWidgets(
      'UT04.5-D: éxito actualiza la ficha y fallo mantiene el formulario sin confirmar',
      (tester) async {
        var donanteActual = donanteInicial;
        final repo = RepoPrueba()
          ..ficha = (_) async => donanteActual;
        repo.actualizarFn = (id, datos) async {
            if (datos.rut == '22.222.222-2') {
              throw DonanteApiException(409, 'Ya existe un donante con ese RUT.', errores: {
                'rut': 'Ya existe un donante con ese RUT.',
              });
            }
            donanteActual = Donante(
              id: id,
              rut: datos.rut!,
              nombre: datos.nombre!,
              fechaNacimiento: datos.fechaNacimiento!,
              pesoKg: datos.pesoKg!,
              grupoAbo: datos.grupoAbo!,
              factorRh: datos.factorRh!,
              telefono: datos.telefono!,
              usuarioRegistroId: donanteActual.usuarioRegistroId,
              fechaRegistro: donanteActual.fechaRegistro,
              usuarioModificacionId: 'ENF-MODIFICADOR',
              fechaModificacion: DateTime.utc(2026, 11, 10, 16),
            );
            return donanteActual;
          };

        await montarFicha(tester, repo);
        await tester.tap(find.text('Editar antecedentes'));
        await tester.pumpAndSettle();

        // 1. Caso Fallo (409 por RUT duplicado)
        await tester.enterText(find.byKey(const Key('edicion-rut')), '22.222.222-2');
        await tester.enterText(find.byKey(const Key('edicion-telefono')), '999888777');
        await tester.ensureVisible(find.text('Guardar cambios'));
        await tester.tap(find.text('Guardar cambios'));
        await tester.pumpAndSettle();

        // Error visible al lado del dato
        expect(find.text('Ya existe un donante con ese RUT.'), findsOneWidget);
        // Formulario conserva lo escrito
        final telefonoField =
            tester.widget<TextField>(find.byKey(const Key('edicion-telefono')));
        expect(telefonoField.controller?.text, '999888777');
        // No hay confirmación de éxito
        expect(find.text('Antecedentes actualizados correctamente.'), findsNothing);

        // 2. Caso Éxito (corregir RUT al propio)
        await tester.enterText(find.byKey(const Key('edicion-rut')), '12.345.678-5');
        await tester.ensureVisible(find.text('Guardar cambios'));
        await tester.tap(find.text('Guardar cambios'));
        await tester.pumpAndSettle();

        // Confirmación mostrada
        expect(find.text('Antecedentes actualizados correctamente.'), findsOneWidget);
        // Regresa a la ficha actualizada
        expect(find.text('999888777'), findsOneWidget);
      },
    );

    testWidgets('UT04.5-E: rol no autorizado no carga ni envía la edición', (
      tester,
    ) async {
      for (final rol in ['hospital', 'inventory']) {
        final repo = RepoPrueba()..ficha = (_) async => donanteInicial;
        await montarFicha(tester, repo, rol: rol);

        expect(find.text('Editar antecedentes'), findsNothing);
        expect(find.text('Tu sesión no permite consultar donantes.'), findsOneWidget);
        expect(repo.llamadasActualizar, isEmpty);
      }
    });
  });
}
