import '../data/evaluacion_repository.dart';
import 'evaluacion_aptitud.dart';
import 'regla_aptitud.dart';
import 'validador_evaluacion.dart';

/// Coordina el registro, consulta y verificación
/// de evaluaciones de aptitud de los donantes.
class RegistroEvaluaciones {
  final EvaluacionRepository repositorio;
  final ValidadorEvaluacion validador;

  const RegistroEvaluaciones({
    required this.repositorio,
    required this.validador,
  });

  /// Registra una evaluación después de validar sus datos.
  Future<void> registrar(
    EvaluacionAptitud evaluacion, {
    DateTime? fechaActual,
  }) async {
    // Primero comprobamos las reglas de validación.
    await validador.validar(
      evaluacion,
      fechaActual: fechaActual,
    );

    // Solo guardamos si la validación fue exitosa.
    await repositorio.guardar(evaluacion);
  }

  /// Recupera la evaluación más reciente del donante.
  Future<EvaluacionAptitud?> consultarActual(
    String donanteId,
  ) {
    return repositorio.buscarActual(donanteId);
  }

  /// Recupera una evaluación mediante su identificador.
  Future<EvaluacionAptitud?> consultarPorId(
    String id,
  ) {
    return repositorio.buscarPorId(id);
  }

  /// T02.2: determina si un donante puede realizar una donación.
  ///
  /// Consulta la evaluación más reciente y aplica la regla
  /// de aptitud sin modificar los datos almacenados.
  Future<bool> puedeDonar(
    String donanteId, {
    DateTime? fechaConsulta,
  }) async {
    // 1. Recuperar la última evaluación registrada.
    final evaluacion = await consultarActual(donanteId);

    // 2. Aplicar la regla de aptitud.
    const regla = ReglaAptitud();

    return regla.puedeDonar(
      evaluacion,
      fechaConsulta: fechaConsulta,
    );
  }
}
