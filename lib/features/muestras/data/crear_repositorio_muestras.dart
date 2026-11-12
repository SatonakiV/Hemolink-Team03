import 'package:http/http.dart' as http;
import '../../../core/access/auth_session.dart';
import 'api_muestra_repository.dart';

/// Usa la sesión activa y su dirección de API sin copiar.
ApiMuestraRepository crearRepositorioMuestras({
  required AuthSession sesion,
  required http.Client cliente,
}) => ApiMuestraRepository(
  cliente: cliente,
  obtenerToken: () async => sesion.accessToken,
  urlBase: sesion.baseUrl,
);
