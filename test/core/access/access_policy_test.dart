import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/core/access/access_policy.dart';
import 'package:hemolink/core/access/app_user.dart';

void main() {
  group('Usuario y pertenencia institucional', () {
    test('enfermería e inventario pertenecen a una sede', () {
      for (final role in [UserRole.nursing, UserRole.inventory]) {
        final user = AppUser(
          id: 'usuario-prueba',
          role: role,
          isVerified: true,
          siteId: 'sede-prueba',
        );

        expect(user.siteId, 'sede-prueba');
        expect(user.hospitalId, isNull);
      }
    });

    test('el personal hospitalario pertenece a un hospital', () {
      final user = AppUser(
        id: 'hospital-prueba',
        role: UserRole.hospital,
        isVerified: true,
        hospitalId: 'hospital-01',
      );

      expect(user.hospitalId, 'hospital-01');
      expect(user.siteId, isNull);
    });

    test('rechaza un identificador de usuario vacío', () {
      expect(
        () => AppUser(
          id: '  ',
          role: UserRole.nursing,
          isVerified: true,
          siteId: 'sede-prueba',
        ),
        throwsArgumentError,
      );
    });

    for (final role in [UserRole.nursing, UserRole.inventory]) {
      test('$role requiere una sede válida', () {
        for (final siteId in [null, '', '  ']) {
          expect(
            () => AppUser(
              id: 'usuario-prueba',
              role: role,
              isVerified: true,
              siteId: siteId,
            ),
            throwsArgumentError,
          );
        }
      });

      test('$role no se asocia también a un hospital', () {
        expect(
          () => AppUser(
            id: 'usuario-prueba',
            role: role,
            isVerified: true,
            siteId: 'sede-prueba',
            hospitalId: 'hospital-prueba',
          ),
          throwsArgumentError,
        );
      });
    }

    test('hospital requiere una institución válida', () {
      for (final hospitalId in [null, '', '  ']) {
        expect(
          () => AppUser(
            id: 'usuario-prueba',
            role: UserRole.hospital,
            isVerified: true,
            hospitalId: hospitalId,
          ),
          throwsArgumentError,
        );
      }
    });

    test('hospital no se asocia también a una sede', () {
      expect(
        () => AppUser(
          id: 'usuario-prueba',
          role: UserRole.hospital,
          isVerified: true,
          hospitalId: 'hospital-prueba',
          siteId: 'sede-prueba',
        ),
        throwsArgumentError,
      );
    });
  });

  group('Acceso a donantes - T01.1', () {
    test('UT01.1-C: sin sesión no puede gestionar donantes', () {
      expect(AccessPolicy.canManageDonors(null), isFalse);
    });

    test('permite gestionar donantes a enfermería verificada', () {
      final user = AppUser(
        id: 'enfermeria-prueba',
        role: UserRole.nursing,
        isVerified: true,
        siteId: 'sede-prueba',
      );

      expect(AccessPolicy.canManageDonors(user), isTrue);
    });

    test('UT01.1-B: enfermería sin verificar no tiene acceso', () {
      final user = AppUser(
        id: 'enfermeria-prueba',
        role: UserRole.nursing,
        isVerified: false,
        siteId: 'sede-prueba',
      );

      expect(AccessPolicy.canManageDonors(user), isFalse);
    });

    test('UT01.1-C: inventario no puede gestionar donantes', () {
      final user = AppUser(
        id: 'inventario-prueba',
        role: UserRole.inventory,
        isVerified: true,
        siteId: 'sede-prueba',
      );

      expect(AccessPolicy.canManageDonors(user), isFalse);
    });

    test('UT01.1-C: hospital no puede gestionar donantes', () {
      final user = AppUser(
        id: 'hospital-prueba',
        role: UserRole.hospital,
        isVerified: true,
        hospitalId: 'hospital-01',
      );

      expect(AccessPolicy.canManageDonors(user), isFalse);
    });
  });

  group('Módulos de navegación - T03.1', () {
    AppUser usuario(UserRole role) => AppUser(
      id: 'usuario-prueba',
      role: role,
      isVerified: true,
      siteId: role == UserRole.hospital ? null : 'sede-prueba',
      hospitalId: role == UserRole.hospital ? 'hospital-01' : null,
    );

    test('solo enfermería verificada ve Donaciones', () {
      expect(
        AccessPolicy.modulesFor(usuario(UserRole.nursing)),
        contains('donations'),
      );
      expect(
        AccessPolicy.modulesFor(usuario(UserRole.inventory)),
        isNot(contains('donations')),
      );
      expect(
        AccessPolicy.modulesFor(usuario(UserRole.hospital)),
        isNot(contains('donations')),
      );
      expect(AccessPolicy.modulesFor(null), isEmpty);
    });
  });
}
