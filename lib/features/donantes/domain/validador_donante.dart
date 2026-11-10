import 'donante.dart';
import 'validador_rut.dart';

class ValidacionDonanteException implements Exception {
  final Map<String, String> errores;

  ValidacionDonanteException(Map<String, String> errores)
    : errores = Map.unmodifiable(errores);

  @override
  String toString() => errores.values.join(' ');
}

class ValidadorDonante {
  const ValidadorDonante();

  /// Devuelve el donante validado; no genera identificadores ni guarda datos.
  /// El servicio de registro debe proporcionar los metadatos autorizados.
  Donante validar(
    DatosDonante datos, {
    required String id,
    required String usuarioRegistroId,
    required DateTime fechaRegistro,
    DateTime? fechaActual,
  }) {
    final normalizados = validarDatos(datos, fechaActual: fechaActual);
    final errores = <String, String>{};
    if (id.trim().isEmpty) {
      errores['id'] = 'El identificador del donante es obligatorio.';
    }
    if (usuarioRegistroId.trim().isEmpty) {
      errores['usuarioRegistroId'] = 'El usuario de registro es obligatorio.';
    }
    if (errores.isNotEmpty) throw ValidacionDonanteException(errores);
    return Donante(
      id: id.trim(),
      rut: normalizados.rut!,
      nombre: normalizados.nombre!,
      fechaNacimiento: normalizados.fechaNacimiento!,
      pesoKg: normalizados.pesoKg!,
      grupoAbo: normalizados.grupoAbo!,
      factorRh: normalizados.factorRh!,
      telefono: normalizados.telefono!,
      usuarioRegistroId: usuarioRegistroId.trim(),
      fechaRegistro: fechaRegistro,
    );
  }

  /// Valida antecedentes antes de enviarlos, sin inventar metadatos del servidor.
  DatosDonante validarDatos(DatosDonante datos, {DateTime? fechaActual}) {
    final errores = <String, String>{};
    final rut = datos.rut?.trim() ?? '';
    final nombre = datos.nombre?.trim() ?? '';
    final nacimiento = datos.fechaNacimiento;
    final peso = datos.pesoKg;
    final grupo = datos.grupoAbo?.trim().toUpperCase() ?? '';
    final rh = datos.factorRh?.trim().toLowerCase() ?? '';
    final telefono = datos.telefono?.trim() ?? '';
    final hoy = _soloFecha(fechaActual ?? DateTime.now());

    if (!ValidadorRut.esValido(rut)) {
      errores['rut'] =
          'Ingresa un RUT con formato y dígito verificador válidos.';
    }
    if (nombre.isEmpty) {
      errores['nombre'] = 'El nombre es obligatorio.';
    }
    if (nacimiento == null) {
      errores['fechaNacimiento'] = 'La fecha de nacimiento es obligatoria.';
    } else if (_soloFecha(nacimiento).isAfter(hoy)) {
      errores['fechaNacimiento'] =
          'La fecha de nacimiento no puede ser futura.';
    }
    if (peso == null || !peso.isFinite || peso <= 0) {
      errores['pesoKg'] = 'El peso debe ser un número positivo en kilogramos.';
    }
    if (!const {'A', 'B', 'AB', 'O'}.contains(grupo)) {
      errores['grupoAbo'] = 'Selecciona un grupo sanguíneo A, B, AB u O.';
    }
    if (!const {'positivo', 'negativo'}.contains(rh)) {
      errores['factorRh'] = 'Selecciona un factor Rh positivo o negativo.';
    }
    if (telefono.isEmpty) {
      errores['telefono'] = 'El teléfono es obligatorio.';
    }
    if (errores.isNotEmpty) throw ValidacionDonanteException(errores);

    return DatosDonante(
      rut: ValidadorRut.normalizar(rut),
      nombre: nombre,
      fechaNacimiento: DateTime(
        nacimiento!.year,
        nacimiento.month,
        nacimiento.day,
      ),
      pesoKg: peso,
      grupoAbo: grupo,
      factorRh: rh,
      telefono: telefono,
    );
  }

  static DateTime _soloFecha(DateTime fecha) =>
      DateTime.utc(fecha.year, fecha.month, fecha.day);
}
