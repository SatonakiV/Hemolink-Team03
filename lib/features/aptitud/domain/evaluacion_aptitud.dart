enum ResultadoAptitud { apto, diferido, rechazado }

class EvaluacionAptitud {
  final String id;
  final String donanteId;
  final ResultadoAptitud resultado;

  final DateTime fechaEvaluacion;
  final DateTime? fechaFinVigencia;
  final DateTime? fechaHabilitacion;

  final String responsableId;
  final DateTime fechaRegistro;

  const EvaluacionAptitud({
    required this.id,
    required this.donanteId,
    required this.resultado,
    required this.fechaEvaluacion,
    this.fechaFinVigencia,
    this.fechaHabilitacion,
    required this.responsableId,
    required this.fechaRegistro,
  });
}
