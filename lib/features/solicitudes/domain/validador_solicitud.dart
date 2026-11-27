import 'solicitud.dart';

class ValidacionSolicitudException implements Exception {
  ValidacionSolicitudException(Map<String, String> errores)
    : errores = Map.unmodifiable(errores);

  final Map<String, String> errores;

  @override
  String toString() => errores.values.join(' ');
}

class ValidadorSolicitud {
  const ValidadorSolicitud();

  static const Set<String> gruposAboValidos = {'A', 'B', 'AB', 'O'};
  static const Set<String> factoresRhValidos = {'positivo', 'negativo'};
  static const Set<String> prioridadesValidas = {'urgente', 'normal'};

  DatosSolicitud validarEntrada({
    String? grupoAbo,
    String? factorRh,
    required String cantidadTexto,
    String? prioridad,
  }) {
    final texto = cantidadTexto.trim();
    int? cantidad;
    String? errorCantidad;

    if (texto.isEmpty) {
      errorCantidad = 'La cantidad solicitada es obligatoria.';
    } else {
      final parsed = int.tryParse(texto);
      if (parsed == null) {
        errorCantidad =
            'La cantidad solicitada debe ser un número entero positivo.';
      } else if (parsed <= 0) {
        errorCantidad = 'La cantidad solicitada debe ser un entero positivo.';
      } else {
        cantidad = parsed;
      }
    }

    try {
      return validarDatos(
        DatosSolicitud(
          grupoAbo: grupoAbo,
          factorRh: factorRh,
          cantidad: cantidad,
          prioridad: prioridad,
        ),
      );
    } on ValidacionSolicitudException catch (error) {
      final errores = Map<String, String>.from(error.errores);
      if (errorCantidad != null) {
        errores['cantidad'] = errorCantidad;
      }
      throw ValidacionSolicitudException(errores);
    }
  }

  DatosSolicitud validarDatos(DatosSolicitud datos) {
    final errores = <String, String>{};
    final grupo = datos.grupoAbo?.trim().toUpperCase() ?? '';
    final rh = datos.factorRh?.trim().toLowerCase() ?? '';
    final cantidad = datos.cantidad;
    final prioridad = datos.prioridad?.trim().toLowerCase() ?? '';

    if (!gruposAboValidos.contains(grupo)) {
      errores['grupoAbo'] = 'Selecciona un grupo sanguíneo A, B, AB u O.';
    }
    if (!factoresRhValidos.contains(rh)) {
      errores['factorRh'] = 'Selecciona un factor Rh positivo o negativo.';
    }
    if (cantidad == null || cantidad <= 0) {
      errores['cantidad'] =
          'La cantidad solicitada debe ser un entero positivo.';
    }
    if (!prioridadesValidas.contains(prioridad)) {
      errores['prioridad'] = 'Selecciona una prioridad (urgente o normal).';
    }

    if (errores.isNotEmpty) {
      throw ValidacionSolicitudException(errores);
    }

    return DatosSolicitud(
      grupoAbo: grupo,
      factorRh: rh,
      cantidad: cantidad,
      prioridad: prioridad,
    );
  }
}

int compararSolicitudes(Solicitud a, Solicitud b) {
  int pesoPrioridad(String p) => p.toLowerCase() == 'urgente' ? 0 : 1;
  final prioridadDiff = pesoPrioridad(a.prioridad) - pesoPrioridad(b.prioridad);
  if (prioridadDiff != 0) return prioridadDiff;

  final fechaDiff = a.fechaRegistro.compareTo(b.fechaRegistro);
  if (fechaDiff != 0) return fechaDiff;

  return a.id.compareTo(b.id);
}

List<Solicitud> ordenarSolicitudes(Iterable<Solicitud> solicitudes) =>
    solicitudes.toList()..sort(compararSolicitudes);
