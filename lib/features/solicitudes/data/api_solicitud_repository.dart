import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/solicitud.dart';
import '../domain/validador_solicitud.dart';
import 'solicitud_repository.dart';

class SolicitudApiException implements Exception {
  const SolicitudApiException(
    this.codigo,
    this.mensaje, {
    this.errores = const {},
  });

  final int? codigo;
  final String mensaje;
  final Map<String, String> errores;

  @override
  String toString() => mensaje;
}

class ApiSolicitudRepository implements SolicitudRepository {
  ApiSolicitudRepository({
    required this.cliente,
    required this.obtenerToken,
    this.urlBase = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8080',
    ),
    this.tiempoEspera = const Duration(seconds: 10),
  });

  final http.Client cliente;
  final Future<String?> Function() obtenerToken;
  final String urlBase;
  final Duration tiempoEspera;
  static const _validador = ValidadorSolicitud();

  static bool _esSolicitudCompleta(Map<String, dynamic> json) =>
      json['cantidadSolicitada'] is int &&
      (json['cantidadSolicitada'] as int) > 0 &&
      json['grupoAbo'] is String &&
      json['factorRh'] is String &&
      json['prioridad'] is String &&
      json['fechaRegistro'] is String;

  static Solicitud _desdeJson(Object? valor) {
    final json = valor as Map<String, dynamic>;
    final solicitada = json['cantidadSolicitada'] as int;
    final despachada = (json['cantidadDespachada'] as int?) ?? 0;
    final reservada = (json['cantidadReservada'] as int?) ?? 0;
    final pendienteEntregar =
        (json['pendienteEntregar'] as int?) ?? (solicitada - despachada);
    final pendienteAsignar =
        (json['pendienteAsignar'] as int?) ?? (pendienteEntregar - reservada);

    final reservasRaw = json['reservas'] as List<dynamic>? ?? const [];
    final avisosRaw = json['avisos'] as List<dynamic>? ?? const [];
    final despachosRaw = json['despachos'] as List<dynamic>? ?? const [];

    return Solicitud(
      id: json['id'] as String,
      numero: (json['numero'] as int?) ?? 0,
      hospitalId: (json['hospitalId'] ?? json['scopeId'] ?? '') as String,
      responsableId: (json['responsableId'] ?? '') as String,
      grupoAbo: json['grupoAbo'] as String,
      factorRh: json['factorRh'] as String,
      prioridad: json['prioridad'] as String,
      estado: (json['estado'] as String?) ?? 'pendiente',
      cantidadSolicitada: solicitada,
      cantidadDespachada: despachada,
      cantidadReservada: reservada,
      pendienteAsignar: pendienteAsignar,
      pendienteEntregar: pendienteEntregar,
      fechaRegistro: DateTime.parse(json['fechaRegistro'] as String),
      reservas: reservasRaw
          .cast<Map<String, dynamic>>()
          .map(ReservaSolicitud.fromJson)
          .toList(),
      avisos: avisosRaw
          .cast<Map<String, dynamic>>()
          .map(AvisoSolicitud.fromJson)
          .toList(),
      despachos: despachosRaw
          .cast<Map<String, dynamic>>()
          .map(DespachoSolicitud.fromJson)
          .toList(),
    );
  }

  Future<T> _solicitar<T>(
    String ruta, {
    required T Function(Map<String, dynamic>) convertir,
    String metodo = 'GET',
    Map<String, dynamic>? cuerpo,
    int estadoEsperado = 200,
    T Function()? siAusente,
  }) async {
    final token = await obtenerToken();
    if (token == null || token.trim().isEmpty) {
      throw const SolicitudApiException(
        401,
        'Debes iniciar sesión para consultar o crear solicitudes.',
      );
    }

    final uri = Uri.parse('$urlBase/api/requests$ruta');
    final encabezados = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    http.Response respuesta;
    try {
      final Future<http.Response> llamada = metodo == 'POST'
          ? cliente.post(uri, headers: encabezados, body: jsonEncode(cuerpo))
          : cliente.get(uri, headers: encabezados);
      respuesta = await llamada.timeout(tiempoEspera);
    } on TimeoutException {
      throw const SolicitudApiException(
        null,
        'El servidor tardó demasiado. Vuelve a intentar.',
      );
    } on http.ClientException {
      throw const SolicitudApiException(
        null,
        'No fue posible conectar con el servidor.',
      );
    }

    if (siAusente != null && respuesta.statusCode == 404) {
      return siAusente();
    }

    try {
      final datos =
          jsonDecode(utf8.decode(respuesta.bodyBytes)) as Map<String, dynamic>;
      if (respuesta.statusCode != estadoEsperado) {
        final errores = datos['errors'];
        throw SolicitudApiException(
          respuesta.statusCode,
          datos['message'] is String
              ? datos['message'] as String
              : 'No se pudo completar la operación.',
          errores: errores is Map<String, dynamic>
              ? errores.map(
                  (campo, mensaje) => MapEntry(campo, mensaje.toString()),
                )
              : const {},
        );
      }
      return convertir(datos);
    } on SolicitudApiException {
      rethrow;
    } on FormatException {
      throw SolicitudApiException(
        respuesta.statusCode,
        'El servidor devolvió una respuesta inválida.',
      );
    } on TypeError {
      throw SolicitudApiException(
        respuesta.statusCode,
        'El servidor devolvió una respuesta incompleta.',
      );
    }
  }

  @override
  Future<List<Solicitud>> listar() => _solicitar(
    '',
    convertir: (datos) => [
      for (final item in (datos['items'] as List).cast<Map<String, dynamic>>())
        if (_esSolicitudCompleta(item)) _desdeJson(item),
    ],
  );

  @override
  Future<Solicitud> crear(DatosSolicitud datos) async {
    final entrada = _validador.validarDatos(datos);
    return _solicitar(
      '',
      metodo: 'POST',
      estadoEsperado: 201,
      cuerpo: {
        'grupoAbo': entrada.grupoAbo,
        'factorRh': entrada.factorRh,
        'cantidad': entrada.cantidad,
        'prioridad': entrada.prioridad,
      },
      convertir: (respuesta) => _desdeJson(respuesta['item']),
    );
  }

  @override
  Future<Solicitud?> buscarPorId(String id) => _solicitar(
    '/${Uri.encodeComponent(id)}',
    siAusente: () => null,
    convertir: (respuesta) => _desdeJson(respuesta['item']),
  );
}
