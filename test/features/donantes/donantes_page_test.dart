import 'dart:async';

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

final donante = Donante(
  id: 'D001',
  rut: '12345678-5',
  nombre: 'María Soto',
  fechaNacimiento: DateTime(1998, 5, 10),
  pesoKg: 70,
  grupoAbo: 'O',
  factorRh: 'positivo',
  telefono: '912345678',
  usuarioRegistroId: 'ENF001',
  fechaRegistro: DateTime.utc(2026, 11, 5),
);

class RepoConsulta implements DonanteRepository {
  Future<List<Donante>> Function(String?, String?) consulta = (_, _) async => [
    donante,
  ];
  Future<Donante?> Function(String) ficha = (_) async => donante;
  final filtros = <(String?, String?)>[];
  final ids = <String>[];
  @override
  Future<List<Donante>> buscar({String? rut, String? nombre}) {
    filtros.add((rut, nombre));
    return consulta(rut, nombre);
  }

  @override
  Future<Donante?> buscarPorId(String id) {
    ids.add(id);
    return ficha(id);
  }

  @override
  Future<Donante> guardar(DatosDonante datos) => throw UnimplementedError();

  @override
  Future<Donante> actualizar(String id, DatosDonante datos) =>
      throw UnimplementedError();
}

Future<AuthSession> sesionPrueba(
  WidgetTester tester, {
  String? rol = 'nursing',
}) async {
  final sesion = AuthSession(
    tokenStore: MemoryTokenStore(),
    client: MockClient(
      (_) async => jsonResponse({
        'token': 'token',
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

Future<void> montar(
  WidgetTester tester,
  RepoConsulta repo, {
  String? rol = 'nursing',
}) async {
  final sesion = await sesionPrueba(tester, rol: rol);
  await tester.pumpWidget(
    MaterialApp(
      home: DonantesPage(sesion: sesion, repositorio: repo),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'UT01.3-D: vacío, resultados y fallo son distintos; reintentar conserva filtro',
    (tester) async {
      final repo = RepoConsulta()..consulta = (_, _) async => [];
      await montar(tester, repo);
      expect(
        find.text('No hay donantes registrados en esta sede.'),
        findsOneWidget,
      );
      repo.consulta = (_, _) async =>
          throw DonanteApiException(500, 'Fallo de consulta.');
      await tester.enterText(
        find.byKey(const Key('busqueda-donante')),
        'María',
      );
      await tester.tap(find.text('Buscar'));
      await tester.pumpAndSettle();
      expect(find.text('Fallo de consulta.'), findsOneWidget);
      expect(find.text('No se encontraron donantes.'), findsNothing);
      repo.consulta = (_, _) async => [donante];
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(repo.filtros.last, (null, 'María'));
      expect(find.text('María Soto'), findsOneWidget);
    },
  );

  testWidgets(
    'UT01.3-E: envía nombre y RUT al repositorio; RUT inválido se señala',
    (tester) async {
      final repo = RepoConsulta();
      await montar(tester, repo);
      await tester.enterText(
        find.byKey(const Key('busqueda-donante')),
        '12345678-5',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('RUT').last);
      await tester.pumpAndSettle();
      expect(repo.filtros.last, ('12345678-5', null));
      final llamadas = repo.filtros.length;
      await tester.enterText(find.byKey(const Key('busqueda-donante')), '123');
      await tester.tap(find.text('Buscar'));
      await tester.pumpAndSettle();
      expect(find.text('Ingresa un RUT válido para buscar.'), findsOneWidget);
      expect(repo.filtros.length, llamadas);
    },
  );

  testWidgets(
    'abre ficha persistida con todos los antecedentes y vuelve al listado',
    (tester) async {
      final repo = RepoConsulta();
      await montar(tester, repo);
      await tester.tap(find.text('María Soto'));
      await tester.pumpAndSettle();
      expect(repo.ids, ['D001']);
      for (final valor in [
        '12345678-5',
        '10/05/1998',
        '70 kg',
        'O positivo',
        '912345678',
        'ENF001',
        'D001',
      ]) {
        expect(find.text(valor), findsOneWidget);
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Buscar'), findsOneWidget);
    },
  );

  testWidgets('ficha distingue ausencia y fallo y permite reintentar', (
    tester,
  ) async {
    final repo = RepoConsulta()
      ..ficha = (_) async => throw DonanteApiException(500, 'Error de ficha.');
    await montar(tester, repo);
    await tester.tap(find.text('María Soto'));
    await tester.pumpAndSettle();
    expect(find.text('Error de ficha.'), findsOneWidget);
    repo.ficha = (_) async => null;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Donante no encontrado en esta sede.'), findsOneWidget);
  });

  testWidgets('respuestas fuera de orden no reemplazan la búsqueda vigente', (
    tester,
  ) async {
    final vieja = Completer<List<Donante>>();
    final nueva = Completer<List<Donante>>();
    final repo = RepoConsulta();
    await montar(tester, repo);
    repo.consulta = (_, nombre) =>
        nombre == 'vieja' ? vieja.future : nueva.future;
    await tester.enterText(find.byKey(const Key('busqueda-donante')), 'vieja');
    await tester.tap(find.text('Buscar'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('busqueda-donante')), 'nueva');
    await tester.tap(find.text('Buscar'));
    await tester.pump();
    nueva.complete([]);
    await tester.pumpAndSettle();
    vieja.complete([donante]);
    await tester.pumpAndSettle();
    expect(find.text('No se encontraron donantes.'), findsOneWidget);
    expect(find.text('María Soto'), findsNothing);
  });

  for (final rol in <String?>[null, 'hospital', 'inventory']) {
    testWidgets('acceso directo rechazado para $rol sin consultar datos', (
      tester,
    ) async {
      final repo = RepoConsulta();
      await montar(tester, repo, rol: rol);
      expect(
        find.text('Tu sesión no permite consultar donantes.'),
        findsOneWidget,
      );
      expect(repo.filtros, isEmpty);
    });
  }

  testWidgets('listado y ficha se recorren a 320px sin desbordamientos', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await montar(tester, RepoConsulta());
    await tester.ensureVisible(find.text('María Soto'));
    await tester.tap(find.text('María Soto'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ENF001'));
    expect(tester.takeException(), isNull);
  });
}
