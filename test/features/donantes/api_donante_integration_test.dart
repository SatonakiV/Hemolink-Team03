import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/core/access/auth_session.dart';
import 'package:hemolink/core/access/token_store.dart';
import 'package:hemolink/features/donantes/data/api_donante_repository.dart';
import 'package:hemolink/features/donantes/data/crear_repositorio_donantes.dart';
import 'package:hemolink/features/donantes/domain/donante.dart';
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

void main() {
  test('T01.2: Flutter registra, busca y recupera la ficha de la API real tras reiniciarla', () async {
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
