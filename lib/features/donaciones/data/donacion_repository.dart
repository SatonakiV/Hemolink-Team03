import '../domain/donacion.dart';

abstract interface class DonacionRepository {
  // Confirma donación y unidades juntas.
  Future<Donacion> guardar(DatosDonacion datos);

  // Un fallo de consulta se propaga como excepción.
  Future<Donacion?> buscarPorId(String id);

  // Donaciones de la sede de la sesión, de la más reciente a la más antigua.
  Future<List<ResumenDonacion>> listar();
}
