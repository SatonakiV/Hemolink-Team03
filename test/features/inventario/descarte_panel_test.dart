import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/core/access/auth_session.dart';
import 'package:hemolink/features/inventario/data/descarte_repository.dart';
import 'package:hemolink/features/inventario/presentation/descarte_controller.dart';
import 'package:hemolink/features/inventario/presentation/descarte_panel.dart';
import 'package:hemolink/features/inventario/presentation/inventario_page.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../../core/access/auth_session_test.dart'
    show MemoryTokenStore, jsonResponse, nursingUser;

UnidadDescarte unidad({
  String id = 'u1',
  String codigo = 'U-001',
  String estado = 'disponible',
  String? pedido,
  String? motivo,
}) => UnidadDescarte(
  id: id,
  codigo: codigo,
  sedeId: 'sede-central',
  grupoAbo: 'O',
  factorRh: 'positivo',
  estado: estado,
  vencimiento: DateTime(2026, 12, 10),
  pedidoReservaId: pedido,
  motivoDescarte: motivo,
  fechaDescarte: motivo == null ? null : DateTime(2026, 11, 19),
);

ResultadoDescarte descartada(
  UnidadDescarte u,
  String motivo, {
  bool repetido = false,
  List<String> pedidos = const [],
}) => ResultadoDescarte(
  unidad: unidad(id: u.id, codigo: u.codigo, estado: 'descartada', motivo: motivo),
  repetido: repetido,
  pedidosActualizados: pedidos,
);

class RepoFalso implements DescarteRepository {
  RepoFalso([List<UnidadDescarte>? unidades])
    : unidades = {for (final u in unidades ?? [unidad()]) u.codigo: u};

  final Map<String, UnidadDescarte> unidades;
  final llamadas = <(String, String)>[];
  late Future<ResultadoDescarte> Function(String id, String motivo) responder =
      (id, motivo) async =>
          descartada(unidades.values.firstWhere((u) => u.id == id), motivo);

  @override
  Future<UnidadDescarte> buscar(String codigo) async {
    final encontrada = unidades[codigo.toUpperCase()];
    if (encontrada == null) {
      throw const AuthException(
        'No hay una unidad con ese código en tu sede.',
        status: 404,
      );
    }
    return encontrada;
  }

  @override
  Future<ResultadoDescarte> descartar(String unidadId, String motivo) {
    llamadas.add((unidadId, motivo));
    return responder(unidadId, motivo);
  }
}

class Montaje {
  Montaje(this.repo);
  final RepoFalso repo;
  int recargas = 0;
}

