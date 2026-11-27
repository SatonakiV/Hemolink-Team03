import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/core/access/auth_session.dart';
import 'package:hemolink/features/solicitudes/data/api_solicitud_repository.dart';
import 'package:hemolink/features/solicitudes/data/simulated_solicitud_repository.dart';
import 'package:hemolink/features/solicitudes/data/solicitud_repository.dart';
import 'package:hemolink/features/solicitudes/domain/solicitud.dart';
import 'package:hemolink/features/solicitudes/presentation/solicitudes_page.dart';
import 'package:http/testing.dart';

import '../../core/access/auth_session_test.dart'
    show MemoryTokenStore, jsonResponse, nursingUser;

Solicitud crearSolicitudEjemplo({
  String id = 'sol-1',
  int numero = 1,
  String hospitalId = 'hospital-demo',
  String grupoAbo = 'O',
  String factorRh = 'positivo',
  String prioridad = 'normal',
  String estado = 'pendiente',
  int solicitadas = 3,
  int despachadas = 0,
  int reservadas = 0,
  DateTime? fechaRegistro,
}) => Solicitud(
  id: id,
  numero: numero,
  hospitalId: hospitalId,
  responsableId: 'hospital-demo',
  grupoAbo: grupoAbo,
  factorRh: factorRh,
  prioridad: prioridad,
  estado: estado,
  cantidadSolicitada: solicitadas,
  cantidadDespachada: despachadas,
  cantidadReservada: reservadas,
  pendienteAsignar: solicitadas - despachadas - reservadas,
  pendienteEntregar: solicitadas - despachadas,
  fechaRegistro: fechaRegistro ?? DateTime.utc(2026, 11, 21, 10, 0),
);

class RepoSolicitudesPrueba implements SolicitudRepository {
  Future<List<Solicitud>> Function() alListar = () async => [];
  Future<Solicitud> Function(DatosSolicitud) alCrear = (datos) async =>
      crearSolicitudEjemplo(
        numero: 12,
        grupoAbo: datos.grupoAbo!,
        factorRh: datos.factorRh!,
        prioridad: datos.prioridad!,
        solicitadas: datos.cantidad!,
      );
  Future<Solicitud?> Function(String) alBuscarPorId = (_) async =>
      crearSolicitudEjemplo(numero: 12);

  final llamadasCrear = <DatosSolicitud>[];
  final llamadasListar = <int>[];
  final llamadasBuscar = <String>[];

  @override
  Future<List<Solicitud>> listar() {
    llamadasListar.add(llamadasListar.length + 1);
    return alListar();
  }

  @override
  Future<Solicitud> crear(DatosSolicitud datos) {
    llamadasCrear.add(datos);
    return alCrear(datos);
  }

  @override
  Future<Solicitud?> buscarPorId(String id) {
    llamadasBuscar.add(id);
    return alBuscarPorId(id);
  }
}

Future<AuthSession> sesionConRol(String? rol, {String? hospitalId}) async {
  final sesion = AuthSession(
    tokenStore: MemoryTokenStore(),
    client: MockClient(
      (_) async => jsonResponse({
        'token': 'token-test',
        'user': {
          ...nursingUser,
          'id': rol == 'hospital' ? (hospitalId ?? 'hospital-demo') : 'user-1',
          'role': rol ?? 'nursing',
          'siteId': rol == 'hospital' ? null : 'sede-central',
          'hospitalId': rol == 'hospital'
              ? (hospitalId ?? 'hospital-demo')
              : null,
        },
      }),
    ),
  );
  if (rol != null) await sesion.login('test@hemolink.test', 'secret');
  return sesion;
}

