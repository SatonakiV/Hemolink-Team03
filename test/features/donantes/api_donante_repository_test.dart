import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/core/access/auth_session.dart';
import 'package:hemolink/core/access/token_store.dart';
import 'package:hemolink/features/donantes/data/api_donante_repository.dart';
import 'package:hemolink/features/donantes/data/crear_repositorio_donantes.dart';
import 'package:hemolink/features/donantes/domain/donante.dart';
import 'package:hemolink/features/donantes/domain/validador_donante.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _TokensMemoria implements TokenStore {
  String? token;
  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String valor) async => token = valor;
  @override
  Future<void> delete() async => token = null;
}

void main() {
  final entrada = DatosDonante(
    rut: ' 12.345.678-5 ',
    nombre: ' María Prueba ',
    fechaNacimiento: DateTime(1998, 5, 10),
    pesoKg: 70,
    grupoAbo: ' o ',
    factorRh: ' POSITIVO ',
    telefono: ' 912345678 ',
  );
  final item = <String, dynamic>{
    'id': 'DON001',
    'rut': '12345678-5',
    'nombre': 'María Prueba',
    'fechaNacimiento': '1998-05-10',
    'pesoKg': 70,
    'grupoAbo': 'O',
    'factorRh': 'positivo',
    'telefono': '912345678',
    'usuarioRegistroId': 'ENF001',
    'fechaRegistro': '2026-11-09T15:00:00.000Z',
  };
  http.Response respuesta(Object datos, [int estado = 200]) => http.Response(
    jsonEncode(datos),
    estado,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  ApiDonanteRepository repositorio(
    Future<http.Response> Function(http.Request) enviar, {
    Future<String?> Function()? obtenerToken,
    Duration tiempoEspera = const Duration(seconds: 10),
  }) {
    final cliente = MockClient(enviar);
    addTearDown(cliente.close);
    return ApiDonanteRepository(
      cliente: cliente,
      obtenerToken: obtenerToken ?? () async => 'token-prueba',
      urlBase: 'http://servidor.test:8080',
      tiempoEspera: tiempoEspera,
    );
  }

  Matcher errorApi([int? estado]) => throwsA(
    isA<DonanteApiException>().having((e) => e.codigo, 'estado HTTP', estado),
  );

  test('UT01.2: guardar valida y envía solo antecedentes; devuelve la ficha confirmada', () async {
    final repo = repositorio((peticion) async {
      expect(peticion.method, 'POST');
      expect(peticion.url.toString(), 'http://servidor.test:8080/api/donors');
      expect(peticion.headers['Authorization'], 'Bearer token-prueba');
      expect(jsonDecode(peticion.body), {
        'rut': '12345678-5',
        'nombre': 'María Prueba',
        'fechaNacimiento': '1998-05-10',
        'pesoKg': 70,
        'grupoAbo': 'O',
        'factorRh': 'positivo',
        'telefono': '912345678',
      });
      return respuesta({'item': item}, 201);
    });
    final guardado = await repo.guardar(entrada);
    expect(guardado.id, 'DON001');
    expect(guardado.nombre, 'María Prueba');
    expect(guardado.pesoKg, 70.0);
    expect(guardado.fechaNacimiento, DateTime(1998, 5, 10));
    expect(guardado.usuarioRegistroId, 'ENF001');
    expect(guardado.fechaRegistro, DateTime.utc(2026, 11, 9, 15));
  });

  test('UT01.2-B: entrada inválida no llega al servidor', () async {
    final repo = repositorio(
      (_) async => fail('No debe enviar datos inválidos.'),
    );
    await expectLater(
      repo.guardar(const DatosDonante()),
      throwsA(isA<ValidacionDonanteException>()),
    );
  });

  test('UT01.2-C: conserva errores de duplicado por campo', () async {
    final repo = repositorio(
      (_) async => respuesta({
        'message': 'Ya existe un donante con ese RUT.',
        'errors': {'rut': 'RUT repetido.'},
      }, 409),
    );
    await expectLater(
      repo.guardar(entrada),
      throwsA(
        isA<DonanteApiException>()
            .having((e) => e.codigo, 'estado', 409)
            .having((e) => e.errores, 'campos', {'rut': 'RUT repetido.'}),
      ),
    );
  });

  test(
    'UT01.2-D: envía el RUT como filtro y recupera la misma identidad',
    () async {
      final repo = repositorio((peticion) async {
        expect(peticion.method, 'GET');
        expect(peticion.url.queryParameters, {'rut': '12.345.678-5'});
        return respuesta({
          'items': [item],
        });
      });
      expect((await repo.buscar(rut: '12.345.678-5')).single.id, 'DON001');
    },
  );

  test('UT01.2-D: codifica nombres con acentos, espacios y & sin añadir parámetros', () async {
    final repo = repositorio((peticion) async {
      expect(peticion.url.queryParameters, {'nombre': 'MARÍA & Prueba'});
      return respuesta({
        'items': [item],
      });
    });
    expect(
      (await repo.buscar(nombre: ' MARÍA & Prueba ')).single.rut,
      '12345678-5',
    );
  });

  test('UT01.2-D: filtros vacíos consultan el listado', () async {
    final repo = repositorio((peticion) async {
      expect(peticion.url.queryParameters, isEmpty);
      return respuesta({'items': []});
    });
    expect(await repo.buscar(rut: ' ', nombre: ''), isEmpty);
  });

  test('UT01.2-D: ficha inexistente devuelve null', () async {
    final repo = repositorio((peticion) async {
      expect(peticion.url.path, '/api/donors/ausente');
      return respuesta({'message': 'Donante no encontrado.'}, 404);
    });
    expect(await repo.buscarPorId('ausente'), isNull);
  });

  for (final datos in [
    {},
    {'item': null},
    {'item': {}},
  ]) {
    test(
      'UT01.2-E: una ficha inválida con HTTP 200 informa error: $datos',
      () async {
        final repo = repositorio((_) async => respuesta(datos));
        await expectLater(repo.buscarPorId('DON001'), errorApi(200));
      },
    );
  }

  test(
    'UT01.2-D: el identificador se codifica como un segmento de ruta',
    () async {
      final repo = repositorio((peticion) async {
        expect(peticion.url.pathSegments.last, 'id/ajeno?foo=bar');
        expect(peticion.url.queryParameters, isEmpty);
        return respuesta({'item': item});
      });
      expect((await repo.buscarPorId('id/ajeno?foo=bar'))!.id, 'DON001');
    },
  );

  final operaciones = <String, Future<Object?> Function(ApiDonanteRepository)>{
    'guardar': (repo) => repo.guardar(entrada),
    'buscar': (repo) => repo.buscar(),
    'ficha': (repo) => repo.buscarPorId('DON001'),
  };
  for (final operacion in operaciones.entries) {
    for (final estado in [401, 403, 500]) {
      test('UT01.2-E: ${operacion.key} propaga HTTP $estado', () async {
        final repo = repositorio(
          (_) async => respuesta({'message': 'Operación rechazada.'}, estado),
        );
        await expectLater(operacion.value(repo), errorApi(estado));
      });
    }
    test('UT01.2-E: ${operacion.key} informa fallo de red', () async {
      final repo = repositorio(
        (_) async => throw http.ClientException('sin red'),
      );
      await expectLater(operacion.value(repo), errorApi());
    });
    test(
      'UT01.2-E: ${operacion.key} informa tiempo de espera agotado',
      () async {
        final repo = repositorio(
          (_) => Completer<http.Response>().future,
          tiempoEspera: const Duration(milliseconds: 1),
        );
        await expectLater(operacion.value(repo), errorApi());
      },
    );
    test('CP01-08: ${operacion.key} exige token antes de enviar', () async {
      final repo = repositorio(
        (_) async => fail('No debe acceder sin sesión.'),
        obtenerToken: () async => null,
      );
      await expectLater(operacion.value(repo), errorApi(401));
    });
  }

  for (final estado in [200, 202, 204]) {
    test('UT01.2-E: guardar exige confirmación HTTP 201, no $estado', () async {
      final repo = repositorio((_) async => respuesta({'item': item}, estado));
      await expectLater(repo.guardar(entrada), errorApi(estado));
    });
  }

  test(
    'UT01.2-E: guardar rechaza una confirmación sin ficha completa',
    () async {
      final repo = repositorio(
        (_) async => respuesta({
          'item': {'id': 'DON001'},
        }, 201),
      );
      await expectLater(repo.guardar(entrada), errorApi(201));
    },
  );

  for (final contenido in ['no es JSON', '[]', '{}', '{"items":[{}]}']) {
    test(
      'UT01.2-E: respuesta inválida no se transforma en lista vacía: $contenido',
      () async {
        final repo = repositorio((_) async => http.Response(contenido, 200));
        await expectLater(repo.buscar(), errorApi(200));
      },
    );
  }

  test(
    'UT01.2-E: una fecha imposible en la ficha no se corrige silenciosamente',
    () async {
      final repo = repositorio(
        (_) async => respuesta({
          'item': {...item, 'fechaNacimiento': '1998-02-30'},
        }),
      );
      await expectLater(repo.buscarPorId('DON001'), errorApi(200));
    },
  );

  test('integración: la fábrica utiliza el token vigente de AuthSession y respeta logout', () async {
    final cliente = MockClient((peticion) async {
      if (peticion.url.path == '/api/login') {
        return respuesta({
          'token': 'sesion-real',
          'user': {
            'id': 'ENF001',
            'role': 'nursing',
            'isVerified': true,
            'siteId': 'sede-central',
            'hospitalId': null,
          },
        });
      }
      expect(peticion.headers['Authorization'], 'Bearer sesion-real');
      if (peticion.url.path == '/api/logout') {
        return respuesta({'message': 'Sesión cerrada.'});
      }
      expect(peticion.url.host, 'servidor.test');
      return respuesta({'item': item}, 201);
    });
    final sesion = AuthSession(
      baseUrl: 'http://servidor.test:8080',
      client: cliente,
      tokenStore: _TokensMemoria(),
    );
    addTearDown(sesion.dispose);
    final repo = crearRepositorioDonantes(sesion: sesion, cliente: cliente);
    await expectLater(repo.guardar(entrada), errorApi(401));
    await sesion.login('enfermeria@hemolink.test', 'clave');
    expect((await repo.guardar(entrada)).id, 'DON001');
    await sesion.logout();
    await expectLater(repo.guardar(entrada), errorApi(401));
  });
}
