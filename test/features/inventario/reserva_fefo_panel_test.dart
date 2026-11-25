import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/core/access/auth_session.dart';
import 'package:hemolink/features/inventario/presentation/inventario_page.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../core/access/auth_session_test.dart'
    show MemoryTokenStore, jsonResponse, nursingUser;

const _ruta = '/api/requests/sol-1/reservations';
const _solicitud = 'Solicitud #1 · O- (normal) · hospital-demo';
const _conflicto = 'Cambió el stock o el saldo. Recalcula la propuesta.';
const _unidades = [
  {
    'id': 'u-norte',
    'codigo': 'U-NORTE',
    'sedeId': 'sede-norte',
    'grupoAbo': 'O',
    'factorRh': 'negativo',
    'fechaVencimiento': '2026-11-25',
  },
  {
    'id': 'u-sur',
    'codigo': 'U-SUR',
    'sedeId': 'sede-sur',
    'grupoAbo': 'O',
    'factorRh': 'negativo',
    'fechaVencimiento': '2026-11-27',
  },
];

http.Response _detalle({
  String? version = 'version-original',
  bool confirmado = false,
  List<Map<String, dynamic>> unidades = _unidades,
}) => jsonResponse({
  'saldos': {
    'cantidadSolicitada': 2,
    'cantidadDespachada': 0,
    'cantidadReservada': confirmado ? 2 : 0,
    'pendienteAsignar': confirmado ? 0 : 2,
    'pendienteEntregar': 2,
    'estado': confirmado ? 'reservado' : 'pendiente',
  },
  'reservas': confirmado ? unidades : [],
  'propuesta': {
    'unidades': confirmado ? [] : unidades,
    'faltante': 0,
    'stockElegible': confirmado ? 0 : 2,
    'version': version,
  },
});

Future<void> _abrirSolicitud(
  WidgetTester tester,
  http.Response Function(http.Request) responder,
) async {
  final sesion = AuthSession(
    tokenStore: MemoryTokenStore()..token = 'inventario-token',
    client: MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer inventario-token');
      switch (request.url.path) {
        case '/api/me':
          return jsonResponse({
            'user': {...nursingUser, 'role': 'inventory'},
          });
        case '/api/requests':
          return jsonResponse({
            'items': [
              {'id': 'demo-requests', 'label': 'Solicitud ficticia de prueba'},
              {
                'id': 'sol-1',
                'label': 'Solicitud #1 · O- (normal)',
                'hospitalId': 'hospital-demo',
                'cantidadSolicitada': 2,
              },
            ],
          });
        default:
          return responder(request);
      }
    }),
  );
  addTearDown(sesion.dispose);
  await sesion.restore();
  await tester.pumpWidget(MaterialApp(home: InventarioPage(sesion: sesion)));
  await tester.pumpAndSettle();
  await _tocar(tester, 'Reservar unidades');
  await _tocar(tester, 'Solicitud');
  expect(find.text('Solicitud ficticia de prueba'), findsNothing);
  await _tocar(tester, _solicitud);
}

Future<void> _tocar(WidgetTester tester, String texto) async {
  final objetivo = find.text(texto).last;
  if (!objetivo.hitTestable().tryEvaluate()) {
    await tester.dragUntilVisible(
      objetivo.hitTestable(),
      find.byType(CustomScrollView),
      const Offset(0, -180),
    );
  }
  await tester.tap(objetivo);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('UT08.4-A y widget: cancelar, confirmar y actualizar stock', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var confirmaciones = 0;
    var consultasStock = 0;
    await _abrirSolicitud(tester, (request) {
      if (request.url.path == '/api/inventory') {
        consultasStock++;
        final items = confirmaciones == 0 ? _unidades : [];
        return jsonResponse({'items': items, 'total': items.length});
      }
      expect(request.url.path, _ruta);
      if (request.method == 'GET') return _detalle();
      expect(request.method, 'POST');
      expect(jsonDecode(request.body), {'version': 'version-original'});
      confirmaciones++;
      return _detalle(confirmado: true, version: null);
    });

    expect(find.text('Pendientes por asignar: 2'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('1. U-NORTE')).dy,
      lessThan(tester.getTopLeft(find.text('2. U-SUR')).dy),
    );
    expect(find.text('sede-norte · Vence el 25/11/2026'), findsOneWidget);
    expect(find.text('sede-sur · Vence el 27/11/2026'), findsOneWidget);

    await _tocar(tester, 'Confirmar reserva');
    await _tocar(tester, 'Cancelar');
    expect(confirmaciones, 0);
    expect(consultasStock, 1);
    expect(find.text('Pendientes por asignar: 2'), findsOneWidget);

    await _tocar(tester, 'Confirmar reserva');
    await _tocar(tester, 'Confirmar');
    expect(confirmaciones, 1);
    expect(consultasStock, 2);
    expect(find.text('Reserva confirmada.'), findsOneWidget);
    expect(find.text('Estado: reservado'), findsOneWidget);
    expect(find.text('Pendientes por asignar: 0'), findsOneWidget);
    expect(find.text('Pendientes por entregar: 2'), findsOneWidget);
    expect(find.text('Reservas vigentes'), findsOneWidget);
    expect(find.text('sede-norte · Vence el 25/11/2026'), findsOneWidget);
    expect(find.text('sede-sur · Vence el 27/11/2026'), findsOneWidget);
    expect(find.text('0 unidades disponibles'), findsOneWidget);
    expect(find.text('Confirmar reserva'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'UT08.4-B: conflicto muestra recalcular y exige otra confirmación',
    (tester) async {
      var consultas = 0;
      var confirmaciones = 0;
      await _abrirSolicitud(tester, (request) {
        if (request.url.path == '/api/inventory') {
          return jsonResponse({'items': _unidades, 'total': _unidades.length});
        }
        expect(request.url.path, _ruta);
        if (request.method == 'GET') {
          consultas++;
          return consultas == 1
              ? _detalle()
              : _detalle(
                  version: 'version-nueva',
                  unidades: _unidades.reversed.toList(),
                );
        }
        confirmaciones++;
        return jsonResponse({'message': _conflicto}, 409);
      });

      await _tocar(tester, 'Confirmar reserva');
      await _tocar(tester, 'Confirmar');
      expect(find.text(_conflicto), findsOneWidget);
      expect(find.text('Reserva confirmada.'), findsNothing);
      expect(find.text('1. U-NORTE'), findsNothing);
      expect(find.text('Confirmar reserva'), findsNothing);
      expect(consultas, 1);

      await _tocar(tester, 'Recalcular propuesta');
      expect(consultas, 2);
      expect(confirmaciones, 1);
      expect(find.text(_conflicto), findsNothing);
      expect(find.text('1. U-SUR'), findsOneWidget);
      expect(find.text('Confirmar reserva'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
