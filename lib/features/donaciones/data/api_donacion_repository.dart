import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/donacion.dart';
import 'donacion_repository.dart';

class DonacionApiException implements Exception {
  final int? codigo;
  final String mensaje;
  final Map<String, String> errores;
  DonacionApiException(
    this.codigo,
    this.mensaje, {
    Map<String, String> errores = const {},
  }) : errores = Map.unmodifiable(errores);

  @override
  String toString() => mensaje;
}

class ApiDonacionRepository implements DonacionRepository {
  final http.Client cliente;
  final Future<String?> Function() obtenerToken;
  final String urlBase;
  final Duration tiempoEspera;

  ApiDonacionRepository({
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

  static UnidadSangre _unidadDesdeJson(Object? valor) {
    final datos = valor as Map<String, dynamic>;
    return UnidadSangre(
      id: datos['id'] as String,
      codigo: datos['codigo'] as String,
      donacionId: datos['donacionId'] as String,
      grupoAbo: datos['grupoAbo'] as String,
      factorRh: datos['factorRh'] as String,
      sedeId: datos['sedeId'] as String,
      estado: EstadoUnidad.values.byName(datos['estado'] as String),
      fechaVencimiento: DateTime.parse(datos['fechaVencimiento'] as String),
    );
  }

  static Donacion _desdeJson(Object? valor) {
    final datos = valor as Map<String, dynamic>;
    return Donacion(
      id: datos['id'] as String,
      donanteId: datos['donanteId'] as String,
      evaluacionId: datos['evaluacionId'] as String,
      fechaExtraccion: DateTime.parse(datos['fechaExtraccion'] as String),
      volumenMl: datos['volumenMl'] as int,
      sedeId: datos['sedeId'] as String,
      responsableId: datos['responsableId'] as String,
      fechaRegistro: DateTime.parse(datos['fechaRegistro'] as String),
      unidades: (datos['unidades'] as List).map(_unidadDesdeJson).toList(),
    );
  }

  Future<T> _solicitar<T>(
    String ruta, {
    required T Function(Map<String, dynamic>) convertir,
    Map<String, dynamic>? cuerpo,
    Set<int> estadosEsperados = const {200},
    T Function()? siAusente,
  }) async {
    final token = await obtenerToken();
    if (token == null || token.trim().isEmpty) {
      throw DonacionApiException(
        401,
        'Debes iniciar sesión para gestionar donaciones.',
      );
    }
    final uri = Uri.parse('$urlBase/api/donations$ruta');
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
      throw DonacionApiException(
        null,
        'El servidor tardó demasiado. Vuelve a intentar.',
      );
    } on http.ClientException {
      throw DonacionApiException(
        null,
        'No fue posible conectar con el servidor.',
      );
    }

    if (siAusente != null && respuesta.statusCode == 404) return siAusente();
    try {
      final datos =
          jsonDecode(utf8.decode(respuesta.bodyBytes)) as Map<String, dynamic>;
      if (!estadosEsperados.contains(respuesta.statusCode)) {
        final errores = datos['errors'];
        throw DonacionApiException(
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
      throw DonacionApiException(
        respuesta.statusCode,
        'El servidor devolvió una respuesta inválida.',
      );
    } on TypeError {
      throw DonacionApiException(
        respuesta.statusCode,
        'El servidor devolvió una respuesta incompleta.',
      );
    } on ArgumentError {
      throw DonacionApiException(
        respuesta.statusCode,
        'El servidor devolvió un estado de unidad desconocido.',
      );
    }
  }

  @override
  Future<Donacion> guardar(DatosDonacion datos) => _solicitar(
    '',
    estadosEsperados: const {200,201},
    cuerpo: {
      'claveConfirmacion': datos.claveConfirmacion,
      'donanteId': datos.donanteId,
      'evaluacionId': datos.evaluacionId,
      'fechaExtraccion': _fecha(datos.fechaExtraccion),
      'volumenMl': datos.volumenMl,
      'unidades': [
        for (final codigo in datos.codigosUnidades) {'codigo': codigo},
      ],
    },
    convertir: (datos) => _desdeJson(datos['item']),
  );

  @override
  Future<Donacion?> buscarPorId(String id) => _solicitar(
    '/${Uri.encodeComponent(id)}',
    siAusente: () => null,
    convertir: (datos) => _desdeJson(datos['item']),);
}
