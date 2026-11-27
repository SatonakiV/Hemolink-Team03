import '../domain/solicitud.dart';
import '../domain/validador_solicitud.dart';
import 'api_solicitud_repository.dart';
import 'solicitud_repository.dart';

/// Repositorio en memoria para desarrollo aislado y pruebas de la GUI.
class RepositorioSolicitudesSimulado implements SolicitudRepository {
  RepositorioSolicitudesSimulado({
    this.rolUsuario = 'hospital',
    this.hospitalIdUsuario = 'hospital-demo',
    this.responsableIdUsuario = 'hospital-demo',
    List<Solicitud> iniciales = const [],
    DateTime Function()? reloj,
  }) : _reloj = reloj ?? DateTime.now {
    _registros.addAll(iniciales);
  }

  final String rolUsuario;
  final String? hospitalIdUsuario;
  final String responsableIdUsuario;
  final DateTime Function() _reloj;
  final List<Solicitud> _registros = [];
  static const _validador = ValidadorSolicitud();

  @override
  Future<List<Solicitud>> listar() async {
    if (rolUsuario == 'inventory') {
      return ordenarSolicitudes(_registros);
    }
    if (rolUsuario == 'hospital') {
      return ordenarSolicitudes(
        _registros.where((s) => s.hospitalId == hospitalIdUsuario),
      );
    }
    throw const SolicitudApiException(
      403,
      'Tu perfil no puede consultar solicitudes.',
    );
  }

  @override
  Future<Solicitud> crear(DatosSolicitud datos) async {
    if (rolUsuario != 'hospital' ||
        hospitalIdUsuario == null ||
        hospitalIdUsuario!.trim().isEmpty) {
      throw const SolicitudApiException(
        403,
        'Solo el hospital puede ingresar solicitudes.',
      );
    }

    final validado = _validador.validarDatos(datos);
    final maxNumero = _registros.fold<int>(
      0,
      (max, s) => s.numero > max ? s.numero : max,
    );
    final numero = maxNumero + 1;
    final cantidad = validado.cantidad!;
    final nueva = Solicitud(
      id: 'sim-sol-$numero',
      numero: numero,
      hospitalId: hospitalIdUsuario!,
      responsableId: responsableIdUsuario,
      grupoAbo: validado.grupoAbo!,
      factorRh: validado.factorRh!,
      prioridad: validado.prioridad!,
      estado: 'pendiente',
      cantidadSolicitada: cantidad,
      cantidadDespachada: 0,
      cantidadReservada: 0,
      pendienteAsignar: cantidad,
      pendienteEntregar: cantidad,
      fechaRegistro: _reloj().toUtc(),
    );
    _registros.add(nueva);
    return nueva;
  }

  @override
  Future<Solicitud?> buscarPorId(String id) async {
    if (rolUsuario != 'hospital' && rolUsuario != 'inventory') {
      throw const SolicitudApiException(
        403,
        'Tu perfil no puede consultar solicitudes.',
      );
    }
    for (final s in _registros) {
      if (s.id != id) continue;
      if (rolUsuario == 'hospital' && s.hospitalId != hospitalIdUsuario) {
        return null;
      }
      return s;
    }
    return null;
  }
}
