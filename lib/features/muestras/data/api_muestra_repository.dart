import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../domain/muestra.dart';
import 'muestra_repository.dart';

class MuestraApiException implements Exception {
  final int? codigo;
  final String mensaje;
  final Map<String, String> errores;

  MuestraApiException(
    this.codigo,
    this.mensaje, {
    Map<String, String> errores = const {},
  }) : errores = Map.unmodifiable(errores);

  @override
  String toString() => mensaje;
}

class ApiMuestraRepository implements MuestraRepository {
  final http.Client cliente;
  final Future<String?> Function() obtenerToken;
  final String urlBase;
  final Duration tiempoEspera;

  ApiMuestraRepository({
    required this.cliente,
    required this.obtenerToken,
    this.urlBase = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8080',
    ),
    this.tiempoEspera = const Duration(seconds: 10),
  });

  static Muestra _desdeJson(Object? valor) {
    final datos = valor as Map<String, dynamic>;
    return Muestra(
      id: datos['id'] as String,
      codigo: datos['codigo'] as String,
      donacionId: datos['donacionId'] as String,
      donanteId: datos['donanteId'] as String,
      scopeId: datos['scopeId'] as String,
      responsableId: datos['responsableId'] as String,
      fechaRegistro: DateTime.parse(datos['fechaRegistro'] as String),
    );
  }

  Future<T> _solicitar<T>(
    String ruta, {
    required T Function(Map<String, dynamic>) convertir,
    Map<String, dynamic>? cuerpo,
    int estadoEsperado = 200,
    Map<String, String>? parametrosConsulta,
    T Function()? siAusente,
  }) async {
    final token = await obtenerToken();
    if (token == null || token.trim().isEmpty) {
      throw MuestraApiException(
        401,
        'Debes iniciar sesión para gestionar muestras.',
      );
    }
    var uri = Uri.parse('$urlBase/api/samples$ruta');
    if (parametrosConsulta != null && parametrosConsulta.isNotEmpty) {
      uri = uri.replace(queryParameters: parametrosConsulta);
    }
    final encabezados = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    http.Response respuesta;
    try {
      respuesta =
          await (cuerpo == null
                  ? cliente.get(uri, headers: encabezados)
                  : cliente.post(
                      uri,
                      headers: encabezados,
                      body: jsonEncode(cuerpo),
                    ))
              .timeout(tiempoEspera);
    } on TimeoutException {
      throw MuestraApiException(
        null,
        'El servidor tardó demasiado. Vuelve a intentar.',
      );
    } on http.ClientException {
      throw MuestraApiException(
        null,
        'No fue posible conectar con el servidor.',
      );
    }

    if (siAusente != null && respuesta.statusCode == 404) return siAusente();
    try {
      final contenido = jsonDecode(utf8.decode(respuesta.bodyBytes));
      if (contenido is! Map<String, dynamic>) {
        throw const FormatException('Respuesta incorrecta');
      }
      if (respuesta.statusCode != estadoEsperado) {
        final errores = contenido['errors'];
        throw MuestraApiException(
          respuesta.statusCode,
          contenido['message'] is String
              ? contenido['message'] as String
              : 'No se pudo completar la operación.',
          errores: errores is Map<String, dynamic>
              ? errores.map(
                  (campo, mensaje) => MapEntry(campo, mensaje as String),
                )
              : const {},
        );
      }
      return convertir(contenido);
    } on FormatException {
      throw MuestraApiException(
        respuesta.statusCode,
        'El servidor devolvió una respuesta inválida.',
      );
    } on TypeError {
      throw MuestraApiException(
        respuesta.statusCode,
        'El servidor devolvió una respuesta incompleta.',
      );
    }
  }

  @override
  Future<Muestra> guardar(DatosMuestra datos) => _solicitar(
    '',
    estadoEsperado: 201,
    cuerpo: {
      'codigo': datos.codigo,
      'donacionId': datos.donacionId,
    },
    convertir: (datos) => _desdeJson(datos['item']),
  );

  @override
  Future<List<Muestra>> buscar({String? donacionId}) async {
    final parametros = <String, String>{};
    if (donacionId != null && donacionId.trim().isNotEmpty) {
      parametros['donacionId'] = donacionId.trim();
    }
    return _solicitar(
      '',
      estadoEsperado: 200,
      parametrosConsulta: parametros.isEmpty ? null : parametros,
      convertir: (datos) {
        final lista = datos['items'] as List<dynamic>;
        return lista.map(_desdeJson).toList();
      },
    );
  }

  @override
  Future<Muestra?> buscarPorId(String id) => _solicitar(
    '/${Uri.encodeComponent(id)}',
    siAusente: () => null,
    convertir: (datos) => _desdeJson(datos['item']),
  );
}
