import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/features/aptitud/data/api_evaluacion_repository.dart';
import 'package:hemolink/features/aptitud/domain/evaluacion_aptitud.dart';
import 'package:hemolink/features/donaciones/data/api_donacion_repository.dart';
import 'package:hemolink/features/donaciones/data/donacion_repository.dart';
import 'package:hemolink/features/donaciones/domain/registro_donaciones.dart';
import 'package:hemolink/features/donaciones/presentation/formulario_donacion_controller.dart';
import 'package:hemolink/features/donantes/domain/donante.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'donacion_formulario_test.dart' as datos;

final _segundoDonante = Donante(
  id: 'D-2',
  rut: '11111111-1',
  nombre: 'Segundo donante',
  fechaNacimiento: DateTime(1990),
  pesoKg: 70,
  grupoAbo: 'A',
  factorRh: 'positivo',
  telefono: '912345678',
  usuarioRegistroId: 'nursing-demo',
  fechaRegistro: DateTime(2026),
);

final _rechazada = EvaluacionAptitud(
  id: 'EV002',
  donanteId: 'D-1',
  resultado: ResultadoAptitud.rechazado,
  fechaEvaluacion: DateTime(2026, 11, 4),
  responsableId: 'nursing-demo',
  fechaRegistro: DateTime(2026, 11, 4),
);

class _EvaluacionesPendientes extends datos.RepoEvaluaciones {
  final consultas = <Completer<EvaluacionAptitud?>>[];

  @override
  Future<EvaluacionAptitud?> buscarActual(String donanteId) {
    final consulta = Completer<EvaluacionAptitud?>();
    consultas.add(consulta);
    return consulta.future;
  }
}

FormularioDonacionController _controlador({
  _EvaluacionesPendientes? evaluaciones,
  DonacionRepository? donaciones,
}) {
  final controlador = FormularioDonacionController(
    usuario: datos.enfermeria,
    donantes: datos.RepoDonantes()..lista = [datos.donanteO, _segundoDonante],
    evaluaciones: evaluaciones ?? datos.RepoEvaluaciones(),
    registro: RegistroDonaciones(
      repositorio: donaciones ?? datos.RepoDonaciones(),
      reloj: datos.reloj,
    ),
    reloj: datos.reloj,
  );
  addTearDown(controlador.dispose);
  return controlador;
}

