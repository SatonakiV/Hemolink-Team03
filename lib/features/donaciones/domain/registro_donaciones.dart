import '../../aptitud/domain/evaluacion_aptitud.dart';
import '../data/donacion_repository.dart';
import 'donacion.dart';
import 'validador_donacion.dart';

class ValidacionDonacionException implements Exception {
  ValidacionDonacionException(Map<String, String> errores)
    : errores = Map.unmodifiable(errores);
  final Map<String, String> errores;

  @override
  String toString() => 'Revisa los datos de la donación.';
}

// Coordina la confirmación de una donación, valida y solo entonces guarda.
class RegistroDonaciones {
  RegistroDonaciones({
    required this.repositorio,
    this.validador = const ValidadorDonacion(),
    DateTime Function()? reloj,
  }) : _reloj = reloj ?? DateTime.now;
  final DonacionRepository repositorio;
  final ValidadorDonacion validador;
  final DateTime Function() _reloj;

  // Si se repite con la misma clave, el servidor devuelve la donación existente.
  Future<Donacion> confirmar(
    DatosDonacion datos, {
    required EvaluacionAptitud? evaluacion,
  }) async {
    final errores = validador.validar(
      datos,
      evaluacion: evaluacion,
      hoy: _reloj(),
    );
    if (errores.isNotEmpty) throw ValidacionDonacionException(errores);
    return repositorio.guardar(datos);
  }
} 