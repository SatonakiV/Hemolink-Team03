import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/features/aptitud/domain/evaluacion_aptitud.dart';
import 'package:hemolink/features/aptitud/domain/regla_aptitud.dart';

void main() {
  const regla = ReglaAptitud();

  // Construye evaluaciones ficticias para las pruebas.
  EvaluacionAptitud crearEvaluacion({
    ResultadoAptitud resultado = ResultadoAptitud.apto,
    DateTime? fechaEvaluacion,
    DateTime? fechaFinVigencia,
    DateTime? fechaHabilitacion,
  }) {
    return EvaluacionAptitud(
      id: 'EV001',
      donanteId: 'D001',
      resultado: resultado,
      fechaEvaluacion:
          fechaEvaluacion ?? DateTime(2026, 11, 1),
      fechaFinVigencia: fechaFinVigencia,
      fechaHabilitacion: fechaHabilitacion,
      responsableId: 'ENF001',
      fechaRegistro: DateTime(2026, 11, 1),
    );
  }

  test('UT1: permite donar cuando está apto y vigente', () {
    final evaluacion = crearEvaluacion(
      fechaFinVigencia: DateTime(2026, 11, 20),
    );

    // Primer día de vigencia.
    expect(
      regla.puedeDonar(
        evaluacion,
        fechaConsulta: DateTime(2026, 11, 1),
      ),
      isTrue,
    );

    // Fecha intermedia.
    expect(
      regla.puedeDonar(
        evaluacion,
        fechaConsulta: DateTime(2026, 11, 10),
      ),
      isTrue,
    );

    // Último día de vigencia.
    expect(
      regla.puedeDonar(
        evaluacion,
        fechaConsulta: DateTime(2026, 11, 20, 23, 59),
      ),
      isTrue,
    );
  });

  test('UT2: rechaza evaluaciones fuera de vigencia', () {
    final evaluacion = crearEvaluacion(
      fechaFinVigencia: DateTime(2026, 11, 20),
    );

    // Antes de realizar la evaluación.
    expect(
      regla.puedeDonar(
        evaluacion,
        fechaConsulta: DateTime(2026, 10, 31),
      ),
      isFalse,
    );

    // Después del vencimiento.
    expect(
      regla.puedeDonar(
        evaluacion,
        fechaConsulta: DateTime(2026, 11, 21),
      ),
      isFalse,
    );
  });

  test('UT3: diferido y rechazado no pueden donar', () {
    final diferido = crearEvaluacion(
      resultado: ResultadoAptitud.diferido,
      fechaHabilitacion: DateTime(2026, 11, 15),
    );

    // Antes de la fecha de habilitación.
    expect(
      regla.puedeDonar(
        diferido,
        fechaConsulta: DateTime(2026, 11, 10),
      ),
      isFalse,
    );

    // Llegar a la fecha no convierte al donante en apto.
    expect(
      regla.puedeDonar(
        diferido,
        fechaConsulta: DateTime(2026, 11, 15),
      ),
      isFalse,
    );

    // Tampoco queda apto después de esa fecha.
    expect(
      regla.puedeDonar(
        diferido,
        fechaConsulta: DateTime(2026, 11, 20),
      ),
      isFalse,
    );

    final rechazado = crearEvaluacion(
      resultado: ResultadoAptitud.rechazado,
    );

    expect(
      regla.puedeDonar(
        rechazado,
        fechaConsulta: DateTime(2026, 11, 10),
      ),
      isFalse,
    );
  });

  test('UT4: rechaza evaluaciones ausentes o incompletas', () {
    // Donante sin evaluación registrada.
    expect(
      regla.puedeDonar(
        null,
        fechaConsulta: DateTime(2026, 11, 10),
      ),
      isFalse,
    );

    // Evaluación apta sin fecha de fin de vigencia.
    final sinVigencia = crearEvaluacion();

    expect(
      regla.puedeDonar(
        sinVigencia,
        fechaConsulta: DateTime(2026, 11, 10),
      ),
      isFalse,
    );

    // Intervalo inconsistente: fin anterior al inicio.
    final fechasInvalidas = crearEvaluacion(
      fechaEvaluacion: DateTime(2026, 11, 20),
      fechaFinVigencia: DateTime(2026, 11, 10),
    );

    expect(
      regla.puedeDonar(
        fechasInvalidas,
        fechaConsulta: DateTime(2026, 11, 15),
      ),
      isFalse,
    );
  });
}
