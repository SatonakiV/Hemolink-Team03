import 'package:http/http.dart' as http;

import '../../../core/access/auth_session.dart';
import 'api_solicitud_repository.dart';

/// Crea el repositorio de solicitudes usando la sesión activa y su API.
ApiSolicitudRepository crearRepositorioSolicitudes({
  required AuthSession sesion,
  http.Client? cliente,
}) => ApiSolicitudRepository(
  cliente: cliente ?? sesion.client,
  obtenerToken: () async => sesion.accessToken,
  urlBase: sesion.baseUrl,
);
