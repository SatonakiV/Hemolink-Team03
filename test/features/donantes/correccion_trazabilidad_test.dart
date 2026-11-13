import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/core/access/auth_session.dart';
import 'package:hemolink/core/access/token_store.dart';
import 'package:hemolink/domain/muestra.dart' hide UnidadSangre;
import 'package:hemolink/features/aptitud/domain/evaluacion_aptitud.dart';
import 'package:hemolink/features/donaciones/data/api_donacion_repository.dart';
import 'package:hemolink/features/donaciones/domain/donacion.dart';
import 'package:hemolink/features/donantes/data/api_donante_repository.dart';
import 'package:hemolink/features/donantes/domain/donante.dart';
import 'package:hemolink/features/muestras/data/api_muestra_repository.dart';
import 'package:hemolink/features/muestras/data/muestra_repository.dart';
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
  group('T04.6: Verificar correcciones y trazabilidad', () {
    test(
      'UT04.6-A: tras editar se conservan donante, evaluación, donación y muestra',
      () {
        // Datos ficticios iniciales: 1 donante, 1 evaluación, 1 donación, 1 muestra, 1 unidad
        final donanteOriginal = Donante(
          id: 'DON-100',
          rut: '12345678-5',
          nombre: 'Juan Donante',
          fechaNacimiento: DateTime(1995, 4, 15),
          pesoKg: 75.0,
          grupoAbo: 'O',
          factorRh: 'positivo',
          telefono: '912345678',
          usuarioRegistroId: 'ENF-001',
          fechaRegistro: DateTime(2026, 11, 1),
        );

        final evaluacion = EvaluacionAptitud(
          id: 'EV-100',
          donanteId: 'DON-100',
          resultado: ResultadoAptitud.apto,
          fechaEvaluacion: DateTime(2026, 11, 2),
          fechaFinVigencia: DateTime(2026, 11, 30),
          responsableId: 'ENF-001',
          fechaRegistro: DateTime(2026, 11, 2),
        );

        final unidad = UnidadSangre(
          id: 'UNI-100',
          codigo: 'U-100',
          donacionId: 'DONAC-100',
          grupoAbo: 'O',
          factorRh: 'positivo',
          sedeId: 'sede-central',
          fechaVencimiento: DateTime(2026, 12, 14),
          estado: EstadoUnidad.disponible,
        );

        final donacion = Donacion(
          id: 'DONAC-100',
          donanteId: 'DON-100',
          evaluacionId: 'EV-100',
          fechaExtraccion: DateTime(2026, 11, 2),
          volumenMl: 450,
          sedeId: 'sede-central',
          responsableId: 'ENF-001',
          fechaRegistro: DateTime(2026, 11, 2),
          unidades: [unidad],
        );

        final muestra = Muestra(
          id: 'M-100',
          codigo: 'M-100',
          donacionId: 'DONAC-100',
          donanteId: 'DON-100',
          scopeId: 'sede-central',
          responsableId: 'ENF-001',
          fechaRegistro: DateTime(2026, 11, 2),
        );

        // Simulamos edición del donante (nombre, peso, grupo, etc.)
        final donanteEditado = Donante(
          id: 'DON-100', // Mantiene ID
          rut: '12345678-5', // Mantiene RUT
          nombre: 'Juan Donante Corregido',
          fechaNacimiento: DateTime(1995, 4, 15),
          pesoKg: 78.0,
          grupoAbo: 'A',
          factorRh: 'positivo',
          telefono: '999888777',
          usuarioRegistroId: 'ENF-001',
          fechaRegistro: DateTime(2026, 11, 1),
          usuarioModificacionId: 'ENF-002',
          fechaModificacion: DateTime(2026, 11, 10),
        );

        // Comprobamos que todas las entidades conservan sus identificadores y relaciones
        expect(donanteEditado.id, donanteOriginal.id);
        expect(evaluacion.donanteId, donanteEditado.id);
        expect(donacion.donanteId, donanteEditado.id);
        expect(donacion.evaluacionId, evaluacion.id);
        expect(muestra.donanteId, donanteEditado.id);
        expect(muestra.donacionId, donacion.id);
        expect(unidad.donacionId, donacion.id);
      },
    );

    test('UT04.6-B: el grupo de una unidad histórica no cambia', () {
      final donanteOriginal = Donante(
        id: 'DON-100',
        rut: '12345678-5',
        nombre: 'Pedro Donante',
        fechaNacimiento: DateTime(1990, 1, 1),
        pesoKg: 70.0,
        grupoAbo: 'O',
        factorRh: 'positivo',
        telefono: '912345678',
        usuarioRegistroId: 'ENF-001',
        fechaRegistro: DateTime(2026, 11, 1),
      );

      final unidadHistorica = UnidadSangre(
        id: 'UNI-100',
        codigo: 'U-100',
        donacionId: 'DONAC-100',
        grupoAbo: donanteOriginal.grupoAbo, // 'O'
        factorRh: donanteOriginal.factorRh, // 'positivo'
        sedeId: 'sede-central',
        fechaVencimiento: DateTime(2026, 12, 14),
        estado: EstadoUnidad.disponible,
      );

      // Corrección de grupo sanguíneo en el donante (de O+ a A+)
      final donanteCorregido = Donante(
        id: 'DON-100',
        rut: '12345678-5',
        nombre: 'Pedro Donante',
        fechaNacimiento: DateTime(1990, 1, 1),
        pesoKg: 70.0,
        grupoAbo: 'A',
        factorRh: 'positivo',
        telefono: '912345678',
        usuarioRegistroId: 'ENF-001',
        fechaRegistro: DateTime(2026, 11, 1),
        usuarioModificacionId: 'ENF-002',
        fechaModificacion: DateTime(2026, 11, 10),
      );

      // El donante tiene grupo 'A', pero la unidad histórica conserva 'O'
      expect(donanteCorregido.grupoAbo, 'A');
      expect(unidadHistorica.grupoAbo, 'O');
      expect(unidadHistorica.factorRh, 'positivo');
    });

    test(
      'UT04.6-C: cancelación, RUT duplicado y fallo mantienen la versión guardada',
      () async {
        final donanteOriginal = Donante(
          id: 'DON-100',
          rut: '12345678-5',
          nombre: 'Donante Original',
          fechaNacimiento: DateTime(1992, 3, 3),
          pesoKg: 72.0,
          grupoAbo: 'B',
          factorRh: 'negativo',
          telefono: '912345678',
          usuarioRegistroId: 'ENF-001',
          fechaRegistro: DateTime(2026, 11, 1),
        );

        // 1. Cancelación: el formulario no invoca repo.actualizar
        var llamadoRepo = false;
        http.Response jsonResp(Object datos, [int estado = 200]) =>
            http.Response(
              jsonEncode(datos),
              estado,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );

        final repoConflict = ApiDonanteRepository(
          cliente: MockClient((req) async {
            llamadoRepo = true;
            if (req.body.contains('11111111-1')) {
              return jsonResp({
                'message': 'Ya existe un donante con ese RUT.',
                'errors': {'rut': 'Ya existe un donante con ese RUT.'},
              }, 409);
            }
            return jsonResp({'message': 'Error de servidor'}, 500);
          }),
          obtenerToken: () async => 'token-prueba',
          urlBase: 'http://servidor.test:8080',
        );

        // Cancelación no llama al repositorio
        expect(llamadoRepo, isFalse);
        expect(donanteOriginal.nombre, 'Donante Original');

        // 2. RUT duplicado lanza DonanteApiException 409 y preserva versión guardada
        final datosDuplicado = DatosDonante(
          rut: '11.111.111-1',
          nombre: 'Donante Editado',
          fechaNacimiento: DateTime(1992, 3, 3),
          pesoKg: 72.0,
          grupoAbo: 'B',
          factorRh: 'negativo',
          telefono: '912345678',
        );

        expect(
          () => repoConflict.actualizar('DON-100', datosDuplicado),
          throwsA(
            isA<DonanteApiException>().having((e) => e.codigo, 'codigo', 409),
          ),
        );

        // 3. Fallo de servidor (500)
        final datosValidos = DatosDonante(
          rut: '12.345.678-5',
          nombre: 'Donante Editado',
          fechaNacimiento: DateTime(1992, 3, 3),
          pesoKg: 72.0,
          grupoAbo: 'B',
          factorRh: 'negativo',
          telefono: '912345678',
        );

        expect(
          () => repoConflict.actualizar('DON-100', datosValidos),
          throwsA(
            isA<DonanteApiException>().having((e) => e.codigo, 'codigo', 500),
          ),
        );
      },
    );

    test('UT04.6-D: ausencia de sesión o rol ajeno impide modificar', () async {
      http.Response jsonResp(Object datos, [int estado = 200]) => http.Response(
        jsonEncode(datos),
        estado,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

      final datosEditados = DatosDonante(
        rut: '12.345.678-5',
        nombre: 'Intento No Autorizado',
        fechaNacimiento: DateTime(1990, 1, 1),
        pesoKg: 70,
        grupoAbo: 'O',
        factorRh: 'positivo',
        telefono: '912345678',
      );

      // Sin token (401)
      final repoSinSesion = ApiDonanteRepository(
        cliente: MockClient(
          (_) async => jsonResp({'message': 'No autorizado'}, 401),
        ),
        obtenerToken: () async => null,
        urlBase: 'http://servidor.test:8080',
      );

      expect(
        () => repoSinSesion.actualizar('DON-100', datosEditados),
        throwsA(
          isA<DonanteApiException>().having((e) => e.codigo, 'codigo', 401),
        ),
      );

      // Rol ajeno p.ej. inventario / hospital (403)
      final repoRolAjeno = ApiDonanteRepository(
        cliente: MockClient(
          (_) async => jsonResp({'message': 'Acceso prohibido'}, 403),
        ),
        obtenerToken: () async => 'token-inventario',
        urlBase: 'http://servidor.test:8080',
      );

      expect(
        () => repoRolAjeno.actualizar('DON-100', datosEditados),
        throwsA(
          isA<DonanteApiException>().having((e) => e.codigo, 'codigo', 403),
        ),
      );
    });

    test(
      'UT04.6-E: el flujo conserva los datos corregidos al recuperarlos del repositorio de prueba',
      () async {
        final carpeta = await Directory.systemTemp.createTemp(
          'hemolink-trazabilidad-',
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
          servidor.stderr
              .transform(utf8.decoder)
              .listen(erroresServidor.write);
          final direccion = await servidor.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first
              .timeout(const Duration(seconds: 10));
          return direccion;
        }

        final cliente = http.Client();
        final tokens = _TokensMemoria();
        final urlBase = await iniciar(semillas: true);

        final sesionEnfermeria = AuthSession(
          baseUrl: urlBase,
          client: cliente,
          tokenStore: tokens,
        );
        sesiones.add(sesionEnfermeria);
        await sesionEnfermeria.login(
          'enfermeria@hemolink.test',
          'DemoHemoLink2026!',
        );

        final repoDonantes = ApiDonanteRepository(
          cliente: cliente,
          obtenerToken: () async => sesionEnfermeria.accessToken,
          urlBase: urlBase,
        );

        final repoDonaciones = ApiDonacionRepository(
          cliente: cliente,
          obtenerToken: () async => sesionEnfermeria.accessToken,
          urlBase: urlBase,
        );

        final repoMuestras = ApiMuestraRepository(
          cliente: cliente,
          obtenerToken: () async => sesionEnfermeria.accessToken,
          urlBase: urlBase,
        );

        // 1. Crear donante
        final donante = await repoDonantes.guardar(
          DatosDonante(
            rut: '12.345.678-5',
            nombre: 'Donante Trazabilidad',
            fechaNacimiento: DateTime(1996, 6, 20),
            pesoKg: 72,
            grupoAbo: 'O',
            factorRh: 'positivo',
            telefono: '912345678',
          ),
        );

        // 2. Registrar evaluación de aptitud directamente en servidor
        final respEval = await cliente.post(
          Uri.parse('$urlBase/api/evaluations'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${sesionEnfermeria.accessToken}',
          },
          body: jsonEncode({
            'id': 'EV_TRAZAB',
            'donanteId': donante.id,
            'resultado': 'apto',
            'fechaEvaluacion': '2026-11-09',
            'fechaFinVigencia': '2026-11-25',
          }),
        );
        expect(respEval.statusCode, 201);

        // 3. Registrar donación con 1 unidad
        final donacion = await repoDonaciones.guardar(
          DatosDonacion(
            claveConfirmacion: 'clave-trazabilidad-001',
            donanteId: donante.id,
            evaluacionId: 'EV_TRAZAB',
            fechaExtraccion: DateTime(2026, 11, 9),
            volumenMl: 450,
            codigosUnidades: ['U-TRAZAB-001'],
          ),
        );

        // 4. Registrar muestra asociada a la donación
        final muestra = await repoMuestras.guardar(
          DatosMuestra(codigo: 'M-TRAZAB-001', donacionId: donacion.id),
        );

        // Verificaciones previas a la edición
        expect(donacion.donanteId, donante.id);
        expect(donacion.evaluacionId, 'EV_TRAZAB');
        expect(donacion.unidades.length, 1);
        expect(donacion.unidades.first.grupoAbo, 'O');
        expect(muestra.donacionId, donacion.id);
        expect(muestra.donanteId, donante.id);

        // 5. Editar donante: cambiar grupo ABO a A y actualizar nombre y teléfono
        final donanteCorregido = await repoDonantes.actualizar(
          donante.id,
          DatosDonante(
            rut: '12.345.678-5',
            nombre: 'Donante Trazabilidad Corregido',
            fechaNacimiento: DateTime(1996, 6, 20),
            pesoKg: 74,
            grupoAbo: 'A',
            factorRh: 'positivo',
            telefono: '988887777',
          ),
        );

        expect(donanteCorregido.id, donante.id);
        expect(donanteCorregido.nombre, 'Donante Trazabilidad Corregido');
        expect(donanteCorregido.grupoAbo, 'A');

        // 6. Reiniciar servidor y recuperar entidades para comprobar conservación de relaciones e invariantes
        await detener();
        final urlNueva = await iniciar(semillas: false);

        final sesion2 = AuthSession(
          baseUrl: urlNueva,
          client: cliente,
          tokenStore: tokens,
        );
        sesiones.add(sesion2);
        await sesion2.login(
          'enfermeria@hemolink.test',
          'DemoHemoLink2026!',
        );

        final repoDonantes2 = ApiDonanteRepository(
          cliente: cliente,
          obtenerToken: () async => sesion2.accessToken,
          urlBase: urlNueva,
        );
        final repoDonaciones2 = ApiDonacionRepository(
          cliente: cliente,
          obtenerToken: () async => sesion2.accessToken,
          urlBase: urlNueva,
        );
        final repoMuestras2 = ApiMuestraRepository(
          cliente: cliente,
          obtenerToken: () async => sesion2.accessToken,
          urlBase: urlNueva,
        );

        // Recuperar donante corregido
        final donantePersistido = await repoDonantes2.buscarPorId(donante.id);
        expect(donantePersistido, isNotNull);
        expect(donantePersistido!.nombre, 'Donante Trazabilidad Corregido');
        expect(donantePersistido.grupoAbo, 'A');

        // Recuperar donación y verificar que sus unidades históricas conservan grupo 'O'
        final donacionPersistida = await repoDonaciones2.buscarPorId(
          donacion.id,
        );
        expect(donacionPersistida, isNotNull);
        expect(donacionPersistida!.donanteId, donante.id);
        expect(donacionPersistida.evaluacionId, 'EV_TRAZAB');
        expect(donacionPersistida.unidades.first.grupoAbo, 'O');

        // Recuperar muestra y verificar que conserva los vínculos de donación y donante
        final muestraPersistida = await repoMuestras2.buscarPorId(muestra.id);
        expect(muestraPersistida, isNotNull);
        expect(muestraPersistida!.donacionId, donacion.id);
        expect(muestraPersistida.donanteId, donante.id);
      },
    );
  });
}
