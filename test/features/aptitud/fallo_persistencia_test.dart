import 'package:flutter_test/flutter_test.dart';

import 'package:hemolink/features/aptitud/data/evaluacion_repository.dart';
import 'package:hemolink/features/aptitud/domain/evaluacion_aptitud.dart';
import 'package:hemolink/features/aptitud/domain/registro_evaluaciones.dart';
import 'package:hemolink/features/aptitud/domain/validador_evaluacion.dart';

// Simula la existencia de un donante.
class DonantesPrueba implements ConsultaDonantes {
  @override
  Future<bool> existe(String id) async {
    return id == 'DON001';
  }
}

// Repositorio simulado que permite provocar un fallo.
class RepositorioConFallo implements EvaluacionRepository {
  final Map<String, EvaluacionAptitud> _evaluaciones = {};
  final Map<String, List<String>> _historial = {};

  bool fallarSiguienteGuardado = false;

  @override
  Future<void> guardar(EvaluacionAptitud evaluacion) async {
    // Simulamos un error antes de modificar los datos.
    if (fallarSiguienteGuardado) {
      fallarSiguienteGuardado = false;
      throw StateError('Error de almacenamiento simulado');
    }

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

  // Crea evaluaciones con datos válidos.
  EvaluacionAptitud crearEvaluacion(String id, ResultadoAptitud resultado) {
    return EvaluacionAptitud(
      id: id,
      donanteId: 'DON001',
      resultado: resultado,
      fechaEvaluacion: hoy,
      fechaFinVigencia: resultado == ResultadoAptitud.apto
          ? DateTime(2026, 11, 13)
          : null,
      fechaHabilitacion: resultado == ResultadoAptitud.diferido
          ? DateTime(2026, 12, 4)
          : null,
      responsableId: 'ENF001',
      fechaRegistro: hoy,
    );
  }

  group('T02.1 - UT5: Fallos de persistencia', () {
    late RepositorioConFallo repositorio;
    late RegistroEvaluaciones servicio;

    setUp(() {
      repositorio = RepositorioConFallo();

      servicio = RegistroEvaluaciones(
        repositorio: repositorio,
        validador: ValidadorEvaluacion(DonantesPrueba()),
      );
    });

    test('UT5-A: un fallo conserva la evaluación anterior', () async {
      final primera = crearEvaluacion('EV001', ResultadoAptitud.apto);

      final segunda = crearEvaluacion('EV002', ResultadoAptitud.diferido);

      // Registrar correctamente la primera evaluación.
      await servicio.registrar(primera, fechaActual: hoy);

      // Provocar un error en el siguiente guardado.
      repositorio.fallarSiguienteGuardado = true;

      await expectLater(
        servicio.registrar(segunda, fechaActual: hoy),
        throwsStateError,
      );

      // La primera evaluación debe continuar existiendo.
      final anterior = await servicio.consultarPorId('EV001');

      expect(anterior?.resultado, ResultadoAptitud.apto);

      // La evaluación actual no debe cambiar.
      final actual = await servicio.consultarActual('DON001');

      expect(actual?.id, 'EV001');

      // La segunda evaluación no debe haberse guardado.
      final fallida = await servicio.consultarPorId('EV002');

      expect(fallida, isNull);
    });

    test('UT5-B: permitir reintentar después del fallo', () async {
      final primera = crearEvaluacion('EV001', ResultadoAptitud.apto);

      final segunda = crearEvaluacion('EV002', ResultadoAptitud.diferido);

      await servicio.registrar(primera, fechaActual: hoy);

      // Primer intento: falla.
      repositorio.fallarSiguienteGuardado = true;

      await expectLater(
        servicio.registrar(segunda, fechaActual: hoy),
        throwsStateError,
      );

      // Segundo intento: funciona.
      await servicio.registrar(segunda, fechaActual: hoy);

      final actual = await servicio.consultarActual('DON001');
      final historica = await servicio.consultarPorId('EV001');

      expect(actual?.id, 'EV002');
      expect(historica?.id, 'EV001');
    });
  });
}
