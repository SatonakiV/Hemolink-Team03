import 'package:http/http.dart' as http;

import '../../../core/access/auth_session.dart';
import 'api_evaluacion_repository.dart';

/// Construye el repositorio de evaluaciones utilizando
/// la autenticación existente de HemoLink.
ApiEvaluacionRepository crearRepositorioEvaluaciones({
  required AuthSession sesion,
  required http.Client cliente,
}) {
  return ApiEvaluacionRepository(
    cliente: cliente,
    obtenerToken: () async => sesion.accessToken,
    urlBase: sesion.baseUrl,
  );
}
