class Muestra {
  final String codigo;
  final String donacionId;
  final String responsableId;
  final DateTime fechaRegistro;

  Muestra({
    required String codigo,
    required String donacionId,
    required String responsableId,
    required this.fechaRegistro,
  })  : codigo = codigo.trim(),
        donacionId = donacionId.trim(),
        responsableId = responsableId.trim() {
    if (this.codigo.isEmpty) {
      throw ArgumentError('El código de la muestra no puede estar vacío.');
    }
    if (this.donacionId.isEmpty) {
      throw ArgumentError('La muestra debe estar asociada a una donación válida.');
    }
  }
}

class UnidadSangre {
  final String codigo;
  final String donacionId;

  UnidadSangre({
    required String codigo,
    required String donacionId,
  })  : codigo = codigo.trim(),
        donacionId = donacionId.trim() {
    if (this.codigo.isEmpty) {
      throw ArgumentError('El código de la unidad no puede estar vacío.');
    }
    if (this.donacionId.isEmpty) {
      throw ArgumentError('La unidad debe estar asociada a una donación válida.');
    }
  }
}

/// Evalúa si una entidad es elegible para inventario, reserva y despacho.
/// Una muestra jamás es elegible para stock; solo las instancias de [UnidadSangre] lo son.
bool esElegibleParaStock(dynamic entidad) {
  if (entidad is Muestra) return false;
  if (entidad is UnidadSangre) return true;
  return false;
}

/// Componente de dominio para la gestión y filtrado de muestras y unidades.
class RegistroMuestrasDominio {
  final List<Muestra> _muestras = [];

  List<Muestra> get muestras => List.unmodifiable(_muestras);

  void registrarMuestra(Muestra muestra) {
    if (_muestras.any((m) => m.codigo.toLowerCase() == muestra.codigo.toLowerCase())) {
      throw ArgumentError('Código de muestra duplicado: ${muestra.codigo}');
    }
    _muestras.add(muestra);
  }

  /// Filtra y devuelve solo las unidades elegibles para stock a partir de un listado mixto de entidades.
  static List<UnidadSangre> obtenerUnidadesElegiblesParaStock(List<dynamic> entidades) {
    return entidades
        .where((e) => esElegibleParaStock(e))
        .cast<UnidadSangre>()
        .toList();
  }
}
