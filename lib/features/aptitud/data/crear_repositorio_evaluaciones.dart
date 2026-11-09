import 'package:http/http.dart' as http;
import '../../../core/access/auth_session.dart';
import '../../../core/access/token_store.dart';
import 'api_evaluacion_repository.dart';

/// Construye el repositorio de evaluaciones utilizando
/// la autenticación existente de HemoLink.
ApiEvaluacionRepository crearRepositorioEvaluaciones({
  required AuthSession sesion,
  required http.Client cliente,
}) {
  // Utiliza el mismo almacenamiento de tokens que AuthSession.
  final almacenTokens = SecureTokenStore(
    server: sesion.baseUrl,
  );

  return ApiEvaluacionRepository(
    cliente: cliente,

    // Lee el token guardado por el inicio de sesión.
    obtenerToken: almacenTokens.read,

    // Reutiliza la dirección del servidor de Diego.
    urlBase: sesion.baseUrl,
  );
}
