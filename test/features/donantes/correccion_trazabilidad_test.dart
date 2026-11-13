import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/core/access/auth_session.dart';
import 'package:hemolink/core/access/token_store.dart';
import 'package:hemolink/domain/muestra.dart' hide UnidadSangre;
import 'package:hemolink/features/aptitud/domain/evaluacion_aptitud.dart';
import 'package:hemolink/features/aptitud/data/api_evaluacion_repository.dart';
import 'package:hemolink/features/donaciones/data/api_donacion_repository.dart';
import 'package:hemolink/features/donaciones/domain/donacion.dart';
import 'package:hemolink/features/donantes/data/api_donante_repository.dart';
import 'package:hemolink/features/donantes/domain/donante.dart';
import 'package:hemolink/features/muestras/data/api_muestra_repository.dart';
import 'package:hemolink/features/muestras/data/muestra_repository.dart';
import 'package:http/http.dart' as http;

class _TokensMemoria implements TokenStore {
  String? token;
  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String valor) async => token = valor;
  @override
  Future<void> delete() async => token = null;
}

// Estado completo de los modelos recuperados, incluidas las unidades.
List<Object?> _estadoDonante(Donante d) => [
  d.id,
  d.rut,
  d.nombre,
  d.fechaNacimiento,
  d.pesoKg,
  d.grupoAbo,
  d.factorRh,
  d.telefono,
  d.usuarioRegistroId,
  d.fechaRegistro,
  d.usuarioModificacionId,
  d.fechaModificacion,
];

List<Object?> _estadoEvaluacion(EvaluacionAptitud e) => [
  e.id,
  e.donanteId,
  e.resultado,
  e.fechaEvaluacion,
  e.fechaFinVigencia,
  e.fechaHabilitacion,
  e.responsableId,
  e.fechaRegistro,
];

List<Object?> _estadoDonacion(Donacion d) => [
  d.id,
  d.donanteId,
  d.evaluacionId,
  d.fechaExtraccion,
  d.volumenMl,
  d.sedeId,
  d.responsableId,
  d.fechaRegistro,
  for (final u in d.unidades)
    [
      u.id,
      u.codigo,
      u.donacionId,
      u.grupoAbo,
      u.factorRh,
      u.sedeId,
      u.estado,
      u.fechaVencimiento,
    ],
];

List<Object?> _estadoMuestra(Muestra m) => [
  m.id,
  m.codigo,
  m.donacionId,
  m.donanteId,
  m.scopeId,
  m.responsableId,
  m.fechaRegistro,
];

void main() {
  group('T04.6: corrección y trazabilidad con servidor real', () {
    test('UT04.6-A/B/E: editar y reiniciar conserva datos, relaciones e historial completo', () async {
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
        servidor.stderr.transform(utf8.decoder).listen(erroresServidor.write);
        final direccion = await servidor.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(seconds: 10));
        return direccion;
      }

      final cliente = http.Client();
      addTearDown(cliente.close);
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

      final repoEvaluaciones = ApiEvaluacionRepository(
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

      final evaluacion = await repoEvaluaciones.buscarPorId('EV_TRAZAB');
      expect(evaluacion, isNotNull);
      final estadoEvaluacion = _estadoEvaluacion(evaluacion!);
      final estadoDonacion = _estadoDonacion(donacion);
      final estadoMuestra = _estadoMuestra(muestra);

      // 5. Corregir también Rh para ejercitar ambos componentes del grupo.
      final donanteCorregido = await repoDonantes.actualizar(
        donante.id,
        DatosDonante(
          rut: '12.345.678-5',
          nombre: 'Donante Trazabilidad Corregido',
          fechaNacimiento: DateTime(1996, 6, 20),
          pesoKg: 74,
          grupoAbo: 'A',
          factorRh: 'negativo',
          telefono: '988887777',
        ),
      );

      expect(donanteCorregido.id, donante.id);
      expect(donanteCorregido.nombre, 'Donante Trazabilidad Corregido');
      expect(donanteCorregido.grupoAbo, 'A');
      expect(donanteCorregido.factorRh, 'negativo');
      expect(donanteCorregido.telefono, '988887777');
      expect(donanteCorregido.pesoKg, 74);
      expect(donanteCorregido.rut, donante.rut);
      expect(donanteCorregido.fechaNacimiento, donante.fechaNacimiento);
      expect(donanteCorregido.usuarioRegistroId, donante.usuarioRegistroId);
      expect(donanteCorregido.fechaRegistro, donante.fechaRegistro);
      expect(donanteCorregido.usuarioModificacionId, 'nursing-demo');
      expect(donanteCorregido.fechaModificacion, isNotNull);
      // Se consulta antes de reiniciar para detectar cambios inmediatos.
      expect(
        _estadoEvaluacion((await repoEvaluaciones.buscarPorId('EV_TRAZAB'))!),
        estadoEvaluacion,
      );
      expect(
        _estadoDonacion((await repoDonaciones.buscarPorId(donacion.id))!),
        estadoDonacion,
      );
      expect(
        _estadoMuestra((await repoMuestras.buscarPorId(muestra.id))!),
        estadoMuestra,
      );

      // 6. Reiniciar servidor y recuperar entidades para comprobar conservación de relaciones e invariantes
      await detener();
      final urlNueva = await iniciar(semillas: false);

      final sesion2 = AuthSession(
        baseUrl: urlNueva,
        client: cliente,
        tokenStore: tokens,
      );
      sesiones.add(sesion2);
      await sesion2.login('enfermeria@hemolink.test', 'DemoHemoLink2026!');

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

      final repoEvaluaciones2 = ApiEvaluacionRepository(
        cliente: cliente,
        obtenerToken: () async => sesion2.accessToken,
        urlBase: urlNueva,
      );

      // Recuperar donante corregido
      final donantePersistido = await repoDonantes2.buscarPorId(donante.id);
      expect(donantePersistido, isNotNull);
      expect(donantePersistido!.nombre, 'Donante Trazabilidad Corregido');
      expect(
        _estadoDonante(donantePersistido),
        _estadoDonante(donanteCorregido),
      );
      final historial = await repoEvaluaciones2.buscarHistorial(donante.id);
      expect(historial, hasLength(1));
      expect(_estadoEvaluacion(historial.single), estadoEvaluacion);
      expect(
        _estadoEvaluacion((await repoEvaluaciones2.buscarPorId('EV_TRAZAB'))!),
        estadoEvaluacion,
      );

      // Recuperar donación y verificar que sus unidades históricas conservan grupo 'O'
      final donacionPersistida = await repoDonaciones2.buscarPorId(donacion.id);
      expect(donacionPersistida, isNotNull);
      expect(donacionPersistida!.donanteId, donante.id);
      expect(donacionPersistida.evaluacionId, 'EV_TRAZAB');
      expect(donacionPersistida.unidades, hasLength(1));
      expect(donacionPersistida.unidades.single.grupoAbo, 'O');
      expect(donacionPersistida.unidades.single.factorRh, 'positivo');
      expect(_estadoDonacion(donacionPersistida), estadoDonacion);

      // Recuperar muestra y verificar que conserva los vínculos de donación y donante
      final muestraPersistida = await repoMuestras2.buscarPorId(muestra.id);
      expect(muestraPersistida, isNotNull);
      expect(muestraPersistida!.donacionId, donacion.id);
      expect(muestraPersistida.donanteId, donante.id);
      expect(_estadoMuestra(muestraPersistida), estadoMuestra);
    });
  });
}
