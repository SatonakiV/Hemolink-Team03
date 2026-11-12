import '../domain/evaluacion_aptitud.dart';

abstract interface class EvaluacionRepository {
  Future<void> guardar(EvaluacionAptitud evaluacion);

  Future<EvaluacionAptitud?> buscarPorId(String id);

  Future<EvaluacionAptitud?> buscarActual(String donanteId);
}

/// Capacidad adicional para recuperar el historial completo.
abstract interface class HistorialEvaluacionRepository {
  Future<List<EvaluacionAptitud>> buscarHistorial(String donanteId);
}
