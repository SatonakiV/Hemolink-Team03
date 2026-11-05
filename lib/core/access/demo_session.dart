import 'access_policy.dart';
import 'app_user.dart';

/// Estado en memoria para demostrar perfiles; no autentica credenciales.
class DemoSession {
  AppUser? _currentUser;

  AppUser? get currentUser => _currentUser;

  bool get canManageDonors => AccessPolicy.canManageDonors(_currentUser);

  void start(AppUser user) {
    if (!user.isVerified) {
      throw StateError('La cuenta de prueba debe estar verificada.');
    }
    _currentUser = user;
  }

  void end() {
    _currentUser = null;
  }
}
