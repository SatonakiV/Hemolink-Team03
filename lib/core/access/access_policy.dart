import 'app_user.dart';

/// Reglas de acceso que también deberá aplicar el servidor en cada operación.
/// La comprobación local no sustituye la autorización en el backend.
abstract final class AccessPolicy {
  static bool canManageDonors(AppUser? user) =>
      user != null && user.isVerified && user.role == UserRole.nursing;
}
