import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/core/access/auth_session.dart';
import 'package:hemolink/features/inventario/presentation/inventario_page.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../core/access/auth_session_test.dart'
    show MemoryTokenStore, jsonResponse, nursingUser;

const _unidadNorte = {
  'codigo': 'U-NORTE',
  'sedeId': 'sede-norte',
  'grupoAbo': 'O',
  'factorRh': 'negativo',
  'fechaVencimiento': '2026-11-25',
};

const _unidadCentral = {
  'codigo': 'U-CENTRAL',
  'sedeId': 'sede-central',
  'grupoAbo': 'A',
  'factorRh': 'positivo',
  'fechaVencimiento': '2026-11-30',
};

Future<void> _abrirInventario(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) responder,
) async {
  final sesion = AuthSession(
    tokenStore: MemoryTokenStore()..token = 'inventario-token',
    client: MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer inventario-token');
      if (request.url.path == '/api/me') {
        return jsonResponse({
          'user': {...nursingUser, 'role': 'inventory'},
        });
      }
      expect(request.method, 'GET');
      expect(request.url.path, '/api/inventory');
      return responder(request);
    }),
  );
  addTearDown(sesion.dispose);
  await sesion.restore();
  await tester.pumpWidget(MaterialApp(home: InventarioPage(sesion: sesion)));
}

Future<void> _elegir(
  WidgetTester tester,
  String etiqueta,
  String opcion,
) async {
  await tester.tap(
    find.ancestor(
      of: find.text(etiqueta),
      matching: find.byType(DropdownButtonFormField<String>),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(opcion).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('combina sede, ABO y Rh y conserva los filtros al actualizar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final consultas = <Map<String, String>>[];
    bool hayStockNorte = true;
    await _abrirInventario(tester, (request) async {
      final filtros = request.url.queryParameters;
      consultas.add(filtros);
      final items = [
        if (hayStockNorte) _unidadNorte,
        if (!filtros.containsKey('sedeId')) _unidadCentral,
      ];
      return jsonResponse({'items': items, 'total': items.length});
    });
    await tester.pumpAndSettle();
    expect(find.text('2 unidades disponibles'), findsOneWidget);
    expect(find.text('O-'), findsOneWidget);
    expect(find.text('sede-norte\nVence el 25/11/2026'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('U-NORTE')).dy,
      lessThan(tester.getTopLeft(find.text('U-CENTRAL')).dy),
    );

    await _elegir(tester, 'Sede', 'sede-norte');
    await _elegir(tester, 'Grupo ABO', 'O');
    await _elegir(tester, 'Factor Rh', 'Negativo');
    const combinados = {
      'sedeId': 'sede-norte',
      'grupoAbo': 'O',
      'factorRh': 'negativo',
    };
    expect(consultas, [
      <String, String>{},
      {'sedeId': 'sede-norte'},
      {'sedeId': 'sede-norte', 'grupoAbo': 'O'},
      combinados,
    ]);
    expect(find.text('1 unidad disponible'), findsOneWidget);
    expect(find.text('U-CENTRAL'), findsNothing);

    hayStockNorte = false;
    await tester.tap(find.byTooltip('Actualizar stock'));
    await tester.pumpAndSettle();
    expect(consultas.last, combinados);
    expect(consultas, hasLength(5));
    expect(find.text('0 unidades disponibles'), findsOneWidget);
    expect(find.text('sede-norte'), findsOneWidget);
    expect(find.text('U-NORTE'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('distingue carga, vacío y error y permite reintentar a 320 px', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var respuesta = Completer<http.Response>();
    await _abrirInventario(tester, (_) => respuesta.future);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('0 unidades disponibles'), findsNothing);

    respuesta.complete(
      jsonResponse({'message': 'No se pudo completar la operación.'}, 500),
    );
    await tester.pumpAndSettle();
    expect(find.text('No se pudo completar la operación.'), findsOneWidget);
    expect(find.text('0 unidades disponibles'), findsNothing);

    respuesta = Completer<http.Response>();
    await tester.tap(find.byTooltip('Actualizar stock'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('No se pudo completar la operación.'), findsNothing);
    respuesta.complete(jsonResponse({'items': [], 'total': 0}));
    await tester.pumpAndSettle();
    expect(find.text('0 unidades disponibles'), findsOneWidget);
    expect(
      find.text('No hay unidades para los filtros seleccionados.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
