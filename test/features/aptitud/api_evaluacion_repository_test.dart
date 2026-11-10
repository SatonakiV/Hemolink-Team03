import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hemolink/features/aptitud/data/api_evaluacion_repository.dart';
import 'package:hemolink/features/aptitud/domain/evaluacion_aptitud.dart';
import 'package:hemolink/features/aptitud/data/crear_repositorio_evaluaciones.dart';
import 'package:hemolink/core/access/auth_session.dart';

import '../../core/access/auth_session_test.dart'
    show MemoryTokenStore, nursingUser, jsonResponse;

void main() {
  final evaluacion = EvaluacionAptitud(
    id: 'EV001',
    donanteId: 'D001',
    resultado: ResultadoAptitud.apto,
    fechaEvaluacion: DateTime(2026, 11, 5),
    fechaFinVigencia: DateTime(2026, 11, 20),
    responsableId: 'ENF001',
    fechaRegistro: DateTime.utc(2026, 11, 8),
  );

  final evaluacionJson = {
    'id': 'EV001',
    'donanteId': 'D001',
    'resultado': 'apto',
    'fechaEvaluacion': '2026-11-05',
    'fechaFinVigencia': '2026-11-20',
    'fechaHabilitacion': null,
    'responsableId': 'ENF001',
    'fechaRegistro': '2026-11-08T15:00:00.000Z',
  };

  ApiEvaluacionRepository crearRepositorio(
    http.Client cliente, {
    Future<String?> Function()? obtenerToken,
  }) {
    return ApiEvaluacionRepository(
      cliente: cliente,
      urlBase: 'http://127.0.0.1:8080',
      obtenerToken: obtenerToken ?? () async => 'token-prueba',
    );
  }

  test('API1: guardar envía la evaluación y el token', () async {
    final cliente = MockClient((solicitud) async {
      expect(solicitud.method, 'POST');
      expect(solicitud.url.path, '/api/evaluations');
      expect(solicitud.headers['Authorization'], 'Bearer token-prueba');

      final datos = jsonDecode(solicitud.body) as Map<String, dynamic>;

      expect(datos['id'], 'EV001');
      expect(datos['donanteId'], 'D001');
      expect(datos['resultado'], 'apto');
      expect(datos['fechaEvaluacion'], '2026-11-05');
      expect(datos['fechaFinVigencia'], '2026-11-20');

      return http.Response(jsonEncode({'item': evaluacionJson}), 201);
    });

    final repositorio = crearRepositorio(cliente);

    await repositorio.guardar(evaluacion);
    cliente.close();
  });

  test('API2: buscarPorId recupera una evaluación', () async {
    final cliente = MockClient((solicitud) async {
      expect(solicitud.method, 'GET');
      expect(solicitud.url.path, '/api/evaluations/EV001');

      return http.Response(jsonEncode({'item': evaluacionJson}), 200);
    });

    final repositorio = crearRepositorio(cliente);
    final resultado = await repositorio.buscarPorId('EV001');

    expect(resultado, isNotNull);
    expect(resultado!.id, 'EV001');
    expect(resultado.donanteId, 'D001');
    expect(resultado.resultado, ResultadoAptitud.apto);
    expect(resultado.responsableId, 'ENF001');

    cliente.close();
  });

  test('API3: buscarActual recupera la última evaluación', () async {
    final cliente = MockClient((solicitud) async {
      expect(solicitud.method, 'GET');
      expect(solicitud.url.path, '/api/evaluations');
      expect(solicitud.url.queryParameters['donanteId'], 'D001');

      return http.Response(
        jsonEncode({
          'items': [
            {
              ...evaluacionJson,
              'id': 'EV002',
              'resultado': 'rechazado',
              'fechaEvaluacion': '2026-11-04',
              'fechaRegistro': '2026-11-09T15:00:00.000Z',
              'fechaFinVigencia': null,
            },
            evaluacionJson,
          ],
        }),
        200,
      );
    });

    final repositorio = crearRepositorio(cliente);
    final actual = await repositorio.buscarActual('D001');

    expect(actual, isNotNull);
    expect(actual!.id, 'EV002');
    expect(actual.resultado, ResultadoAptitud.rechazado);

    cliente.close();
  });

  test('API4: propaga el rechazo HTTP 403 del servidor', () async {
    final cliente = MockClient((solicitud) async {
      return http.Response(
        jsonEncode({'message': 'Tu perfil no puede gestionar evaluaciones.'}),
        403,
      );
    });

    final repositorio = crearRepositorio(cliente);

    await expectLater(
      repositorio.guardar(evaluacion),
      throwsA(
        isA<EvaluacionApiException>().having(
          (error) => error.codigo,
          'Código HTTP',
          403,
        ),
      ),
    );

    cliente.close();
  });

  test('API5: impide registrar sin sesión', () async {
    final cliente = MockClient((solicitud) async {
      fail('No debe enviarse una solicitud sin token.');
    });

    final repositorio = crearRepositorio(
      cliente,
      obtenerToken: () async => null,
    );

    await expectLater(
      repositorio.guardar(evaluacion),
      throwsA(
        isA<EvaluacionApiException>().having(
          (error) => error.codigo,
          'Código HTTP',
          401,
        ),
      ),
    );

    cliente.close();
  });

  test('API6: la fábrica comparte la sesión activa y deja de enviar al cerrar sesión', () async {
    var registrosEnviados = 0;
    final cliente = MockClient((solicitud) async {
      if (solicitud.url.path == '/api/login') {
        return jsonResponse({
          'token': 'sesion-compartida',
          'user': nursingUser,
        });
      }
      expect(solicitud.headers['Authorization'], 'Bearer sesion-compartida');
      expect(solicitud.url.host, 'sesion.test');
      if (solicitud.url.path == '/api/logout') {
        return jsonResponse({'message': 'Sesión cerrada.'});
      }
      registrosEnviados++;
      return jsonResponse({'item': evaluacionJson}, 201);
    });
    final sesion = AuthSession(
      baseUrl: 'http://sesion.test',
      client: cliente,
      tokenStore: MemoryTokenStore(),
    );
    addTearDown(sesion.dispose);
    final repo = crearRepositorioEvaluaciones(sesion: sesion, cliente: cliente);
    final sinSesion = throwsA(
      isA<EvaluacionApiException>().having(
        (error) => error.codigo,
        'estado HTTP',
        401,
      ),
    );
    await expectLater(repo.guardar(evaluacion), sinSesion);
    await sesion.login('enfermeria@hemolink.test', 'secret');
    await repo.guardar(evaluacion);
    expect(registrosEnviados, 1);
    await sesion.logout();
    await expectLater(repo.guardar(evaluacion), sinSesion);
    expect(registrosEnviados, 1);
  });
}
