/// Datos de entrada: admite campos ausentes para informar errores de validación.
class DatosDonante {
  final String? rut;
  final String? nombre;
  final DateTime? fechaNacimiento;
  final double? pesoKg;
  final String? grupoAbo;
  final String? factorRh;
  final String? telefono;

  const DatosDonante({
    this.rut,
    this.nombre,
    this.fechaNacimiento,
    this.pesoKg,
    this.grupoAbo,
    this.factorRh,
    this.telefono,
  });
}

/// Antecedentes normalizados y metadatos del registro, sin datos clínicos.
class Donante {
  final String id;
  final String rut;
  final String nombre;
  final DateTime fechaNacimiento;
  final double pesoKg;
  final String grupoAbo;
  final String factorRh;
  final String telefono;
  final String usuarioRegistroId;
  final DateTime fechaRegistro;

  const Donante({
    required this.id,
    required this.rut,
    required this.nombre,
    required this.fechaNacimiento,
    required this.pesoKg,
    required this.grupoAbo,
    required this.factorRh,
    required this.telefono,
    required this.usuarioRegistroId,
    required this.fechaRegistro,
  });
}
