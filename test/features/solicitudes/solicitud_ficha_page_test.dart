import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/features/solicitudes/data/api_solicitud_repository.dart';
import 'package:hemolink/features/solicitudes/domain/solicitud.dart';
import 'package:hemolink/features/solicitudes/presentation/solicitud_ficha_page.dart';

import 'solicitudes_page_test.dart'
    show RepoSolicitudesPrueba, sesionConRol;

void main() {
  testWidgets(
    'Widget: ficha muestra carga, error con reintento, contadores con unidades, avisos y despachos',
    (tester) async {
      final sesion = await sesionConRol('hospital');
      addTearDown(sesion.dispose);
      final respuesta = Completer<Solicitud?>();
      final repo = RepoSolicitudesPrueba()
        ..alBuscarPorId = (_) => respuesta.future;

      await tester.pumpWidget(
        MaterialApp(
          home: SolicitudFichaPage(
            sesion: sesion,
            repositorio: repo,
            solicitudId: 'sol-10',
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      respuesta.completeError(
        const SolicitudApiException(500, 'No se pudo cargar la ficha.'),
      );
      await tester.pumpAndSettle();
      expect(find.text('No se pudo cargar la ficha.'), findsOneWidget);

      repo.alBuscarPorId = (_) async => Solicitud(
        id: 'sol-10',
        numero: 10,
        hospitalId: 'hospital-demo',
        responsableId: 'hosp-user-1',
        grupoAbo: 'A',
        factorRh: 'positivo',
        prioridad: 'urgente',
        estado: 'parcial',
        cantidadSolicitada: 8,
        cantidadDespachada: 2,
        cantidadReservada: 3,
        pendienteAsignar: 3,
        pendienteEntregar: 6,
        fechaRegistro: DateTime.utc(2026, 11, 21, 14, 30),
        reservas: [
          ReservaSolicitud(
            id: 'u-1',
            codigo: 'U-101',
            sedeId: 'sede-central',
            estado: 'reservada',
            fechaVencimiento: DateTime.utc(2026, 12, 10),
          ),
        ],
        avisos: const [
          AvisoSolicitud(
            id: 'av-1',
            decision: 'aceptar',
            cantidadFaltante: 3,
            fecha: '2026-11-21',
            usuarioRegistroId: 'inv-1',
          ),
        ],
        despachos: [
          DespachoSolicitud(
            id: 'desp-1',
            tipo: 'urgente',
            sedeId: 'sede-central',
            motivo: 'Pabellón 2',
            cantidad: 2,
            unidades: const ['u-01', 'u-02'],
            responsableId: 'inv-1',
            fechaRegistro: DateTime.utc(2026, 11, 21, 15, 0),
          ),
        ],
      );

      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(find.text('Solicitud #10'), findsOneWidget);
      expect(find.text('Estado: Parcial'), findsOneWidget);
      expect(find.text('Prioridad: Urgente'), findsOneWidget);
      expect(find.text('hosp-user-1'), findsOneWidget);
      expect(find.text('hospital-demo'), findsOneWidget);

      // Contadores con sus unidades (CA4)
      expect(find.text('Solicitadas'), findsOneWidget);
      expect(find.text('8 unidades'), findsOneWidget);
      expect(find.text('Reservadas'), findsOneWidget);
      expect(find.text('3 unidades'), findsWidgets);
      expect(find.text('Despachadas'), findsOneWidget);
      expect(find.text('2 unidades'), findsOneWidget);
      expect(find.text('Pendientes por asignar'), findsOneWidget);
      expect(find.text('Pendientes por entregar'), findsOneWidget);
      expect(find.text('6 unidades'), findsOneWidget);

      // Secciones de reservas, avisos y despachos
      expect(find.textContaining('U-101'), findsOneWidget);
      expect(find.textContaining('Faltante: 3 unidades'), findsOneWidget);
      expect(find.textContaining('Urgente'), findsWidgets);
      expect(find.textContaining('Pabellón 2'), findsOneWidget);
    },
  );

  testWidgets('ficha admite paneles extensibles y no desborda a 320px', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final sesion = await sesionConRol('inventory');
    addTearDown(sesion.dispose);
    final repo = RepoSolicitudesPrueba()
      ..alBuscarPorId = (_) async => null;

    await tester.pumpWidget(
      MaterialApp(
        home: SolicitudFichaPage(
          sesion: sesion,
          repositorio: repo,
          solicitudId: 'sol-inexistente',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Solicitud no encontrada.'), findsOneWidget);

    final fichaInicial = Solicitud(
      id: 'sol-1',
      numero: 1,
      hospitalId: 'hospital-demo',
      responsableId: 'hosp-1',
      grupoAbo: 'O',
      factorRh: 'negativo',
      prioridad: 'normal',
      estado: 'pendiente',
      cantidadSolicitada: 1,
      cantidadDespachada: 0,
      cantidadReservada: 0,
      pendienteAsignar: 1,
      pendienteEntregar: 1,
      fechaRegistro: DateTime.utc(2026, 11, 21, 9, 0),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SolicitudFichaPage(
          sesion: sesion,
          repositorio: repo,
          solicitudId: 'sol-1',
          solicitudInicial: fichaInicial,
          accionesBuilder: (_, solicitud, _) => [
            Text('Panel extensible para #${solicitud.numero}'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 unidad'), findsWidgets);
    expect(find.text('Panel extensible para #1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
