import 'app_user.dart';

/// Visibilidad de navegación. El servidor autoriza cada operación nuevamente.
abstract final class AccessPolicy {
  static bool canManageDonors(AppUser? user) =>
      user != null && user.isVerified && user.role == UserRole.nursing;

  static List<String> modulesFor(AppUser? user) {
    if (user == null || !user.isVerified) return const [];
    return switch (user.role) {
      UserRole.nursing => const ['donors', 'evaluations'],
      UserRole.inventory => const ['inventory'],
      UserRole.hospital => const ['requests'],
    };
  }
}
