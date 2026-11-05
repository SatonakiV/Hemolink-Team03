import 'evaluacion_aptitud.dart';

abstract interface class ConsultaDonantes {
  Future<bool> existe(String id);
}

class ValidacionEvaluacionException implements Exception {
  final String mensaje;

  const ValidacionEvaluacionException(this.mensaje);

  @override
  String toString() => mensaje;
}

class ValidadorEvaluacion {
  final ConsultaDonantes consultaDonantes;

  const ValidadorEvaluacion(this.consultaDonantes);

  // Compara únicamente el día, mes y año.
  DateTime _soloFecha(DateTime fecha) {
    return DateTime.utc(fecha.year, fecha.month, fecha.day);
  }

  Future<void> validar(
    EvaluacionAptitud evaluacion, {
    DateTime? fechaActual,
  }) async {
    final hoy = _soloFecha(fechaActual ?? DateTime.now());
    final fechaEvaluacion = _soloFecha(evaluacion.fechaEvaluacion);

    // 1. Comprobar identificadores obligatorios.
    if (evaluacion.id.trim().isEmpty ||
        evaluacion.donanteId.trim().isEmpty ||
        evaluacion.responsableId.trim().isEmpty) {
      throw const ValidacionEvaluacionException('Faltan datos obligatorios.');
    }

    // 2. Comprobar que el donante exista.
    final existe = await consultaDonantes.existe(evaluacion.donanteId);

    if (!existe) {
      throw const ValidacionEvaluacionException('El donante no existe.');
    }

    // 3. Rechazar evaluaciones futuras.
    if (fechaEvaluacion.isAfter(hoy)) {
      throw const ValidacionEvaluacionException(
        'La fecha de evaluación no puede ser futura.',
      );
    }

    // 4. Validar las fechas según el resultado.
    switch (evaluacion.resultado) {
      case ResultadoAptitud.apto:
        final fin = evaluacion.fechaFinVigencia;

        if (fin == null) {
          throw const ValidacionEvaluacionException(
            'El resultado apto requiere fecha de vigencia.',
          );
        }

        if (_soloFecha(fin).isBefore(fechaEvaluacion)) {
          throw const ValidacionEvaluacionException(
            'El fin de vigencia no puede ser anterior '
            'a la evaluación.',
          );
        }

      case ResultadoAptitud.diferido:
        final habilitacion = evaluacion.fechaHabilitacion;

        if (habilitacion == null) {
          throw const ValidacionEvaluacionException(
            'El resultado diferido requiere '
            'fecha de habilitación.',
          );
        }

        if (_soloFecha(habilitacion).isBefore(fechaEvaluacion)) {
          throw const ValidacionEvaluacionException(
            'La habilitación no puede ser anterior '
            'a la evaluación.',
          );
        }

      case ResultadoAptitud.rechazado:
        // No requiere fechas adicionales.
        break;
    }
  }
}
