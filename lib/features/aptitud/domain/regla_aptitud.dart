import 'evaluacion_aptitud.dart';

/// Aplica la regla de aptitud para determinar si
/// un donante está habilitado para donar.
class ReglaAptitud {
  const ReglaAptitud();

  /// Retorna true si la evaluación permite donar
  /// en la fecha consultada.
  bool puedeDonar(
    EvaluacionAptitud? evaluacion, {
    DateTime? fechaConsulta,
  }) {
    // 1. Sin evaluación, el donante no puede donar.
    if (evaluacion == null) {
      return false;
    }

    // 2. Solo un resultado APTO permite donar.
    if (evaluacion.resultado != ResultadoAptitud.apto) {
      return false;
    }

    // 3. Debe existir una fecha de fin de vigencia.
    final fechaFin = evaluacion.fechaFinVigencia;

    if (fechaFin == null) {
      return false;
    }

    // 4. Obtener la fecha que queremos comprobar.
    final fecha = fechaConsulta ?? DateTime.now();

    // 5. Normalizar las fechas para ignorar las horas.
    final hoy = _normalizarFecha(fecha);
    final inicio = _normalizarFecha(
      evaluacion.fechaEvaluacion,
    );
    final fin = _normalizarFecha(fechaFin);

    // 6. La fecha debe estar dentro del intervalo.
    if (hoy.isBefore(inicio)) {
      return false;
    }

    if (hoy.isAfter(fin)) {
      return false;
    }

    // 7. Se cumplen todas las condiciones.
    return true;
  }

  /// Compara fechas por día calendario, sin horas.
  DateTime _normalizarFecha(DateTime fecha) {
    return DateTime.utc(
      fecha.year,
      fecha.month,
      fecha.day,
    );
  }
}
