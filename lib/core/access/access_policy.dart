import 'app_user.dart';

/// Visibilidad de navegación. El servidor autoriza cada operación nuevamente.
abstract final class AccessPolicy {
  static bool canManageDonors(AppUser? user) =>
      user != null && user.isVerified && user.role == UserRole.nursing;

  static bool canViewRequests(AppUser? user) =>
      user != null &&
      user.isVerified &&
      (user.role == UserRole.hospital || user.role == UserRole.inventory);

  static bool canCreateRequests(AppUser? user) =>
      user != null && user.isVerified && user.role == UserRole.hospital;

  static List<String> modulesFor(AppUser? user) {
    if (user == null || !user.isVerified) return const [];
    return switch (user.role) {
      UserRole.nursing => const ['donors', 'evaluations', 'donations'],
      UserRole.inventory => const ['inventory', 'requests'],
      UserRole.hospital => const ['requests'],
    };
  }
}
