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
        responsableId = responsableId.trim();
}

// Una muestra jamás es elegible para inventario/stock
bool esElegibleParaStock(dynamic entidad) {
  if (entidad is Muestra) return false;
  return false;
}
