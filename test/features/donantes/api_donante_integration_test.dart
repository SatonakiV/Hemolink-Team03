import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/core/access/auth_session.dart';
import 'package:hemolink/core/access/token_store.dart';
import 'package:hemolink/features/donantes/data/api_donante_repository.dart';
import 'package:hemolink/features/donantes/data/crear_repositorio_donantes.dart';
import 'package:hemolink/features/donantes/domain/donante.dart';
import 'package:http/http.dart' as http;
import 'package:hemolink/features/aptitud/data/api_evaluacion_repository.dart';
import 'package:hemolink/features/aptitud/domain/evaluacion_aptitud.dart';
import 'package:hemolink/features/aptitud/domain/registro_evaluaciones.dart';
import 'package:hemolink/features/aptitud/domain/validador_evaluacion.dart';
import 'package:hemolink/features/donantes/data/donante_repository.dart';

class _ConsultaDonantes implements ConsultaDonantes {
  _ConsultaDonantes(this.repo);
  final DonanteRepository repo;
  @override
  Future<bool> existe(String id) async => await repo.buscarPorId(id) != null;
}

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
  test('T01.2 y PR19: donante y evaluación actual por HTTP real, decisión trazable y reinicio', () async {
    final carpeta = await Directory.systemTemp.createTemp('hemolink-donantes-');
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
      expect(
        direccion,
        startsWith('http://127.0.0.1:'),
        reason: erroresServidor.toString(),
      );
      return direccion;
    }

    final tokens = _TokensMemoria();
    final cliente = http.Client();
    final sesion = AuthSession(
      baseUrl: await iniciar(semillas: true),
      client: cliente,
      tokenStore: tokens,
    );
    sesiones.add(sesion);
    await sesion.login('enfermeria@hemolink.test', 'DemoHemoLink2026!');
    final repo = crearRepositorioDonantes(sesion: sesion, cliente: cliente);
    expect((await repo.buscar()).single.id, 'demo-donors');
    final datos = DatosDonante(
      rut: '6.000.000-k',
      nombre: 'María Soto',
      fechaNacimiento: DateTime(1998, 5, 10),
      pesoKg: 70,
      grupoAbo: 'AB',
      factorRh: 'negativo',
      telefono: '912345678',
    );
    final guardado = await repo.guardar(datos);
    final evaluaciones = ApiEvaluacionRepository(
      cliente: cliente,
      obtenerToken: () async => sesion.accessToken,
      urlBase: sesion.baseUrl,
    );
    final registro = RegistroEvaluaciones(
      repositorio: evaluaciones,
      validador: ValidadorEvaluacion(_ConsultaDonantes(repo)),
    );
    Future<void> evaluar(String id, ResultadoAptitud resultado, int dia) =>
        evaluaciones.guardar(
          EvaluacionAptitud(
            id: id,
            donanteId: guardado.id,
            resultado: resultado,
            fechaEvaluacion: DateTime(2026, 11, dia),
            fechaFinVigencia: resultado == ResultadoAptitud.apto
                ? DateTime(2026, 11, 20)
                : null,
            responsableId: 'IGNORADO',
            fechaRegistro: DateTime(2000),
          ),
        );
    // Fecha de registro idéntica: manda el orden persistido, incluso al ingresar
    // una fecha clínica anterior. Los IDs tampoco deciden el orden.
    await evaluar('EV_Z', ResultadoAptitud.apto, 7);
    await evaluar('EV_A', ResultadoAptitud.rechazado, 5);
    expect((await evaluaciones.buscarActual(guardado.id))!.id, 'EV_A');
    await evaluar('EV_B', ResultadoAptitud.apto, 5);
    final decision = await registro.evaluarDonacion(
      guardado.id,
      fechaExtraccion: DateTime(2026, 11, 10),
    );
    expect(decision.autorizada, isTrue);
    expect(decision.evaluacionId, 'EV_B');
    expect(decision.donanteId, guardado.id);
    final vencida = await registro.evaluarDonacion(
      guardado.id,
      fechaExtraccion: DateTime(2026, 11, 21),
    );
    expect(vencida.autorizada, isFalse);
    expect(vencida.evaluacionId, 'EV_B');
    await evaluar('EV_C', ResultadoAptitud.rechazado, 5);
    expect(
      (await registro.evaluarDonacion(
        guardado.id,
        fechaExtraccion: DateTime(2026, 11, 10),
      )).autorizada,
      isFalse,
    );
    expect(decision.autorizada, isTrue);
    expect(decision.evaluacionId, 'EV_B');
    expect(
      (await evaluaciones.buscarPorId('EV_Z'))!.fechaEvaluacion,
      DateTime(2026, 11, 7),
    );
    expect(guardado.rut, '6000000-K');
    expect(guardado.usuarioRegistroId, 'nursing-demo');
    expect((await repo.buscar(rut: '06.000.000-k')).single.id, guardado.id);
    expect((await repo.buscar(nombre: 'MARÍA')).single.id, guardado.id);
    await expectLater(
      repo.guardar(datos),
      throwsA(
        isA<DonanteApiException>().having((e) => e.codigo, 'duplicado', 409),
      ),
    );

    await detener();
    final clienteNuevo = http.Client();
    final sesionNueva = AuthSession(
      baseUrl: await iniciar(semillas: false),
      client: clienteNuevo,
      tokenStore: tokens,
    );
    sesiones.add(sesionNueva);
    await sesionNueva.restore();
    final nuevoRepo = crearRepositorioDonantes(
      sesion: sesionNueva,
      cliente: clienteNuevo,
    );
    final ficha = await nuevoRepo.buscarPorId(guardado.id);
    final evaluacionesNuevas = ApiEvaluacionRepository(
      cliente: clienteNuevo,
      obtenerToken: () async => sesionNueva.accessToken,
      urlBase: sesionNueva.baseUrl,
    );
    expect((await evaluacionesNuevas.buscarActual(guardado.id))!.id, 'EV_C');
    expect(
      (await evaluacionesNuevas.buscarPorId(decision.evaluacionId!))!.resultado,
      ResultadoAptitud.apto,
    );
    expect(ficha!.nombre, 'María Soto');
    expect(ficha.fechaNacimiento, datos.fechaNacimiento);
    expect(ficha.pesoKg, datos.pesoKg);
    expect(ficha.grupoAbo, datos.grupoAbo);
    expect(ficha.factorRh, datos.factorRh);
    expect(ficha.telefono, datos.telefono);
    expect(ficha.fechaRegistro, guardado.fechaRegistro);
    expect(await nuevoRepo.buscar(nombre: 'ausente'), isEmpty);
    await sesionNueva.logout();
    await expectLater(
      nuevoRepo.buscarPorId(guardado.id),
      throwsA(
        isA<DonanteApiException>().having(
          (e) => e.codigo,
          'sesión cerrada',
          401,
        ),
      ),
    );
  });
}
