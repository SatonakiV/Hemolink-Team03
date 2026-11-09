import 'package:http/http.dart' as http;

import '../../../core/access/auth_session.dart';
import 'api_donante_repository.dart';

/// Utiliza la sesión activa y su dirección de API sin copiar o persistir el token.
ApiDonanteRepository crearRepositorioDonantes({
  required AuthSession sesion,
  required http.Client cliente,
}) => ApiDonanteRepository(
  cliente: cliente,
  obtenerToken: () async => sesion.accessToken,
  urlBase: sesion.baseUrl,
);