Future<Montaje> montar(WidgetTester tester, [RepoFalso? repo]) async {
  final m = Montaje(repo ?? RepoFalso());
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DescartePanel(
            repositorio: m.repo,
            alDescartar: () => m.recargas++,
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Descartar unidad'));
  await tester.pumpAndSettle();
  return m;
}

Future<void> tocar(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> buscar(WidgetTester tester, String codigo) async {
  await tester.enterText(find.byKey(const Key('descarte-codigo')), codigo);
  await tocar(tester, find.byKey(const Key('descarte-buscar')));
}

Future<void> escribirMotivo(WidgetTester tester, String motivo) async {
  final campo = find.byKey(const Key('descarte-motivo'));
  await tester.ensureVisible(campo);
  await tester.enterText(campo, motivo);
  await tester.pumpAndSettle();
}

FilledButton botonConfirmar(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('descarte-confirmar')));

void main() {
  group('UT07.2-A: el motivo en blanco bloquea la confirmación', () {
    test('lógica: sin motivo no llama al repositorio', () async {
      final repo = RepoFalso();
      final c = DescarteController(repo);
      await c.buscar('U-001');
      expect(c.puedeConfirmar, isFalse);
      c.cambiarMotivo('   ');
      expect(c.puedeConfirmar, isFalse);
      expect(await c.descartar(), isFalse);
      expect(repo.llamadas, isEmpty);
      expect(c.error, 'Indica el motivo del descarte.');
    });

    testWidgets('GUI: el botón queda deshabilitado sin motivo', (tester) async {
      final m = await montar(tester);
      await buscar(tester, 'u-001');
      expect(find.text('Estado: Disponible'), findsOneWidget);
      expect(botonConfirmar(tester).onPressed, isNull);

      await escribirMotivo(tester, '    ');
      expect(botonConfirmar(tester).onPressed, isNull);

      await escribirMotivo(tester, 'Bolsa dañada');
      expect(botonConfirmar(tester).onPressed, isNotNull);
      expect(m.repo.llamadas, isEmpty);
    });
  });

  testWidgets('UT07.2-B: cancelar evita la llamada y conserva el estado', (
    tester,
  ) async {
    final m = await montar(tester);
    await buscar(tester, 'U-001');
    await escribirMotivo(tester, 'Bolsa dañada');
    await tocar(tester, find.byKey(const Key('descarte-confirmar')));
    expect(find.text('Confirmar descarte'), findsOneWidget);

    await tocar(tester, find.text('Cancelar'));
    expect(m.repo.llamadas, isEmpty);
    expect(m.recargas, 0);
    expect(find.text('Estado: Disponible'), findsOneWidget);
    expect(find.byKey(const Key('descarte-exito')), findsNothing);
  });

  testWidgets('UT07.2-C: un fallo conserva lo escrito; el éxito pide recargar stock', (
    tester,
  ) async {
    var falla = true;
    final repo = RepoFalso();
    repo.responder = (id, motivo) async {
      if (falla) {
        throw const AuthException(
          'No se pudo completar la operación.',
          status: 500,
        );
      }
      return descartada(repo.unidades['U-001']!, motivo);
    };
    final m = await montar(tester, repo);
    await buscar(tester, 'U-001');
    await escribirMotivo(tester, 'Bolsa dañada');
    await tocar(tester, find.byKey(const Key('descarte-confirmar')));
    await tocar(tester, find.text('Descartar'));

    expect(find.text('No se pudo completar la operación.'), findsOneWidget);
    expect(find.byKey(const Key('descarte-exito')), findsNothing);
    expect(m.recargas, 0);
    final motivo = tester.widget<TextField>(
      find.byKey(const Key('descarte-motivo')),
    );
    expect(motivo.controller?.text, 'Bolsa dañada');
    expect(find.text('Estado: Disponible'), findsOneWidget);

    falla = false;
    await tocar(tester, find.byKey(const Key('descarte-confirmar')));
    await tocar(tester, find.text('Descartar'));
    expect(find.text('Unidad descartada.'), findsOneWidget);
    expect(m.recargas, 1, reason: 'el éxito pide recargar el stock');
    expect(find.text('Estado: Descartada'), findsOneWidget);
    expect(
      find.text('Descartada el 19/11/2026. Motivo: Bolsa dañada'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('descarte-confirmar')), findsNothing);
    expect(m.repo.llamadas, [('u1', 'Bolsa dañada'), ('u1', 'Bolsa dañada')]);
  });

  group('Widget: muestra cada mensaje', () {
    testWidgets('código vacío y unidad inexistente u otra sede', (tester) async {
      await montar(tester);
      await buscar(tester, '   ');
      expect(find.text('Ingresa el código de la unidad.'), findsOneWidget);

      await buscar(tester, 'U-NORTE');
      expect(
        find.text('No hay una unidad con ese código en tu sede.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('descarte-ficha')), findsNothing);
    });

    testWidgets('unidad despachada: se informa y no ofrece descartar', (
      tester,
    ) async {
      await montar(tester, RepoFalso([unidad(estado: 'despachada')]));
      await buscar(tester, 'U-001');
      expect(find.text('Estado: Despachada'), findsOneWidget);
      expect(
        find.text('Una unidad despachada no se puede descartar.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('descarte-confirmar')), findsNothing);
      expect(find.byKey(const Key('descarte-motivo')), findsNothing);
    });

    testWidgets('rechazo del servidor (409) se muestra sin éxito', (
      tester,
    ) async {
      final repo = RepoFalso()
        ..responder = (_, _) async => throw const AuthException(
          'Una unidad despachada no se puede descartar.',
          status: 409,
        );
      final m = await montar(tester, repo);
      await buscar(tester, 'U-001');
      await escribirMotivo(tester, 'Bolsa dañada');
      await tocar(tester, find.byKey(const Key('descarte-confirmar')));
      await tocar(tester, find.text('Descartar'));
      expect(
        find.text('Una unidad despachada no se puede descartar.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('descarte-exito')), findsNothing);
      expect(m.recargas, 0);
    });

    testWidgets('descarte repetido conserva el primer registro', (
      tester,
    ) async {
      final repo = RepoFalso();
      repo.responder = (id, _) async => descartada(
        repo.unidades['U-001']!,
        'Motivo original',
        repetido: true,
      );
      await montar(tester, repo);
      await buscar(tester, 'U-001');
      await escribirMotivo(tester, 'Otro motivo');
      await tocar(tester, find.byKey(const Key('descarte-confirmar')));
      await tocar(tester, find.text('Descartar'));
      expect(
        find.text(
          'La unidad ya estaba descartada. Se conserva el primer registro.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Descartada el 19/11/2026. Motivo: Motivo original'),
        findsOneWidget,
      );
    });

    testWidgets('unidad reservada: avisa y libera la reserva', (tester) async {
      final repo = RepoFalso([unidad(estado: 'reservada', pedido: 'PED-1')]);
      repo.responder = (id, motivo) async => descartada(
        repo.unidades['U-001']!,
        motivo,
        pedidos: ['PED-1'],
      );
      await montar(tester, repo);
      await buscar(tester, 'U-001');
      expect(find.text('Reservada para la solicitud PED-1'), findsOneWidget);
      await escribirMotivo(tester, 'Rotura');
      await tocar(tester, find.byKey(const Key('descarte-confirmar')));
      expect(find.textContaining('se liberará su reserva'), findsOneWidget);
      await tocar(tester, find.text('Descartar'));
      expect(
        find.text(
          'Unidad descartada. Se liberó su reserva y se actualizó el pedido.',
        ),
        findsOneWidget,
      );
    });
  });

  group('ApiDescarteRepository', () {
    Future<(AuthSession, List<http.Request>)> sesion(
      http.Response Function(http.Request) responder,
    ) async {
      final pedidos = <http.Request>[];
      final s = AuthSession(
        tokenStore: MemoryTokenStore()..token = 'inventario-token',
        client: MockClient((request) async {
          if (request.url.path == '/api/me') {
            return jsonResponse({
              'user': {...nursingUser, 'role': 'inventory'},
            });
          }
          pedidos.add(request);
          return responder(request);
        }),
      );
      await s.restore();
      return (s, pedidos);
    }

    final item = {
      'id': 'u1',
      'codigo': 'U-001',
      'sedeId': 'sede-central',
      'grupoAbo': 'O',
      'factorRh': 'positivo',
      'estado': 'reservada',
      'fechaVencimiento': '2026-12-10',
      'reserva': {'reservaId': 'u1', 'pedidoId': 'PED-1'},
      'descarte': null,
    };

    test('busca por código y descarta enviando solo el motivo', () async {
      final (s, pedidos) = await sesion((request) {
        if (request.method == 'GET') return jsonResponse({'item': item});
        return jsonResponse({
          'item': {
            ...item,
            'estado': 'descartada',
            'reserva': null,
            'descarte': {'motivo': 'Rotura', 'fecha': '2026-11-19'},
          },
          'repetido': false,
          'reservasInvalidadas': [
            {'reservaId': 'u1', 'pedidoId': 'PED-1'},
          ],
          'pedidos': [
            {'id': 'PED-1', 'pendienteAsignar': 1},
          ],
        });
      });
      addTearDown(s.dispose);
      final repo = ApiDescarteRepository(s);

      final encontrada = await repo.buscar('U-001');
      expect(pedidos.single.url.path, '/api/inventory/lookup');
      expect(pedidos.single.url.queryParameters['codigo'], 'U-001');
      expect(encontrada.pedidoReservaId, 'PED-1');

      final resultado = await repo.descartar('u1', 'Rotura');
      expect(pedidos.last.method, 'POST');
      expect(pedidos.last.url.path, '/api/inventory/u1/discard');
      expect(jsonDecode(pedidos.last.body), {'motivo': 'Rotura'});
      expect(resultado.unidad.estado, 'descartada');
      expect(resultado.unidad.motivoDescarte, 'Rotura');
      expect(resultado.pedidosActualizados, ['PED-1']);
    });

    test('el rechazo del servidor llega con su mensaje', () async {
      final (s, _) = await sesion(
        (_) => jsonResponse({
          'message': 'No hay una unidad con ese código en tu sede.',
        }, 404),
      );
      addTearDown(s.dispose);
      await expectLater(
        ApiDescarteRepository(s).buscar('U-NORTE'),
        throwsA(
          isA<AuthException>()
              .having((e) => e.status, 'status', 404)
              .having(
                (e) => e.message,
                'message',
                'No hay una unidad con ese código en tu sede.',
              ),
        ),
      );
    });
  });

  testWidgets('T07.2: la pantalla de inventario muestra el panel de descarte', (
    tester,
  ) async {
    final s = AuthSession(
      tokenStore: MemoryTokenStore()..token = 'inventario-token',
      client: MockClient((request) async {
        switch (request.url.path) {
          case '/api/me':
            return jsonResponse({
              'user': {...nursingUser, 'role': 'inventory'},
            });
          case '/api/inventory':
            return jsonResponse({'items': [], 'total': 0});
          default:
            return jsonResponse({'message': 'Recurso no encontrado.'}, 404);
        }
      }),
    );
    addTearDown(s.dispose);
    await s.restore();
    await tester.pumpWidget(MaterialApp(home: InventarioPage(sesion: s)));
    await tester.pumpAndSettle();

    final titulo = find.text('Descartar unidad');
    await tester.dragUntilVisible(
      titulo.hitTestable(),
      find.byType(CustomScrollView),
      const Offset(0, -180),
    );
    await tester.tap(titulo);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('descarte-codigo')), findsOneWidget);
  });
}