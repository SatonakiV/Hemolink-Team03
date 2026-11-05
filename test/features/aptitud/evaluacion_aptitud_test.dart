import 'package:flutter_test/flutter_test.dart';

import 'package:hemolink/features/aptitud/domain/evaluacion_aptitud.dart';

void main() {
  group('T02.1 - UT1: Registro de evaluaciones', () {
    test('Registrar evaluación APTO', () {
      final evaluacion = EvaluacionAptitud(
        id: 'EV001',
        donanteId: 'DON001',
        resultado: ResultadoAptitud.apto,
        fechaEvaluacion: DateTime(2026, 11, 4),
        fechaFinVigencia: DateTime(2026, 11, 13),
        responsableId: 'ENF001',
        fechaRegistro: DateTime(2026, 11, 4),
      );

      expect(evaluacion.resultado, ResultadoAptitud.apto);
      expect(evaluacion.fechaFinVigencia, DateTime(2026, 11, 13));
      expect(evaluacion.donanteId, 'DON001');
      expect(evaluacion.responsableId, 'ENF001');
    });

    test('Registrar evaluación DIFERIDO', () {
      final evaluacion = EvaluacionAptitud(
        id: 'EV002',
        donanteId: 'DON002',
        resultado: ResultadoAptitud.diferido,
        fechaEvaluacion: DateTime(2026, 11, 4),
        fechaHabilitacion: DateTime(2026, 12, 4),
        responsableId: 'ENF001',
        fechaRegistro: DateTime(2026, 11, 4),
      );

      expect(evaluacion.resultado, ResultadoAptitud.diferido);
      expect(evaluacion.fechaHabilitacion, DateTime(2026, 12, 4));
    });

    test('Registrar evaluación RECHAZADO', () {
      final evaluacion = EvaluacionAptitud(
        id: 'EV003',
        donanteId: 'DON003',
        resultado: ResultadoAptitud.rechazado,
        fechaEvaluacion: DateTime(2026, 11, 4),
        responsableId: 'ENF001',
        fechaRegistro: DateTime(2026, 11, 4),
      );

      expect(evaluacion.resultado, ResultadoAptitud.rechazado);
      expect(evaluacion.fechaFinVigencia, isNull);
      expect(evaluacion.fechaHabilitacion, isNull);
    });
  });
}
