import 'package:flutter/foundation.dart';
import '../../../core/access/app_user.dart';
import '../../aptitud/data/api_evaluacion_repository.dart';
import '../../aptitud/data/evaluacion_repository.dart';
import '../../aptitud/domain/evaluacion_aptitud.dart';
import '../../aptitud/domain/regla_aptitud.dart';
import '../../donantes/data/api_donante_repository.dart';
import '../../donantes/data/donante_repository.dart';
import '../../donantes/domain/donante.dart';
import '../data/api_donacion_repository.dart';
import '../domain/donacion.dart';
import '../domain/registro_donaciones.dart';

// Estado y lógica del formulario de donación (T03.3), separados del widget para poder probarlos sin pantalla.
// La sede y el vencimiento solo se muestran: la sede sale de la sesión y el vencimiento se calcula. Ninguno se envía al servidor.
class FormularioDonacionController extends ChangeNotifier {
  FormularioDonacionController({
    required this.usuario,
    required this.donantes,
    required this.evaluaciones,
    required this.registro,
    DateTime Function()? reloj,
    String? claveConfirmacion,
  }) : _reloj = reloj ?? DateTime.now,
       claveConfirmacion = claveConfirmacion ?? generarClaveConfirmacion() {
    final hoy = _reloj();
    _fechaExtraccion = DateTime(hoy.year, hoy.month, hoy.day);
  }

  final AppUser? usuario;
  final DonanteRepository donantes;
  final EvaluacionRepository evaluaciones;
  final RegistroDonaciones registro;
  final DateTime Function() _reloj;

  /// Se genera una sola vez por formulario. Si el guardado falla y se reintenta,
  /// se reenvía la misma clave y el servidor no duplica la donación (T03.2).
  final String claveConfirmacion;

  List<Donante> _listaDonantes = const [];
  Donante? _donante;
  EvaluacionAptitud? _evaluacion;
  late DateTime _fechaExtraccion;
  String _volumen = '';
  final List<String> _codigos = [];
  Map<String, String> _errores = const {};
  String? _errorGeneral;
  bool _cargandoDonantes = false;
  bool _cargandoEvaluacion = false;
  bool _guardando = false;
  bool _cerrado = false;

  List<Donante> get listaDonantes => _listaDonantes;
  Donante? get donante => _donante;
  EvaluacionAptitud? get evaluacion => _evaluacion;
  DateTime get fechaExtraccion => _fechaExtraccion;
  DateTime get hoy {
    final ahora = _reloj();
    return DateTime(ahora.year, ahora.month, ahora.day);
  }

  String get volumen => _volumen;
  List<String> get codigos => List.unmodifiable(_codigos);
  Map<String, String> get errores => _errores;
  String? get errorGeneral => _errorGeneral;
  bool get cargandoDonantes => _cargandoDonantes;
  bool get cargandoEvaluacion => _cargandoEvaluacion;
  bool get guardando => _guardando;

  bool get autorizado =>
      usuario != null &&
      usuario!.isVerified &&
      usuario!.role == UserRole.nursing;

  /// Sede de la cuenta de la sesión; no se puede editar.
  String get sede => usuario?.siteId ?? 'Sin sede asociada';

  /// Vencimiento calculado (extracción + 42 días); no se puede editar.
  DateTime get vencimiento => calcularVencimiento(_fechaExtraccion);

  /// Resultado de la regla de HU02 para la fecha de extracción elegida.
  bool get aptoParaExtraccion =>
      _evaluacion != null &&
      const ReglaAptitud().puedeDonar(
        _evaluacion,
        fechaConsulta: _fechaExtraccion,
      );

  Future<void> cargarDonantes() async {
    _cargandoDonantes = true;
    _errorGeneral = null;
    _avisar();
    try {
      _listaDonantes = List.unmodifiable(await donantes.buscar());
    } catch (error) {
      _errorGeneral = _mensaje(error, 'No se pudo cargar la lista de donantes.');
    } finally {
      _cargandoDonantes = false;
      _avisar();
    }
  }

