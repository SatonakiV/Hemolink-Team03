import 'package:flutter/foundation.dart';

import '../../../core/access/auth_session.dart';
import '../data/descarte_repository.dart';

/// Estado y lógica del panel de descarte (T07.2), separados del widget para
/// probarlos sin pantalla. El servidor vuelve a validar todo (T07.1).
class DescarteController extends ChangeNotifier {
  DescarteController(this.repositorio);

  final DescarteRepository repositorio;

  UnidadDescarte? _unidad;
  String _motivo = '';
  String? _error;
  String? _exito;
  bool _buscando = false;
  bool _guardando = false;
  bool _cerrado = false;

  UnidadDescarte? get unidad => _unidad;
  String get motivo => _motivo;
  String? get error => _error;
  String? get exito => _exito;
  bool get buscando => _buscando;
  bool get guardando => _guardando;

  /// UT07.2-A: sin motivo (o solo espacios) no se puede confirmar.
  bool get puedeConfirmar =>
      !_guardando &&
      !_buscando &&
      _unidad != null &&
      _unidad!.descartable &&
      _motivo.trim().isNotEmpty;

  Future<void> buscar(String codigo) async {
    final limpio = codigo.trim();
    _error = null;
    _exito = null;
    if (limpio.isEmpty) {
      _error = 'Ingresa el código de la unidad.';
      _avisar();
      return;
    }
    _buscando = true;
    _unidad = null;
    _avisar();
    try {
      _unidad = await repositorio.buscar(limpio);
    } catch (error) {
      _error = _mensaje(error, 'No se pudo buscar la unidad. Vuelve a intentar.');
    } finally {
      _buscando = false;
      _avisar();
    }
  }

  void cambiarMotivo(String texto) {
    _motivo = texto;
    _avisar();
  }

  /// Guarda el descarte. Devuelve true solo si el servidor lo confirmó.
  /// Ante un fallo conserva la unidad y el motivo escrito (UT07.2-C).
  Future<bool> descartar() async {
    final unidad = _unidad;
    if (!puedeConfirmar || unidad == null) {
      if (_motivo.trim().isEmpty && unidad != null) {
        _error = 'Indica el motivo del descarte.';
        _avisar();
      }
      return false;
    }
    _guardando = true;
    _error = null;
    _exito = null;
    _avisar();
    try {
      final resultado = await repositorio.descartar(unidad.id, _motivo.trim());
      _unidad = resultado.unidad;
      _motivo = '';
      _exito = resultado.repetido
          ? 'La unidad ya estaba descartada. Se conserva el primer registro.'
          : resultado.pedidosActualizados.isEmpty
          ? 'Unidad descartada.'
          : 'Unidad descartada. Se liberó su reserva y se actualizó el pedido.';
      return true;
    } catch (error) {
      _error = _mensaje(error, 'No se pudo guardar el descarte. Vuelve a intentar.');
      return false;
    } finally {
      _guardando = false;
      _avisar();
    }
  }

  static String _mensaje(Object error, String porDefecto) =>
      error is AuthException ? error.message : porDefecto;

  void _avisar() {
    if (!_cerrado) notifyListeners();
  }

  @override
  void dispose() {
    _cerrado = true;
    super.dispose();
  }
}