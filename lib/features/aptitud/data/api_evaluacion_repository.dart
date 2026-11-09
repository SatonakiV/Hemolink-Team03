import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/evaluacion_aptitud.dart';
import 'evaluacion_repository.dart';

// Error producido al comunicarse con el backend.
class EvaluacionApiException implements Exception {
  final int? codigo;
  final String mensaje;

  const EvaluacionApiException(this.codigo, this.mensaje);

  @override
  String toString() => mensaje;
}

// Implementación HTTP del contrato EvaluacionRepository.
class ApiEvaluacionRepository implements EvaluacionRepository {
  final http.Client cliente;
  final Future<String?> Function() obtenerToken;
  final String urlBase;

  ApiEvaluacionRepository({
    required this.cliente,
    required this.obtenerToken,
    this.urlBase = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8080',
    ),
  });

  // Convierte DateTime al formato YYYY-MM-DD del servidor.
  String _fecha(DateTime fecha) {
    final anio = fecha.year.toString().padLeft(4, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    final dia = fecha.day.toString().padLeft(2, '0');
    return '$anio-$mes-$dia';
  }

  // Convierte un campo de fecha JSON a DateTime.
  DateTime? _fechaOpcional(Object? valor) {
    if (valor == null) return null;
    return DateTime.parse(valor as String);
  }

  // Convierte la respuesta JSON del backend al modelo Dart.
  EvaluacionAptitud _desdeJson(Map<String, dynamic> datos) {
    final resultado = ResultadoAptitud.values.byName(
      datos['resultado'] as String,
    );

    return EvaluacionAptitud(
      id: datos['id'] as String,
      donanteId: datos['donanteId'] as String,
      resultado: resultado,
      fechaEvaluacion: DateTime.parse(
        datos['fechaEvaluacion'] as String,
      ),
      fechaFinVigencia: _fechaOpcional(datos['fechaFinVigencia']),
      fechaHabilitacion: _fechaOpcional(datos['fechaHabilitacion']),
      responsableId: datos['responsableId'] as String,
      fechaRegistro: DateTime.parse(
        datos['fechaRegistro'] as String,
      ),
    );
  }

  // Solicita el token del usuario que inició sesión.
  Future<Map<String, String>> _encabezados() async {
    final token = await obtenerToken();

    if (token == null || token.isEmpty) {
      throw const EvaluacionApiException(
        401,
        'Debes iniciar sesión para gestionar evaluaciones.',
      );
    }

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // Verifica el resultado de una solicitud HTTP.
  Map<String, dynamic> _procesarRespuesta(
    http.Response respuesta, {
    int? estadoEsperado,
  }) {
    Map<String, dynamic> datos;

    try {
      final contenido = jsonDecode(
        utf8.decode(respuesta.bodyBytes),
      );

      if (contenido is! Map<String, dynamic>) {
        throw const FormatException('Respuesta incorrecta');
      }

      datos = contenido;
    } catch (_) {
      throw EvaluacionApiException(
        respuesta.statusCode,
        'El servidor devolvió una respuesta no válida.',
      );
    }

    final correcto = estadoEsperado == null
        ? respuesta.statusCode >= 200 && respuesta.statusCode < 300
        : respuesta.statusCode == estadoEsperado;

    if (!correcto) {
      throw EvaluacionApiException(
        respuesta.statusCode,
        datos['message'] is String
            ? datos['message'] as String
            : 'No se pudo completar la operación.',
      );
    }

    return datos;
  }

  // Registra una nueva evaluación en el backend.
  @override
  Future<void> guardar(EvaluacionAptitud evaluacion) async {
    final uri = Uri.parse('$urlBase/api/evaluations');

    final datos = {
      'id': evaluacion.id,
      'donanteId': evaluacion.donanteId,
      'resultado': evaluacion.resultado.name,
      'fechaEvaluacion': _fecha(evaluacion.fechaEvaluacion),
      'fechaFinVigencia': evaluacion.fechaFinVigencia == null
          ? null
          : _fecha(evaluacion.fechaFinVigencia!),
      'fechaHabilitacion': evaluacion.fechaHabilitacion == null
          ? null
          : _fecha(evaluacion.fechaHabilitacion!),
    };

    try {
      final respuesta = await cliente.post(
        uri,
        headers: await _encabezados(),
        body: jsonEncode(datos),
      );

      _procesarRespuesta(
        respuesta,
        estadoEsperado: 201,
      );
    } on http.ClientException catch (_) {
      throw const EvaluacionApiException(
        null,
        'No fue posible conectar con el servidor.',
      );
    }
  }

  // Busca una evaluación mediante su identificador.
  @override
  Future<EvaluacionAptitud?> buscarPorId(String id) async {
    final uri = Uri.parse(
      '$urlBase/api/evaluations/${Uri.encodeComponent(id)}',
    );

    try {
      final respuesta = await cliente.get(
        uri,
        headers: await _encabezados(),
      );

      if (respuesta.statusCode == 404) {
        return null;
      }

      final datos = _procesarRespuesta(respuesta);

      return _desdeJson(
        datos['item'] as Map<String, dynamic>,
      );
    } on http.ClientException catch (_) {
      throw const EvaluacionApiException(
        null,
        'No fue posible conectar con el servidor.',
      );
    }
  }

  // Recupera la última evaluación registrada del donante.
  @override
  Future<EvaluacionAptitud?> buscarActual(
    String donanteId,
  ) async {
    final uri = Uri.parse(
      '$urlBase/api/evaluations',
    ).replace(
      queryParameters: {'donanteId': donanteId},
    );

    try {
      final respuesta = await cliente.get(
        uri,
        headers: await _encabezados(),
      );

      final datos = _procesarRespuesta(respuesta);
      final historial = datos['items'] as List<dynamic>;

      if (historial.isEmpty) {
        return null;
      }

      // El servidor devuelve el historial en orden descendente.
      return _desdeJson(
        historial.first as Map<String, dynamic>,
      );
    } on http.ClientException catch (_) {
      throw const EvaluacionApiException(
        null,
        'No fue posible conectar con el servidor.',
      );
    }
  }
}