  Future<void> seleccionarDonante(String? id) async {
    _donante = null;
    for (final candidato in _listaDonantes) {
      if (candidato.id == id) _donante = candidato;
    }
    _evaluacion = null;
    _errores = Map.of(_errores)
      ..remove('donanteId')
      ..remove('evaluacionId');
    final pedido = _donante?.id;
    if (pedido == null) {
      _avisar();
      return;
    }
    _cargandoEvaluacion = true;
    _avisar();
    try {
      final actual = await evaluaciones.buscarActual(pedido);
      // Si cambió la selección mientras se consultaba, se descarta la respuesta.
      if (_donante?.id == pedido) _evaluacion = actual;
    } catch (error) {
      _errorGeneral = _mensaje(
        error,
        'No se pudo consultar la aptitud del donante.',
      );
    } finally {
      _cargandoEvaluacion = false;
      _avisar();
    }
  }

  void cambiarFecha(DateTime fecha) {
    _fechaExtraccion = DateTime(fecha.year, fecha.month, fecha.day);
    _errores = Map.of(_errores)
      ..remove('fechaExtraccion')
      ..remove('evaluacionId');
    _avisar();
  }

  void cambiarVolumen(String texto) {
    _volumen = texto;
    if (_errores.containsKey('volumenMl')) {
      _errores = Map.of(_errores)..remove('volumenMl');
      _avisar();
    }
  }

  /// Devuelve true si la unidad se agregó.
  bool agregarUnidad(String codigo) {
    final limpio = codigo.trim();
    String? error;
    if (limpio.isEmpty) {
      error = 'Ingresa el código de la unidad.';
    } else if (_codigos.any((c) => c.toLowerCase() == limpio.toLowerCase())) {
      error = 'El código $limpio ya está en la lista.';
    }
    _errores = Map.of(_errores);
    if (error != null) {
      _errores['unidades'] = error;
      _avisar();
      return false;
    }
    _errores.remove('unidades');
    _codigos.add(limpio);
    _avisar();
    return true;
  }

  void quitarUnidad(String codigo) {
    _codigos.remove(codigo);
    _avisar();
  }

  /// Valida y guarda. Devuelve la donación confirmada, o null si hubo errores.
  /// Ante cualquier fallo conserva todo lo escrito.
  Future<Donacion?> confirmar() async {
    if (_guardando) return null;
    _errorGeneral = null;
    if (!autorizado) {
      _errorGeneral = 'Tu perfil no puede registrar donaciones.';
      _avisar();
      return null;
    }

    final volumen = int.tryParse(_volumen.trim());
    final datos = DatosDonacion(
      claveConfirmacion: claveConfirmacion,
      donanteId: _donante?.id ?? '',
      evaluacionId: _evaluacion?.id ?? '',
      fechaExtraccion: _fechaExtraccion,
      volumenMl: volumen ?? 0,
      codigosUnidades: _codigos,
    );

    _guardando = true;
    _errores = const {};
    _avisar();
    try {
      return await registro.confirmar(datos, evaluacion: _evaluacion);
    } on ValidacionDonacionException catch (error) {
      _errores = _ajustarErrores(error.errores, volumen);
      _errorGeneral = 'Revisar los datos marcados antes de confirmar.';
    } on DonacionApiException catch (error) {
      _errores = error.errores;
      _errorGeneral = error.mensaje;
    } catch (_) {
      _errorGeneral = 'No se pudo guardar la donación. Vuelva a intentar.';
    } finally {
      _guardando = false;
      _avisar();
    }
    return null;
  }
  Map<String, String> _ajustarErrores(Map<String, String> base, int? volumen) {
    final errores = Map.of(base);
    if (_donante == null) {
      errores['donanteId'] = 'Selecciona un donante.';
      errores.remove('evaluacionId');
    }
    if (volumen == null) {
      errores['volumenMl'] = _volumen.trim().isEmpty
          ? 'Ingrese el volumen en mililitros.'
          : 'El volumen debe ser un número entero de mililitros.';
    }
    return errores;
  }
  static String _mensaje(Object error, String porDefecto) => switch (error) {
    DonacionApiException(:final mensaje) => mensaje,
    DonanteApiException(:final mensaje) => mensaje,
    EvaluacionApiException(:final mensaje) => mensaje,
    _ => porDefecto,
  };

  void _avisar() {
    if (!_cerrado) notifyListeners();
  }

  @override
  void dispose() {
    _cerrado = true;
    super.dispose();
  }
}