void main() {
  testWidgets(
    'Widget: distingue carga, lista vacía, error con reintento y listado con contadores',
    (tester) async {
      final sesion = await sesionConRol('hospital');
      addTearDown(sesion.dispose);
      final repo = RepoSolicitudesPrueba();
      var respuesta = Completer<List<Solicitud>>();
      repo.alListar = () => respuesta.future;

      await tester.pumpWidget(
        MaterialApp(
          home: SolicitudesPage(sesion: sesion, repositorio: repo),
        ),
      );
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('No hay solicitudes registradas.'), findsNothing);

      respuesta.complete([]);
      await tester.pumpAndSettle();
      expect(find.text('No hay solicitudes registradas.'), findsOneWidget);

      repo.alListar = () async =>
          throw const SolicitudApiException(500, 'Error al consultar bandeja.');
      await tester.tap(find.byTooltip('Actualizar solicitudes'));
      await tester.pumpAndSettle();
      expect(find.text('Error al consultar bandeja.'), findsOneWidget);
      expect(find.text('No hay solicitudes registradas.'), findsNothing);

      repo.alListar = () async => [
        crearSolicitudEjemplo(
          id: 'sol-7',
          numero: 7,
          prioridad: 'urgente',
          grupoAbo: 'A',
          factorRh: 'negativo',
          solicitadas: 5,
          reservadas: 2,
          despachadas: 1,
        ),
      ];
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Solicitud #7 · A-'), findsOneWidget);
      expect(
        find.textContaining('Solicitadas: 5 · Reservadas: 2 · Despachadas: 1'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'UT06.2-B: crear solicitud desde bandeja de hospital muestra número y abre ficha',
    (tester) async {
      final sesion = await sesionConRol('hospital');
      addTearDown(sesion.dispose);
      final repoSimulado = RepositorioSolicitudesSimulado(
        hospitalIdUsuario: 'hospital-demo',
        rolUsuario: 'hospital',
        responsableIdUsuario: 'hospital-demo',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SolicitudesPage(sesion: sesion, repositorio: repoSimulado),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No hay solicitudes registradas.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('nueva-solicitud-btn')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('solicitud-grupo-abo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('O').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('solicitud-factor-rh')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Positivo').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('solicitud-cantidad')),
        '4',
      );

      await tester.tap(find.byKey(const Key('solicitud-prioridad')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Urgente').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Guardar solicitud'));
      await tester.tap(find.text('Guardar solicitud'));
      await tester.pumpAndSettle();

      expect(
        find.text('Solicitud #1 registrada correctamente.'),
        findsOneWidget,
      );
      expect(find.text('Solicitud #1'), findsOneWidget);
      expect(find.text('4 unidades'), findsWidgets);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Solicitud #1 · O+'), findsOneWidget);
    },
  );

  testWidgets(
    'inventario ve bandeja ordenada sin botón de creación y enfermería es rechazada',
    (tester) async {
      final sesionInv = await sesionConRol('inventory');
      addTearDown(sesionInv.dispose);
      final repo = RepoSolicitudesPrueba()
        ..alListar = () async => [
          crearSolicitudEjemplo(
            id: 'sol-2',
            numero: 2,
            hospitalId: 'hospital-regional',
            prioridad: 'urgente',
            fechaRegistro: DateTime.utc(2026, 11, 21, 9, 0),
          ),
          crearSolicitudEjemplo(
            id: 'sol-1',
            numero: 1,
            hospitalId: 'hospital-demo',
            prioridad: 'normal',
            fechaRegistro: DateTime.utc(2026, 11, 21, 8, 0),
          ),
        ];

      await tester.pumpWidget(
        MaterialApp(
          home: SolicitudesPage(sesion: sesionInv, repositorio: repo),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nueva-solicitud-btn')), findsNothing);
      expect(
        tester.getTopLeft(find.text('Solicitud #2 · O+')).dy,
        lessThan(tester.getTopLeft(find.text('Solicitud #1 · O+')).dy),
      );
      expect(find.textContaining('hospital-regional'), findsOneWidget);

      final sesionEnf = await sesionConRol('nursing');
      addTearDown(sesionEnf.dispose);
      final repoEnf = RepoSolicitudesPrueba();
      await tester.pumpWidget(
        MaterialApp(
          home: SolicitudesPage(sesion: sesionEnf, repositorio: repoEnf),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Tu sesión no permite consultar solicitudes.'),
        findsOneWidget,
      );
      expect(repoEnf.llamadasListar, isEmpty);
    },
  );

  testWidgets('bandeja de solicitudes no desborda a 320px', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final sesion = await sesionConRol('hospital');
    addTearDown(sesion.dispose);
    final repo = RepoSolicitudesPrueba()
      ..alListar = () async => [crearSolicitudEjemplo()];

    await tester.pumpWidget(
      MaterialApp(
        home: SolicitudesPage(sesion: sesion, repositorio: repo),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
