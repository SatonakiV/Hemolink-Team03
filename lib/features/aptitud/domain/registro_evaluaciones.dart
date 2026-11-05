import '../data/evaluacion_repository.dart';
import 'evaluacion_aptitud.dart';
import 'validador_evaluacion.dart';

class RegistroEvaluaciones {
  final EvaluacionRepository repositorio;
  final ValidadorEvaluacion validador;

  const RegistroEvaluaciones({
    required this.repositorio,
    required this.validador,
  });

  // Registra una evaluación después de validarla.
  Future<void> registrar(
    EvaluacionAptitud evaluacion, {
    DateTime? fechaActual,
  }) async {
    await validador.validar(evaluacion, fechaActual: fechaActual);

    await repositorio.guardar(evaluacion);
  }

  // Consulta la evaluación actual.
  Future<EvaluacionAptitud?> consultarActual(String donanteId) {
    return repositorio.buscarActual(donanteId);
  }

  // Recupera una evaluación histórica.
  Future<EvaluacionAptitud?> consultarPorId(String id) {
    return repositorio.buscarPorId(id);
  }
}
