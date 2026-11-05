import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/core/access/app_user.dart';
import 'package:hemolink/core/access/demo_session.dart';

void main() {
  late DemoSession session;

  setUp(() => session = DemoSession());

  AppUser user(UserRole role, {bool verified = true}) => AppUser(
    id: 'usuario-demo',
    role: role,
    isVerified: verified,
    siteId: role == UserRole.hospital ? null : 'sede-demo',
    hospitalId: role == UserRole.hospital ? 'hospital-demo' : null,
  );

  test('la demostración inicia sin usuario ni permiso de donantes', () {
    expect(session.currentUser, isNull);
    expect(session.canManageDonors, isFalse);
  });

  test('enfermería verificada conserva su sede y habilita donantes', () {
    session.start(user(UserRole.nursing));

    expect(session.currentUser?.siteId, 'sede-demo');
    expect(session.canManageDonors, isTrue);
  });

  for (final role in [UserRole.inventory, UserRole.hospital]) {
    test('$role no obtiene permiso para gestionar donantes', () {
      session.start(user(role));

      expect(session.currentUser?.role, role);
      expect(session.canManageDonors, isFalse);
    });
  }

  test('rechaza una cuenta no verificada sin abrir una sesión', () {
    expect(
      () => session.start(user(UserRole.nursing, verified: false)),
      throwsStateError,
    );
    expect(session.currentUser, isNull);
    expect(session.canManageDonors, isFalse);
  });

  test('cerrar elimina el usuario y revoca el permiso de donantes', () {
    session.start(user(UserRole.nursing));
    session.end();

    expect(session.currentUser, isNull);
    expect(session.canManageDonors, isFalse);
  });
}
