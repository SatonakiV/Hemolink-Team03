import '../domain/evaluacion_aptitud.dart';

abstract interface class EvaluacionRepository {
  // Agrega una evaluación sin sobrescribir las anteriores.
  Future<void> guardar(EvaluacionAptitud evaluacion);

  // Recupera una evaluación mediante su identificador.
  Future<EvaluacionAptitud?> buscarPorId(String id);

  // Recupera la última evaluación del donante.
  Future<EvaluacionAptitud?> buscarActual(String donanteId);
}
