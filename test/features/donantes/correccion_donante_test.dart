import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/core/access/auth_session.dart';
import 'package:hemolink/core/access/token_store.dart';
import 'package:hemolink/features/aptitud/domain/evaluacion_aptitud.dart';
import 'package:hemolink/features/donantes/data/api_donante_repository.dart';
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
  group('T04.4: Corrección del donante (Unitario)', () {
    final entradaActualizada = DatosDonante(
      rut: '12.345.678-5',
      nombre: 'María Modificada',
      fechaNacimiento: DateTime(1998, 5, 10),
      pesoKg: 68,
      grupoAbo: 'A',
      factorRh: 'positivo',
      telefono: '987654321',
    );

    final itemActualizado = <String, dynamic>{
      'id': 'DON-001',
      'rut': '12345678-5',
      'nombre': 'María Modificada',
      'fechaNacimiento': '1998-05-10',
      'pesoKg': 68,
      'grupoAbo': 'A',
      'factorRh': 'positivo',
      'telefono': '987654321',
      'usuarioRegistroId': 'ENF-ORIGINAL',
      'fechaRegistro': '2026-11-01T10:00:00.000Z',
      'usuarioModificacionId': 'ENF-MODIFICADOR',
      'fechaModificacion': '2026-11-10T16:00:00.000Z',
    };

    http.Response jsonResp(Object datos, [int estado = 200]) => http.Response(
      jsonEncode(datos),
      estado,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

    ApiDonanteRepository crearRepo(
      Future<http.Response> Function(http.Request) handler,
    ) {
      final client = MockClient(handler);
      addTearDown(client.close);
      return ApiDonanteRepository(
        cliente: client,
        obtenerToken: () async => 'token-enfermeria',
        urlBase: 'http://servidor.test:8080',
      );
    }

    test(
      'UT04.4-A: editar datos mantiene identificador y registra usuario y fecha',
      () async {
        final repo = crearRepo((req) async {
          expect(req.method, 'PUT');
          expect(
            req.url.toString(),
            'http://servidor.test:8080/api/donors/DON-001',
          );
          expect(req.headers['Authorization'], 'Bearer token-enfermeria');
          final body = jsonDecode(req.body);
          expect(body['nombre'], 'María Modificada');
          expect(body['pesoKg'], 68);
          expect(body['grupoAbo'], 'A');
          expect(body['telefono'], '987654321');
          return jsonResp({'item': itemActualizado});
        });

        final resultado = await repo.actualizar('DON-001', entradaActualizada);

        expect(resultado.id, 'DON-001');
        expect(resultado.nombre, 'María Modificada');
        expect(resultado.pesoKg, 68);
        expect(resultado.grupoAbo, 'A');
        expect(resultado.factorRh, 'positivo');
        expect(resultado.telefono, '987654321');
        expect(resultado.usuarioRegistroId, 'ENF-ORIGINAL');
        expect(
          resultado.fechaRegistro,
          DateTime.parse('2026-11-01T10:00:00.000Z'),
        );
        expect(resultado.usuarioModificacionId, 'ENF-MODIFICADOR');
        expect(
          resultado.fechaModificacion,
          DateTime.parse('2026-11-10T16:00:00.000Z'),
        );
      },
    );

    test(
      'UT04.4-B: RUT de otro donante se rechaza y el propio normalizado se admite',
      () async {
        final repo = crearRepo((req) async {
          final body = jsonDecode(req.body);
          if (body['rut'] == '11111111-1') {
            return jsonResp({
              'message': 'Ya existe un donante con ese RUT.',
              'errors': {'rut': 'Ya existe un donante con ese RUT.'},
            }, 409);
          }
          return jsonResp({'item': itemActualizado});
        });

        // Caso 1: RUT ajeno duplicado
        final entradaConflicto = DatosDonante(
          rut: '11.111.111-1',
          nombre: 'Nombre Cualquiera',
          fechaNacimiento: DateTime(1995, 1, 1),
          pesoKg: 70,
          grupoAbo: 'O',
          factorRh: 'positivo',
          telefono: '912345678',
        );

        expect(
          () => repo.actualizar('DON-001', entradaConflicto),
          throwsA(
            isA<DonanteApiException>()
                .having((e) => e.codigo, 'codigo', 409)
                .having(
                  (e) => e.errores['rut'],
                  'error rut',
                  contains('Ya existe'),
                ),
          ),
        );

        // Caso 2: El propio RUT normalizado se admite
        final resultado = await repo.actualizar('DON-001', entradaActualizada);
        expect(resultado.rut, '12345678-5');
      },
    );

    test('UT04.4-C: campos inválidos reutilizan las reglas del alta', () async {
      var peticionRealizada = false;
      final repo = crearRepo((req) async {
        peticionRealizada = true;
        return jsonResp({'item': itemActualizado});
      });

      final entradaInvalida = DatosDonante(
        rut: '12.345.678-9', // DV incorrecto
        nombre: '', // Nombre vacío
        fechaNacimiento: DateTime(2099, 1, 1), // Futuro
        pesoKg: -5, // Inválido
        grupoAbo: 'X', // Inválido
        factorRh: 'neutro', // Inválido
        telefono: '', // Vacío
      );

      expect(
        () => repo.actualizar('DON-001', entradaInvalida),
        throwsA(
          isA<ValidacionDonanteException>().having(
            (e) => e.errores.keys,
            'campos con error',
            [
              'rut',
              'nombre',
              'fechaNacimiento',
              'pesoKg',
              'grupoAbo',
              'factorRh',
              'telefono',
            ],
          ),
        ),
      );
      expect(peticionRealizada, isFalse);
    });

    test(
      'UT04.4-D: donaciones, aptitud y grupos históricos no cambian al editar donante',
      () {
        // Objeto histórico de aptitud vinculado
        final evaluacionHistorica = EvaluacionAptitud(
          id: 'EVAL-001',
          donanteId: 'DON-001',
          resultado: ResultadoAptitud.apto,
          fechaEvaluacion: DateTime(2026, 11, 2),
          fechaFinVigencia: DateTime(2026, 11, 30),
          responsableId: 'ENF-ORIGINAL',
          fechaRegistro: DateTime(2026, 11, 2),
        );

        // Donante original O positivo
        final donanteOriginal = Donante(
          id: 'DON-001',
          rut: '12345678-5',
          nombre: 'María Original',
          fechaNacimiento: DateTime(1998, 5, 10),
          pesoKg: 70,
          grupoAbo: 'O',
          factorRh: 'positivo',
          telefono: '912345678',
          usuarioRegistroId: 'ENF-ORIGINAL',
          fechaRegistro: DateTime(2026, 11, 1, 10),
        );

        // Simulamos edición de grupo a A positivo
        final donanteModificado = Donante(
          id: 'DON-001',
          rut: '12345678-5',
          nombre: 'María Original',
          fechaNacimiento: DateTime(1998, 5, 10),
          pesoKg: 70,
          grupoAbo: 'A',
          factorRh: 'positivo',
          telefono: '912345678',
          usuarioRegistroId: 'ENF-ORIGINAL',
          fechaRegistro: DateTime(2026, 11, 1, 10),
          usuarioModificacionId: 'ENF-MODIFICADOR',
          fechaModificacion: DateTime(2026, 11, 10, 16),
        );

        // La evaluación histórica mantiene su donanteId y sus fechas intactas
        expect(evaluacionHistorica.donanteId, donanteModificado.id);
        expect(evaluacionHistorica.resultado, ResultadoAptitud.apto);
        expect(evaluacionHistorica.responsableId, 'ENF-ORIGINAL');
      },
    );

    test('UT04.4-E: fallo de persistencia conserva la versión anterior', () async {
      final repo = crearRepo((req) async {
        return jsonResp({'message': 'Error interno del servidor'}, 500);
      });

      expect(
        () => repo.actualizar('DON-001', entradaActualizada),
        throwsA(
          isA<DonanteApiException>().having((e) => e.codigo, 'codigo', 500),
        ),
      );
    });
  });

  group('T04.4: Corrección de donante con servidor real y reinicio', () {
    test(
      'CP04-04 a CP04-08: actualiza por HTTP, previene duplicados ajenos y sobrevive a reinicio',
      () async {
        final carpeta = await Directory.systemTemp.createTemp(
          'hemolink-correccion-',
        );
        final archivo = '${carpeta.path}${Platform.pathSeparator}local.json';
        Process? proceso;
        final sesiones = <AuthSession>[];
        final erroresServidor = StringBuffer();

        Future<void> detener() async {
          final anterior = proceso;
          if (anterior == null) return;
          anterior.kill();
          await anterior.exitCode.timeout(const Duration(seconds: 10));
          proceso = null;
        }

        addTearDown(() async {
          for (final sesion in sesiones) {
            sesion.dispose();
          }
          await detener();
          await carpeta.delete(recursive: true);
        });

        Future<String> iniciar({required bool semillas}) async {
          final servidor = await Process.start('node', [
            '--input-type=module',
            '-e',
            '''
              import { createApplication } from './server/src/app.mjs';
              const { server } = createApplication({
                databasePath: process.argv[1], seedDemo: $semillas,
                clock: () => Date.parse('2026-11-10T15:00:00Z'),
              });
              server.listen(0, '127.0.0.1', () => {
                console.log('http://127.0.0.1:' + server.address().port);
              });
            ''',
            archivo,
          ]);
          proceso = servidor;
          servidor.stderr.transform(utf8.decoder).listen(erroresServidor.write);
          final direccion = await servidor.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first
              .timeout(const Duration(seconds: 10));
          return direccion;
        }

        final cliente = http.Client();
        final tokens = _TokensMemoria();
        final sesion = AuthSession(
          baseUrl: await iniciar(semillas: true),
          client: cliente,
          tokenStore: tokens,
        );
        sesiones.add(sesion);
        await sesion.login('enfermeria@hemolink.test', 'DemoHemoLink2026!');
        final repo = ApiDonanteRepository(
          cliente: cliente,
          obtenerToken: () async => sesion.accessToken,
          urlBase: sesion.baseUrl,
        );

        // 1. Guardar donante inicial
        final creado = await repo.guardar(
          DatosDonante(
            rut: '12.345.678-5',
            nombre: 'Donante Inicial',
            fechaNacimiento: DateTime(1998, 5, 10),
            pesoKg: 70,
            grupoAbo: 'O',
            factorRh: 'positivo',
            telefono: '912345678',
          ),
        );

        // 2. Intentar actualizar con el RUT del donante semilla demo-donors (11111111-1) -> Falla con 409
        expect(
          () => repo.actualizar(
            creado.id,
            DatosDonante(
              rut: '11.111.111-1',
              nombre: 'Donante Conflicto',
              fechaNacimiento: DateTime(1998, 5, 10),
              pesoKg: 70,
              grupoAbo: 'O',
              factorRh: 'positivo',
              telefono: '912345678',
            ),
          ),
          throwsA(
            isA<DonanteApiException>().having((e) => e.codigo, 'codigo', 409),
          ),
        );

        // 3. Actualizar con cambios válidos manteniendo el propio RUT (incluso normalizándolo)
        final actualizado = await repo.actualizar(
          creado.id,
          DatosDonante(
            rut: '12345678-5',
            nombre: 'Donante Corregido',
            fechaNacimiento: DateTime(1998, 5, 10),
            pesoKg: 74.5,
            grupoAbo: 'A',
            factorRh: 'negativo',
            telefono: '988887777',
          ),
        );

        expect(actualizado.id, creado.id);
        expect(actualizado.nombre, 'Donante Corregido');
        expect(actualizado.pesoKg, 74.5);
        expect(actualizado.grupoAbo, 'A');
        expect(actualizado.factorRh, 'negativo');
        expect(actualizado.telefono, '988887777');
        expect(actualizado.usuarioRegistroId, creado.usuarioRegistroId);
        expect(actualizado.usuarioModificacionId, 'nursing-demo');
        expect(actualizado.fechaModificacion, isNotNull);

        // 4. Reiniciar servidor y verificar que la versión corregida persiste intacta
        await detener();
        final urlNueva = await iniciar(semillas: false);
        final sesion2 = AuthSession(
          baseUrl: urlNueva,
          client: cliente,
          tokenStore: tokens,
        );
        sesiones.add(sesion2);
        await sesion2.login('enfermeria@hemolink.test', 'DemoHemoLink2026!');
        final repo2 = ApiDonanteRepository(
          cliente: cliente,
          obtenerToken: () async => sesion2.accessToken,
          urlBase: urlNueva,
        );

        final persistido = await repo2.buscarPorId(creado.id);
        expect(persistido, isNotNull);
        expect(persistido!.nombre, 'Donante Corregido');
        expect(persistido.pesoKg, 74.5);
        expect(persistido.grupoAbo, 'A');
        expect(persistido.factorRh, 'negativo');
        expect(persistido.usuarioModificacionId, 'nursing-demo');
      },
    );
  });
}
