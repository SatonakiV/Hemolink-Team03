import '../domain/solicitud.dart';

abstract interface class SolicitudRepository {
  Future<List<Solicitud>> listar();
  Future<Solicitud> crear(DatosSolicitud datos);
  Future<Solicitud?> buscarPorId(String id);
}
