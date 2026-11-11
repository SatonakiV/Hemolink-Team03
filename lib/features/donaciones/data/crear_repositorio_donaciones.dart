import 'package:http/http.dart' as http;
import '../../../core/access/auth_session.dart';
import 'api_donacion_repository.dart';

/// Usa la sesión activa y su dirección de API sin copiar.
ApiDonacionRepository crearRepositorioDonaciones({
  required AuthSession sesion,
  required http.Client cliente,
}) => ApiDonacionRepository(
  cliente: cliente,
  obtenerToken: () async => sesion.accessToken,
  urlBase: sesion.baseUrl,
);
