class Muestra {
  final String id;
  final String codigo;
  final String donacionId;
  final String donanteId;
  final String scopeId;
  final String responsableId;
  final DateTime fechaRegistro;

  Muestra({
    this.id = '',
    required String codigo,
    required String donacionId,
    this.donanteId = '',
    this.scopeId = '',
    required String responsableId,
    required this.fechaRegistro,
  }) : codigo = codigo.trim(),
       donacionId = donacionId.trim(),
       responsableId = responsableId.trim() {
    if (this.codigo.isEmpty) {
      throw ArgumentError('El código de la muestra no puede estar vacío.');
    }
    if (this.donacionId.isEmpty) {
      throw ArgumentError(
        'La muestra debe estar asociada a una donación válida.',
      );
    }
  }
}

class UnidadSangre {
  final String codigo;
  final String donacionId;

  UnidadSangre({required String codigo, required String donacionId})
    : codigo = codigo.trim(),
      donacionId = donacionId.trim() {
    if (this.codigo.isEmpty) {
      throw ArgumentError('El código de la unidad no puede estar vacío.');
    }
    if (this.donacionId.isEmpty) {
      throw ArgumentError(
        'La unidad debe estar asociada a una donación válida.',
      );
    }
  }
}

/// Discrimina el tipo. No valida estado, vencimiento ni reservas de la unidad.
bool esUnidadSangre(Object? entidad) => entidad is UnidadSangre;

/// Compatibilidad con PR17: esta función solo discrimina tipos.
/// Los consumidores deben aplicar además estado, vencimiento, sede y reserva.
@Deprecated(
  'Usa esUnidadSangre y aplica las reglas de disponibilidad de la operación.',
)
bool esElegibleParaStock(Object? entidad) => esUnidadSangre(entidad);

/// Componente de dominio para la gestión y filtrado de muestras y unidades.
class RegistroMuestrasDominio {
  RegistroMuestrasDominio({required this.existeDonacion});
  final bool Function(String id) existeDonacion;
  final List<Muestra> _muestras = [];

  List<Muestra> get muestras => List.unmodifiable(_muestras);

  void registrarMuestra(Muestra muestra) {
    if (!existeDonacion(muestra.donacionId)) {
      throw ArgumentError('La donación de origen no existe.');
    }
    if (_muestras.any(
      (m) => m.codigo.toLowerCase() == muestra.codigo.toLowerCase(),
    )) {
      throw ArgumentError('Código de muestra duplicado: ${muestra.codigo}');
    }
    _muestras.add(muestra);
  }

  /// Separa unidades de muestras; no determina su disponibilidad operativa.
  static List<UnidadSangre> obtenerUnidades(List<dynamic> entidades) {
    return entidades.where(esUnidadSangre).cast<UnidadSangre>().toList();
  }

  @Deprecated(
    'Usa obtenerUnidades; la disponibilidad se valida en cada operación.',
  )
  static List<UnidadSangre> obtenerUnidadesElegiblesParaStock(
    List<dynamic> entidades,
  ) => obtenerUnidades(entidades);
}
