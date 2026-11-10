import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/donante.dart';
import '../domain/validador_donante.dart';
import 'donante_repository.dart';

class DonanteApiException implements Exception {
  final int? codigo;
  final String mensaje;
  final Map<String, String> errores;

  DonanteApiException(
    this.codigo,
    this.mensaje, {
    Map<String, String> errores = const {},
  }) : errores = Map.unmodifiable(errores);

  @override
  String toString() => mensaje;
}

class ApiDonanteRepository implements DonanteRepository {
  final http.Client cliente;
  final Future<String?> Function() obtenerToken;
  final String urlBase;
  final Duration tiempoEspera;
  static const _validador = ValidadorDonante();

  ApiDonanteRepository({
    required this.cliente,
    required this.obtenerToken,
    this.urlBase = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8080',
    ),
    this.tiempoEspera = const Duration(seconds: 10),
  });

  static String _fecha(DateTime fecha) =>
      '${fecha.year.toString().padLeft(4, '0')}-'
      '${fecha.month.toString().padLeft(2, '0')}-'
      '${fecha.day.toString().padLeft(2, '0')}';

  static DateTime _fechaCivil(String valor) {
    final fecha = DateTime.parse(valor);
    if (_fecha(fecha) != valor) {
      throw const FormatException('Fecha civil inválida.');
    }
    return fecha;
  }

  static Donante _desdeJson(Object? valor) {
    final datos = valor as Map<String, dynamic>;
    return _validador.validar(
      DatosDonante(
        rut: datos['rut'] as String,
        nombre: datos['nombre'] as String,
        fechaNacimiento: _fechaCivil(datos['fechaNacimiento'] as String),
        pesoKg: (datos['pesoKg'] as num).toDouble(),
        grupoAbo: datos['grupoAbo'] as String,
        factorRh: datos['factorRh'] as String,
        telefono: datos['telefono'] as String,
      ),
      id: datos['id'] as String,
      usuarioRegistroId: datos['usuarioRegistroId'] as String,
      fechaRegistro: DateTime.parse(datos['fechaRegistro'] as String),
    );
  }

  Future<T> _solicitar<T>(
    String ruta, {
    required T Function(Map<String, dynamic>) convertir,
    Map<String, dynamic>? cuerpo,
    Map<String, String>? filtros,
    int estadoEsperado = 200,
    T Function()? siAusente,
  }) async {
    final token = await obtenerToken();
    if (token == null || token.trim().isEmpty) {
      throw DonanteApiException(
        401,
        'Debes iniciar sesión para gestionar donantes.',
      );
    }
    final uri = Uri.parse('$urlBase/api/donors$ruta')
        .replace(queryParameters: filtros?.isEmpty == true ? null : filtros);
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
      throw DonanteApiException(
        null,
        'El servidor tardó demasiado. Vuelve a intentar.',
      );
    } on http.ClientException {
      throw DonanteApiException(
        null,
        'No fue posible conectar con el servidor.',
      );
    }

    // Solo un 404 de ficha es ausencia. Otros fallos nunca son lista vacía o éxito.
    if (siAusente != null && respuesta.statusCode == 404) {
      return siAusente();
    }
    try {
      final datos =
          jsonDecode(utf8.decode(respuesta.bodyBytes)) as Map<String, dynamic>;
      if (respuesta.statusCode != estadoEsperado) {
        final errores = datos['errors'];
        throw DonanteApiException(
          respuesta.statusCode,
          datos['message'] is String
              ? datos['message'] as String
              : 'No se pudo completar la operación.',
          errores: errores is Map<String, dynamic>
              ? errores.map(
                  (campo, mensaje) => MapEntry(campo, mensaje as String),
                )
              : const {},
        );
      }
      return convertir(datos);
    } on FormatException {
      throw DonanteApiException(
        respuesta.statusCode,
        'El servidor devolvió una respuesta inválida.',
      );
    } on TypeError {
      throw DonanteApiException(
        respuesta.statusCode,
        'El servidor devolvió una respuesta incompleta.',
      );
    } on ValidacionDonanteException {
      throw DonanteApiException(
        respuesta.statusCode,
        'El servidor devolvió una ficha inválida.',
      );
    }
  }

  @override
  Future<Donante> guardar(DatosDonante datos) async {
    final entrada = _validador.validarDatos(datos);
    return _solicitar(
      '',
      estadoEsperado: 201,
      cuerpo: {
        'rut': entrada.rut,
        'nombre': entrada.nombre,
        'fechaNacimiento': _fecha(entrada.fechaNacimiento!),
        'pesoKg': entrada.pesoKg,
        'grupoAbo': entrada.grupoAbo,
        'factorRh': entrada.factorRh,
        'telefono': entrada.telefono,
      },
      convertir: (datos) => _desdeJson(datos['item']),
    );
  }

  @override
  Future<List<Donante>> buscar({String? rut, String? nombre}) => _solicitar(
    '',
    filtros: {
      if (rut != null && rut.trim().isNotEmpty) 'rut': rut.trim(),
      if (nombre != null && nombre.trim().isNotEmpty) 'nombre': nombre.trim(),
    },
    convertir: (datos) => (datos['items'] as List).map(_desdeJson).toList(),
  );

  @override
  Future<Donante?> buscarPorId(String id) => _solicitar(
    '/${Uri.encodeComponent(id)}',
    siAusente: () => null,
    convertir: (datos) => _desdeJson(datos['item']),
  );
}
