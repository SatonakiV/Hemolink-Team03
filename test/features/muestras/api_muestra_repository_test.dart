import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hemolink/features/muestras/data/api_muestra_repository.dart';
import 'package:hemolink/features/muestras/data/muestra_repository.dart';

http.Response _json(Object data, int status) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  final muestraJson = {
    'id': 'muestra-uuid-1',
    'module': 'samples',
    'codigo': 'M-001',
    'donacionId': 'DON-1',
    'donanteId': 'D-1',
    'scopeId': 'sede-central',
    'responsableId': 'nursing-demo',
    'fechaRegistro': '2026-11-08T15:00:00.000Z',
  };

  ApiMuestraRepository crear(
    http.Client cliente, {
    Future<String?> Function()? token,
  }) => ApiMuestraRepository(
    cliente: cliente,
    urlBase: 'http://127.0.0.1:8080',
    obtenerToken: token ?? () async => 'token-prueba',
  );

  final datos = DatosMuestra(
    codigo: ' M-001 ',
    donacionId: ' DON-1 ',
  );

  test('MUESTRA1: guardar envía solo código y donación con token', () async {
    final cliente = MockClient((solicitud) async {
      expect(solicitud.method, 'POST');
      expect(solicitud.url.path, '/api/samples');
      expect(solicitud.headers['Authorization'], 'Bearer token-prueba');
      final cuerpo = jsonDecode(solicitud.body) as Map<String, dynamic>;
      expect(cuerpo['codigo'], 'M-001');
      expect(cuerpo['donacionId'], 'DON-1');
      return _json({'item': muestraJson}, 201);
    });
    final muestra = await crear(cliente).guardar(datos);
    expect(muestra.id, 'muestra-uuid-1');
    expect(muestra.codigo, 'M-001');
    expect(muestra.donacionId, 'DON-1');
  });

  test('MUESTRA2: buscar por id y buscar con filtro donacionId', () async {
    final cliente = MockClient((solicitud) async {
      if (solicitud.url.path == '/api/samples/muestra-uuid-1') {
        return _json({'item': muestraJson}, 200);
      }
      if (solicitud.url.path == '/api/samples') {
        expect(solicitud.url.queryParameters['donacionId'], 'DON-1');
        return _json({
          'items': [muestraJson],
        }, 200);
      }
      return _json({}, 404);
    });
    final repo = crear(cliente);
    final encontrada = await repo.buscarPorId('muestra-uuid-1');
    expect(encontrada?.codigo, 'M-001');

    final lista = await repo.buscar(donacionId: 'DON-1');
    expect(lista.length, 1);
    expect(lista.first.codigo, 'M-001');
  });

  test('MUESTRA3: 404 es ausencia en buscarPorId; 409 conserva mensaje y estado en guardar', () async {
    var estado = 404;
    final cliente = MockClient(
      (_) async => _json({'message': 'Ya existe una muestra con ese código.'}, estado),
    );
    expect(await crear(cliente).buscarPorId('NO'), isNull);
    estado = 409;
    await expectLater(
      crear(cliente).guardar(datos),
      throwsA(
        isA<MuestraApiException>()
            .having((e) => e.codigo, 'codigo', 409)
            .having((e) => e.mensaje, 'mensaje', contains('Ya existe')),
      ),
    );
  });

  test('MUESTRA4: sin token lanza 401; error de red se propaga', () async {
    var llamadas = 0;
    final cliente = MockClient((_) async {
      llamadas++;
      throw http.ClientException('sin red');
    });
    await expectLater(
      crear(cliente, token: () async => null).guardar(datos),
      throwsA(isA<MuestraApiException>().having((e) => e.codigo, 'codigo', 401)),
    );
    expect(llamadas, 0);
    await expectLater(
      crear(cliente).guardar(datos),
      throwsA(isA<MuestraApiException>().having((e) => e.codigo, 'codigo', isNull)),
    );
  });
}