void main() {
  group('Consultas de aptitud concurrentes', () {
    test('A → B → A conserva la respuesta más reciente de A', () async {
      final evaluaciones = _EvaluacionesPendientes();
      final c = _controlador(evaluaciones: evaluaciones);
      await c.cargarDonantes();
      final primeraA = c.seleccionarDonante('D-1');
      final consultaB = c.seleccionarDonante('D-2');
      final ultimaA = c.seleccionarDonante('D-1');

      evaluaciones.consultas[2].complete(_rechazada);
      await ultimaA;
      evaluaciones.consultas[0].complete(datos.evaluacionApta);
      await primeraA;
      evaluaciones.consultas[1].complete(null);
      await consultaB;

      expect(c.evaluacion?.id, 'EV002');
      expect(c.aptoParaExtraccion, isFalse);
    });

    test(
      'una respuesta anterior no termina la carga de la selección actual',
      () async {
        final evaluaciones = _EvaluacionesPendientes();
        final c = _controlador(evaluaciones: evaluaciones);
        await c.cargarDonantes();
        final consultaA = c.seleccionarDonante('D-1');
        final consultaB = c.seleccionarDonante('D-2');
        evaluaciones.consultas[0].complete(datos.evaluacionApta);
        await consultaA;
        final seguiaCargando = c.cargandoEvaluacion;
        evaluaciones.consultas[1].complete(null);
        await consultaB;

        expect(seguiaCargando, isTrue);
        expect(c.cargandoEvaluacion, isFalse);
        expect(c.evaluacion, isNull);
      },
    );

    test(
      'el error de una consulta anterior no contamina la selección actual',
      () async {
        final evaluaciones = _EvaluacionesPendientes();
        final c = _controlador(evaluaciones: evaluaciones);
        await c.cargarDonantes();
        final consultaA = c.seleccionarDonante('D-1');
        final consultaB = c.seleccionarDonante('D-2');
        evaluaciones.consultas[1].complete(null);
        await consultaB;
        evaluaciones.consultas[0].completeError(
          const EvaluacionApiException(null, 'Fallo de la consulta anterior.'),
        );
        await consultaA;

        expect(c.donante?.id, 'D-2');
        expect(c.errorGeneral, isNull);
        expect(c.cargandoEvaluacion, isFalse);
      },
    );

    test(
      'quitar la selección cancela la carga y descarta su respuesta',
      () async {
        final evaluaciones = _EvaluacionesPendientes();
        final c = _controlador(evaluaciones: evaluaciones);
        await c.cargarDonantes();
        final consulta = c.seleccionarDonante('D-1');
        await c.seleccionarDonante(null);
        final cargandoSinSeleccion = c.cargandoEvaluacion;
        evaluaciones.consultas.single.complete(datos.evaluacionApta);
        await consulta;

        expect(cargandoSinSeleccion, isFalse);
        expect(c.donante, isNull);
        expect(c.evaluacion, isNull);
      },
    );
  });

  group('Resultado del guardado pendiente', () {
    test('recupera un guardado cuya respuesta se perdió sin cambiar el cuerpo ni duplicarlo', () async {
      Map<String, dynamic>? persistida;
      final cuerpos = <Map<String, dynamic>>[];
      var guardados = 0;
      final cliente = MockClient((solicitud) async {
        final cuerpo = jsonDecode(solicitud.body) as Map<String, dynamic>;
        cuerpos.add(cuerpo);
        if (persistida == null) {
          persistida = cuerpo;
          guardados++;
          throw http.ClientException('Respuesta perdida después del guardado.');
        }
        if (jsonEncode(cuerpo) != jsonEncode(persistida)) {
          return http.Response(
            jsonEncode({
              'message': 'La clave de confirmación ya se usó con otros datos.',
            }),
            409,
          );
        }
        return http.Response(
          jsonEncode({
            'item': {
              ...persistida!,
              'id': 'DON-1',
              'sedeId': 'sede-central',
              'responsableId': 'nursing-demo',
              'fechaRegistro': '2026-11-04T12:00:00Z',
              'unidades': [
                {
                  'id': 'u-1',
                  'codigo': 'U-001',
                  'donacionId': 'DON-1',
                  'grupoAbo': 'O',
                  'factorRh': 'positivo',
                  'sedeId': 'sede-central',
                  'estado': 'disponible',
                  'fechaVencimiento': '2026-12-16',
                },
              ],
            },
          }),
          200,
        );
      });
      addTearDown(cliente.close);
      final c = _controlador(
        donaciones: ApiDonacionRepository(
          cliente: cliente,
          obtenerToken: () async => 'token',
        ),
      );
      await datos.completar(c);
      expect(await c.confirmar(), isNull);
      expect(c.confirmacionPendiente, isTrue);

      c.cambiarVolumen('400');
      c.cambiarFecha(DateTime(2026, 11, 3));
      await c.seleccionarDonante('D-2');
      c.quitarUnidad('U-001');
      expect(c.agregarUnidad('U-002'), isFalse);
      expect(c.volumen, '450');
      expect(c.donante?.id, 'D-1');

      final recuperada = await c.confirmar();
      expect(recuperada?.id, 'DON-1');
      expect(recuperada?.volumenMl, 450);
      expect(cuerpos, hasLength(2));
      expect(cuerpos[1], cuerpos[0]);
      expect(guardados, 1);
      expect(c.confirmacionPendiente, isFalse);
    });

    for (final codigo in [null, 200, 201, 500, 503]) {
      test('con error $codigo preserva la solicitud para reintentar', () async {
        var falla = true;
        final repo = datos.RepoDonaciones()
          ..responder = (d) async {
            if (falla) {
              throw DonacionApiException(codigo, 'Respuesta incierta.');
            }
            return datos.donacionDe(d);
          };
        final c = _controlador(donaciones: repo);
        await datos.completar(c);
        expect(await c.confirmar(), isNull);
        c.cambiarVolumen('400');
        expect(c.volumen, '450');
        falla = false;
        expect((await c.confirmar())?.volumenMl, 450);
        expect(repo.enviados[1], same(repo.enviados[0]));
      });
    }

    test('un rechazo explícito permite corregir y reenviar', () async {
      var rechaza = true;
      final repo = datos.RepoDonaciones()
        ..responder = (d) async {
          if (rechaza) {
            throw DonacionApiException(409, 'Código de unidad repetido.');
          }
          return datos.donacionDe(d);
        };
      final c = _controlador(donaciones: repo);
      await datos.completar(c);
      expect(await c.confirmar(), isNull);
      expect(c.confirmacionPendiente, isFalse);
      c.quitarUnidad('U-001');
      expect(c.agregarUnidad('U-002'), isTrue);
      rechaza = false;
      expect((await c.confirmar())?.unidades.single.codigo, 'U-002');
    });

    test('la validación local no bloquea corregir el formulario', () async {
      final repo = datos.RepoDonaciones();
      final c = _controlador(donaciones: repo);
      expect(await c.confirmar(), isNull);
      expect(c.edicionBloqueada, isFalse);
      expect(repo.enviados, isEmpty);
      await datos.completar(c);
      expect((await c.confirmar())?.id, 'DON-1');
    });

    testWidgets(
      'tras una respuesta perdida bloquea la edición y permite recuperar el detalle',
      (tester) async {
        var falla = true;
        final repo = datos.RepoDonaciones()
          ..responder = (d) async {
            if (falla) {
              throw DonacionApiException(null, 'No se recibió la respuesta.');
            }
            return datos.donacionDe(d);
          };
        await datos.montarFormulario(tester, donaciones: repo);
        await datos.llenarFormulario(tester);
        await datos.tocar(tester, find.byKey(const Key('donacion-confirmar')));

        expect(
          find.byKey(const Key('donacion-confirmacion-pendiente')),
          findsOneWidget,
        );
        expect(find.text('Donación registrada correctamente.'), findsNothing);
        for (final campo in ['donacion-volumen', 'donacion-codigo-unidad']) {
          expect(
            tester.widget<TextField>(find.byKey(Key(campo))).enabled,
            isFalse,
          );
        }
        final donante = tester.widget<DropdownButtonFormField<String>>(
          find.byKey(const Key('donacion-donante')),
        );
        expect(donante.onChanged, isNull);
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const Key('donacion-cambiar-fecha')),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const Key('donacion-agregar-unidad')),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<InputChip>(find.byKey(const Key('unidad-U-001')))
              .onDeleted,
          isNull,
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('donacion-confirmar')))
              .onPressed,
          isNotNull,
        );
        expect(find.text('Reintentar confirmación'), findsOneWidget);

        falla = false;
        await datos.tocar(tester, find.byKey(const Key('donacion-confirmar')));
        expect(find.text('Detalle de donación DON-1'), findsOneWidget);
        expect(repo.enviados[1], same(repo.enviados[0]));
      },
    );
  });
}
