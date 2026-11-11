import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hemolink/features/donaciones/data/api_donacion_repository.dart';
import 'package:hemolink/features/donaciones/domain/donacion.dart';

http.Response _json(Object data, int status) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  // El donante YA fue corregido a A negativo; la unidad conserva O positivo.
  final donacionJson = {
    'id': 'DON-1',
    'donanteId': 'D-1',
    'evaluacionId': 'EV001',
    'fechaExtraccion': '2026-11-03',
    'volumenMl': 450,
    'sedeId': 'sede-central',
    'responsableId': 'nursing-demo',
    'fechaRegistro': '2026-11-08T15:00:00.000Z',
    'donante': {'id': 'D-1', 'grupoAbo': 'A', 'factorRh': 'negativo'},
    'unidades': [
      {
        'id': 'u-uuid',
        'codigo': 'U-001',
        'donacionId': 'DON-1',
        'grupoAbo': 'O',
        'factorRh': 'positivo',
        'sedeId': 'sede-central',
        'estado': 'disponible',
        'fechaVencimiento': '2026-12-15',
      },
    ],
  };

  ApiDonacionRepository crear(
    http.Client cliente, {
    Future<String?> Function()? token,
  }) => ApiDonacionRepository(
    cliente: cliente,
    urlBase: 'http://127.0.0.1:8080',
    obtenerToken: token ?? () async => 'token-prueba',
  );

  final datos = DatosDonacion(
    donanteId: 'D-1',
    evaluacionId: 'EV001',
    fechaExtraccion: DateTime(2026, 11, 3),
    volumenMl: 450,
    codigosUnidades: ['U-001'],
  );

  test('DON1: guardar envía solo lo editable y el token', () async {
    final cliente = MockClient((solicitud) async {
      expect(solicitud.method, 'POST');
      expect(solicitud.url.path, '/api/donations');
      expect(solicitud.headers['Authorization'], 'Bearer token-prueba');
      final cuerpo = jsonDecode(solicitud.body) as Map<String, dynamic>;
      expect(cuerpo['fechaExtraccion'], '2026-11-03');
      expect(cuerpo['volumenMl'], 450);
      expect(cuerpo['unidades'], [
        {'codigo': 'U-001'},
      ]);
      // Sede, responsable, grupo y vencimiento los decide el servidor.
      for (final prohibido in [
        'sedeId',
        'responsableId',
        'fechaVencimiento',
        'grupoAbo',
      ]) {
        expect(cuerpo.containsKey(prohibido), isFalse, reason: prohibido);
      }
      return _json({'item': donacionJson}, 201);
    });
    final donacion = await crear(cliente).guardar(datos);
    expect(donacion.id, 'DON-1');
    expect(donacion.unidades.single.fechaVencimiento, DateTime(2026, 12, 15));
  });

  test('DON2: la unidad conserva su grupo de origen del servidor', () async {
    final cliente = MockClient((_) async => _json({'item': donacionJson}, 200));
    final donacion = (await crear(cliente).buscarPorId('DON-1'))!;
    expect(donacion.unidades.single.grupo, 'O+');
    expect(donacion.unidades.single.donacionId, donacion.id);
    expect(donacion.unidades.single.estado, EstadoUnidad.disponible);
    expect(() => donacion.unidades.add(donacion.unidades.first), throwsA(anything));
  });

  test('DON3: 404 es ausencia; 409 conserva mensaje y estado', () async {
    var estado = 404;
    final cliente = MockClient(
      (_) async => _json({'message': 'El código de unidad U-001 ya existe.'}, estado),
    );
    expect(await crear(cliente).buscarPorId('NO'), isNull);
    estado = 409;
    await expectLater(
      crear(cliente).guardar(datos),
      throwsA(
        isA<DonacionApiException>()
            .having((e) => e.codigo, 'codigo', 409)
            .having((e) => e.mensaje, 'mensaje', contains('ya existe')),
      ),
    );
  });

  test('DON4: sin token no llama al servidor; error de red no es éxito', () async {
    var llamadas = 0;
    final cliente = MockClient((_) async {
      llamadas++;
      throw http.ClientException('sin red');
    });
    await expectLater(
      crear(cliente, token: () async => null).guardar(datos),
      throwsA(isA<DonacionApiException>().having((e) => e.codigo, 'codigo', 401)),
    );
    expect(llamadas, 0);
    await expectLater(
      crear(cliente).guardar(datos),
      throwsA(isA<DonacionApiException>().having((e) => e.codigo, 'codigo', isNull)),
    );
  });

  test('DON5: respuesta incompleta se informa como error, no como donación', () async {
    final cliente = MockClient((_) async => _json({'item': {'id': 'x'}}, 201));
    await expectLater(
      crear(cliente).guardar(datos),
      throwsA(isA<DonacionApiException>()),
    );
  });
}
