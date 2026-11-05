import 'package:flutter_test/flutter_test.dart';

import 'package:hemolink/features/aptitud/domain/evaluacion_aptitud.dart';
import 'package:hemolink/features/aptitud/domain/validador_evaluacion.dart';

// Simula un donante existente.
class DonantesPrueba implements ConsultaDonantes {
  @override
  Future<bool> existe(String id) async => id == 'DON001';
}

void main() {
  final hoy = DateTime(2026, 11, 4);
  final validador = ValidadorEvaluacion(DonantesPrueba());

  EvaluacionAptitud crearEvaluacion({
    ResultadoAptitud resultado = ResultadoAptitud.apto,
    required DateTime fechaEvaluacion,
    DateTime? fechaFinVigencia,
    DateTime? fechaHabilitacion,
  }) {
    return EvaluacionAptitud(
      id: 'EV001',
      donanteId: 'DON001',
      resultado: resultado,
      fechaEvaluacion: fechaEvaluacion,
      fechaFinVigencia: fechaFinVigencia,
      fechaHabilitacion: fechaHabilitacion,
      responsableId: 'ENF001',
      fechaRegistro: hoy,
    );
  }

  group('T02.1 - UT3: Validaciones de fechas', () {
    test('Rechazar fecha de evaluación futura', () async {
      final evaluacion = crearEvaluacion(
        fechaEvaluacion: DateTime(2026, 11, 5),
        fechaFinVigencia: DateTime(2026, 11, 13),
      );

      await expectLater(
        validador.validar(evaluacion, fechaActual: hoy),
        throwsA(isA<ValidacionEvaluacionException>()),
      );
    });

    test('Rechazar fin de vigencia anterior', () async {
      final evaluacion = crearEvaluacion(
        fechaEvaluacion: hoy,
        fechaFinVigencia: DateTime(2026, 11, 3),
      );

      await expectLater(
        validador.validar(evaluacion, fechaActual: hoy),
        throwsA(isA<ValidacionEvaluacionException>()),
      );
    });

    test('Rechazar habilitación anterior', () async {
      final evaluacion = crearEvaluacion(
        resultado: ResultadoAptitud.diferido,
        fechaEvaluacion: hoy,
        fechaHabilitacion: DateTime(2026, 11, 3),
      );

      await expectLater(
        validador.validar(evaluacion, fechaActual: hoy),
        throwsA(isA<ValidacionEvaluacionException>()),
      );
    });

    test('Aceptar fin de vigencia igual a evaluación', () async {
      final evaluacion = crearEvaluacion(
        fechaEvaluacion: hoy,
        fechaFinVigencia: hoy,
      );

      await validador.validar(evaluacion, fechaActual: hoy);
    });

    test('Aceptar habilitación igual a evaluación', () async {
      final evaluacion = crearEvaluacion(
        resultado: ResultadoAptitud.diferido,
        fechaEvaluacion: hoy,
        fechaHabilitacion: hoy,
      );

      await validador.validar(evaluacion, fechaActual: hoy);
    });
  });
}
