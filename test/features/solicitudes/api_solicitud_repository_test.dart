import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/features/solicitudes/data/api_solicitud_repository.dart';
import 'package:hemolink/features/solicitudes/domain/solicitud.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> _solicitudJson({
  String id = 'sol-1',
  int numero = 1,
  String estado = 'pendiente',
  List<Map<String, dynamic>>? reservas,
  List<Map<String, dynamic>>? avisos,
  List<Map<String, dynamic>>? despachos,
}) => {
  'id': id,
  'numero': numero,
  'module': 'requests',
  'scopeId': 'hospital-demo',
  'hospitalId': 'hospital-demo',
  'responsableId': 'hospital-demo',
  'grupoAbo': 'O',
  'factorRh': 'positivo',
  'prioridad': 'urgente',
  'estado': estado,
  'cantidadSolicitada': 4,
  'cantidadDespachada': 1,
  'cantidadReservada': 1,
  'pendienteAsignar': 2,
  'pendienteEntregar': 3,
  'fechaRegistro': '2026-11-21T10:15:00.000Z',
  'reservas': ?reservas,
  'avisos': ?avisos,
  'despachos': ?despachos,
};

void main() {
  test('listar envía token, ignora semilla incompleta y parsea solicitudes', () async {
    final repo = ApiSolicitudRepository(
      obtenerToken: () async => 'token-hospital',
      cliente: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/requests');
        expect(request.headers['Authorization'], 'Bearer token-hospital');
        return _json({
          'items': [
            {'id': 'demo-requests', 'label': 'Solicitud ficticia de prueba'},
            _solicitudJson(),
          ],
        });
      }),
    );

    final items = await repo.listar();
    expect(items, hasLength(1));
    expect(items.single.id, 'sol-1');
    expect(items.single.numero, 1);
    expect(items.single.grupoAbo, 'O');
    expect(items.single.factorRh, 'positivo');
    expect(items.single.prioridad, 'urgente');
    expect(items.single.cantidadSolicitada, 4);
  });

  test('crear envía payload esperado y devuelve la solicitud creada', () async {
    final repo = ApiSolicitudRepository(
      obtenerToken: () async => 'token-hospital',
      cliente: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/requests');
        expect(jsonDecode(request.body), {
          'grupoAbo': 'AB',
          'factorRh': 'negativo',
          'cantidad': 3,
          'prioridad': 'normal',
        });
        return _json({
          'item': {
            ..._solicitudJson(id: 'sol-2', numero: 2),
            'grupoAbo': 'AB',
            'factorRh': 'negativo',
            'prioridad': 'normal',
            'cantidadSolicitada': 3,
            'cantidadDespachada': 0,
            'cantidadReservada': 0,
            'pendienteAsignar': 3,
            'pendienteEntregar': 3,
          },
        }, 201);
      }),
    );

    final creada = await repo.crear(
      const DatosSolicitud(
        grupoAbo: 'AB',
        factorRh: 'negativo',
        cantidad: 3,
        prioridad: 'normal',
      ),
    );
    expect(creada.id, 'sol-2');
    expect(creada.numero, 2);
    expect(creada.cantidadSolicitada, 3);
  });

  test('crear propaga errores de campo del servidor', () async {
    final repo = ApiSolicitudRepository(
      obtenerToken: () async => 'token-hospital',
      cliente: MockClient(
        (_) async => _json({
          'message': 'Revisa los datos de la solicitud.',
          'errors': {'cantidad': 'La cantidad solicitada debe ser un entero positivo.'},
        }, 400),
      ),
    );

    await expectLater(
      repo.crear(
        const DatosSolicitud(
          grupoAbo: 'O',
          factorRh: 'positivo',
          cantidad: 1,
          prioridad: 'normal',
        ),
      ),
      throwsA(
        isA<SolicitudApiException>()
            .having((e) => e.codigo, 'codigo', 400)
            .having(
              (e) => e.errores['cantidad'],
              'error en cantidad',
              contains('entero positivo'),
            ),
      ),
    );
  });

  test('buscarPorId devuelve null en 404 y parsea reservas, avisos y despachos en 200', () async {
    var estado = 404;
    final repo = ApiSolicitudRepository(
      obtenerToken: () async => 'token-hospital',
      cliente: MockClient((request) async {
        expect(request.url.path, '/api/requests/sol-9');
        if (estado == 404) {
          return _json({'message': 'Solicitud no encontrada.'}, 404);
        }
        return _json({
          'item': _solicitudJson(
            id: 'sol-9',
            numero: 9,
            estado: 'parcial',
            reservas: [
              {
                'id': 'u-1',
                'codigo': 'U-001',
                'sedeId': 'sede-central',
                'estado': 'reservada',
                'fechaVencimiento': '2026-12-01',
              },
            ],
            avisos: [
              {
                'id': 'av-1',
                'decision': 'aceptar',
                'cantidadFaltante': 2,
                'fecha': '2026-11-21',
                'usuarioRegistroId': 'inventory-demo',
              },
            ],
            despachos: [
              {
                'id': 'desp-1',
                'tipo': 'urgente',
                'sedeId': 'sede-central',
                'motivo': 'Cirugía de emergencia',
                'unidades': ['u-0'],
                'cantidad': 1,
                'responsableId': 'inventory-demo',
                'fechaRegistro': '2026-11-21T11:00:00.000Z',
              },
            ],
          ),
        });
      }),
    );

    expect(await repo.buscarPorId('sol-9'), isNull);

    estado = 200;
    final ficha = await repo.buscarPorId('sol-9');
    expect(ficha, isNotNull);
    expect(ficha!.reservas, hasLength(1));
    expect(ficha.reservas.single.codigo, 'U-001');
    expect(ficha.avisos, hasLength(1));
    expect(ficha.avisos.single.cantidadFaltante, 2);
    expect(ficha.despachos, hasLength(1));
    expect(ficha.despachos.single.tipo, 'urgente');
    expect(ficha.despachos.single.motivo, 'Cirugía de emergencia');
  });

  test('rechaza operar sin token y traduce timeout a SolicitudApiException', () async {
    final sinToken = ApiSolicitudRepository(
      obtenerToken: () async => null,
      cliente: MockClient((_) async => _json({})),
    );
    await expectLater(
      sinToken.listar(),
      throwsA(isA<SolicitudApiException>().having((e) => e.codigo, 'codigo', 401)),
    );

    final lento = ApiSolicitudRepository(
      obtenerToken: () async => 'token',
      tiempoEspera: const Duration(milliseconds: 10),
      cliente: MockClient((_) => Completer<http.Response>().future),
    );
    await expectLater(
      lento.listar(),
      throwsA(isA<SolicitudApiException>()),
    );
  });
}
