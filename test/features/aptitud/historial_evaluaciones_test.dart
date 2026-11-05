import 'package:flutter_test/flutter_test.dart';

import 'package:hemolink/features/aptitud/data/evaluacion_repository.dart';
import 'package:hemolink/features/aptitud/domain/evaluacion_aptitud.dart';
import 'package:hemolink/features/aptitud/domain/registro_evaluaciones.dart';
import 'package:hemolink/features/aptitud/domain/validador_evaluacion.dart';

class DonantesPrueba implements ConsultaDonantes {
  @override
  Future<bool> existe(String id) async => id == 'DON001';
}

// Repositorio falso: solo para las pruebas.
class RepositorioPrueba implements EvaluacionRepository {
  final Map<String, EvaluacionAptitud> _evaluaciones = {};
  final Map<String, List<String>> _historial = {};

  @override
  Future<void> guardar(EvaluacionAptitud evaluacion) async {
    if (_evaluaciones.containsKey(evaluacion.id)) {
      throw StateError('La evaluación ya existe');
    }

    _evaluaciones[evaluacion.id] = evaluacion;

    _historial.putIfAbsent(evaluacion.donanteId, () => []).add(evaluacion.id);
  }

  @override
  Future<EvaluacionAptitud?> buscarPorId(String id) async {
    return _evaluaciones[id];
  }

  @override
  Future<EvaluacionAptitud?> buscarActual(String donanteId) async {
    final ids = _historial[donanteId];

    if (ids == null || ids.isEmpty) {
      return null;
    }

    return _evaluaciones[ids.last];
  }
}

void main() {
  final hoy = DateTime(2026, 11, 4);

  group('T02.1 - UT4: Historial de evaluaciones', () {
    test('Conservar evaluación anterior al registrar otra', () async {
      final repositorio = RepositorioPrueba();

      final servicio = RegistroEvaluaciones(
        repositorio: repositorio,
        validador: ValidadorEvaluacion(DonantesPrueba()),
      );

      final primera = EvaluacionAptitud(
        id: 'EV001',
        donanteId: 'DON001',
        resultado: ResultadoAptitud.apto,
        fechaEvaluacion: hoy,
        fechaFinVigencia: DateTime(2026, 11, 13),
        responsableId: 'ENF001',
        fechaRegistro: hoy,
      );

      final segunda = EvaluacionAptitud(
        id: 'EV002',
        donanteId: 'DON001',
        resultado: ResultadoAptitud.diferido,
        fechaEvaluacion: hoy,
        fechaHabilitacion: DateTime(2026, 12, 4),
        responsableId: 'ENF001',
        fechaRegistro: hoy,
      );

      // Registrar la primera evaluación.
      await servicio.registrar(primera, fechaActual: hoy);

      // Una donación histórica conserva este identificador.
      final evaluacionUsadaPorDonacion = primera.id;

      // Registrar una nueva evaluación.
      await servicio.registrar(segunda, fechaActual: hoy);

      // La evaluación actual debe ser la segunda.
      final actual = await servicio.consultarActual('DON001');

      expect(actual?.id, 'EV002');
      expect(actual?.resultado, ResultadoAptitud.diferido);

      // La evaluación histórica debe conservarse.
      final historica = await servicio.consultarPorId(
        evaluacionUsadaPorDonacion,
      );

      expect(historica?.id, 'EV001');
      expect(historica?.resultado, ResultadoAptitud.apto);
      expect(historica?.fechaFinVigencia, DateTime(2026, 11, 13));
    });

    test('Rechazar identificadores duplicados', () async {
      final repositorio = RepositorioPrueba();

      final evaluacion = EvaluacionAptitud(
        id: 'EV001',
        donanteId: 'DON001',
        resultado: ResultadoAptitud.apto,
        fechaEvaluacion: hoy,
        fechaFinVigencia: DateTime(2026, 11, 13),
        responsableId: 'ENF001',
        fechaRegistro: hoy,
      );

      await repositorio.guardar(evaluacion);

      await expectLater(repositorio.guardar(evaluacion), throwsStateError);

      // El registro original debe permanecer intacto.
      final guardada = await repositorio.buscarPorId('EV001');
      expect(guardada?.resultado, ResultadoAptitud.apto);
    });
  });
}
