import '../data/evaluacion_repository.dart';
import 'evaluacion_aptitud.dart';
import 'regla_aptitud.dart';
import 'validador_evaluacion.dart';

/// Decisión y referencia obtenidas en una sola consulta para una extracción.
/// HU03 debe persistir evaluacionId y revalidarla al guardar en el servidor.
class DecisionAptitud {
  const DecisionAptitud._({
    required this.donanteId,
    required this.fechaExtraccion,
    required this.evaluacion,
  });
  final String donanteId;
  final DateTime fechaExtraccion;
  final EvaluacionAptitud? evaluacion;
  String? get evaluacionId => evaluacion?.id;
  bool get autorizada => const ReglaAptitud().puedeDonar(
    evaluacion,
    fechaConsulta: fechaExtraccion,
  );
}

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
    await validador.validar(evaluacion, fechaActual: fechaActual);

    // Solo guardamos si la validación fue exitosa.
    await repositorio.guardar(evaluacion);
  }

  /// Recupera la evaluación más reciente del donante.
  Future<EvaluacionAptitud?> consultarActual(String donanteId) {
    return repositorio.buscarActual(donanteId);
  }

  /// Recupera una evaluación mediante su identificador.
  Future<EvaluacionAptitud?> consultarPorId(String id) {
    return repositorio.buscarPorId(id);
  }

  /// HU03: exige el día de extracción y conserva la evaluación utilizada.
  Future<DecisionAptitud> evaluarDonacion(
    String donanteId, {
    required DateTime fechaExtraccion,
  }) async => DecisionAptitud._(
    donanteId: donanteId,
    fechaExtraccion: DateTime(
      fechaExtraccion.year,
      fechaExtraccion.month,
      fechaExtraccion.day,
    ),
    evaluacion: await consultarActual(donanteId),
  );

  /// T02.2: consulta informativa; para una extracción usar evaluarDonacion.
  ///
  /// Consulta la evaluación más reciente y aplica la regla
  /// de aptitud sin modificar los datos almacenados.
  Future<bool> puedeDonar(String donanteId, {DateTime? fechaConsulta}) async {
    return (await evaluarDonacion(
      donanteId,
      fechaExtraccion: fechaConsulta ?? DateTime.now(),
    )).autorizada;
  }
}
