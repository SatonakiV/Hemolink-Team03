import '../domain/donante.dart';

abstract interface class DonanteRepository {
  /// El servidor asigna identificador, usuario y fecha; devuelve la ficha guardada.
  Future<Donante> guardar(DatosDonante datos);

  /// Sin filtros devuelve el listado; ambos filtros juntos se combinan con AND.
  Future<List<Donante>> buscar({String? rut, String? nombre});

  /// null significa inexistente; un fallo de consulta se propaga como excepción.
  Future<Donante?> buscarPorId(String id);

  /// Actualiza antecedentes manteniendo identificador y metadatos originales;
  /// registra usuario y fecha de modificación.
  Future<Donante> actualizar(String id, DatosDonante datos);
}
