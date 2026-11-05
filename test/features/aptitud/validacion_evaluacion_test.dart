import 'package:flutter_test/flutter_test.dart';

import 'package:hemolink/features/aptitud/domain/evaluacion_aptitud.dart';
import 'package:hemolink/features/aptitud/domain/validador_evaluacion.dart';

// Simula la consulta de donantes durante las pruebas.
class DonantesFalsos implements ConsultaDonantes {
  final Set<String> identificadores;

  DonantesFalsos(this.identificadores);

  @override
  Future<bool> existe(String id) async {
    return identificadores.contains(id);
  }
}

void main() {
  final fecha = DateTime(2026, 11, 4);

  // Construye una evaluación con valores válidos por defecto.
  EvaluacionAptitud crearEvaluacion({
    ResultadoAptitud resultado = ResultadoAptitud.apto,
    DateTime? finVigencia,
    DateTime? habilitacion,
  }) {
    return EvaluacionAptitud(
      id: 'EV001',
      donanteId: 'DON001',
      resultado: resultado,
      fechaEvaluacion: fecha,
      fechaFinVigencia: finVigencia,
      fechaHabilitacion: habilitacion,
      responsableId: 'ENF001',
      fechaRegistro: fecha,
    );
  }

  group('T02.1 - UT2: Validaciones', () {
    test('Rechazar donante inexistente', () async {
      final validador = ValidadorEvaluacion(DonantesFalsos({}));

      final evaluacion = crearEvaluacion(finVigencia: DateTime(2026, 11, 13));

      await expectLater(
        validador.validar(evaluacion),
        throwsA(isA<ValidacionEvaluacionException>()),
      );
    });

    test('Rechazar apto sin fecha de vigencia', () async {
      final validador = ValidadorEvaluacion(DonantesFalsos({'DON001'}));

      final evaluacion = crearEvaluacion();

      await expectLater(
        validador.validar(evaluacion),
        throwsA(isA<ValidacionEvaluacionException>()),
      );
    });

    test('Rechazar diferido sin habilitación', () async {
      final validador = ValidadorEvaluacion(DonantesFalsos({'DON001'}));

      final evaluacion = crearEvaluacion(resultado: ResultadoAptitud.diferido);

      await expectLater(
        validador.validar(evaluacion),
        throwsA(isA<ValidacionEvaluacionException>()),
      );
    });

    test('Aceptar los tres resultados completos', () async {
      final validador = ValidadorEvaluacion(DonantesFalsos({'DON001'}));

      final evaluaciones = [
        crearEvaluacion(finVigencia: DateTime(2026, 11, 13)),
        crearEvaluacion(
          resultado: ResultadoAptitud.diferido,
          habilitacion: DateTime(2026, 12, 4),
        ),
        crearEvaluacion(resultado: ResultadoAptitud.rechazado),
      ];

      for (final evaluacion in evaluaciones) {
        await validador.validar(evaluacion);
      }
    });
  });
}
