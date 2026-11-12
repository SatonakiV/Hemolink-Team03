import '../../../domain/muestra.dart';

class DatosMuestra {
  final String codigo;
  final String donacionId;

  DatosMuestra({
    required String codigo,
    required String donacionId,
  }) : codigo = codigo.trim(),
       donacionId = donacionId.trim() {
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

abstract interface class MuestraRepository {
  /// Registra una nueva muestra en el servidor y devuelve la ficha guardada.
  Future<Muestra> guardar(DatosMuestra datos);

  /// Busca muestras, opcionalmente filtradas por donación.
  Future<List<Muestra>> buscar({String? donacionId});

  /// Busca una muestra por su identificador; null si no existe.
  Future<Muestra?> buscarPorId(String id);
}
