enum UserRole { nursing, inventory, hospital }

/// Identidad que deberá proporcionar el servicio de autenticación.
class AppUser {
  AppUser({
    required String id,
    required this.role,
    required this.isVerified,
    String? siteId,
    String? hospitalId,
  }) : id = id.trim(),
       siteId = siteId?.trim(),
       hospitalId = hospitalId?.trim() {
    if (this.id.isEmpty) {
      throw ArgumentError('El usuario debe tener un identificador.');
    }

    if (role == UserRole.hospital) {
      if (this.hospitalId == null || this.hospitalId!.isEmpty) {
        throw ArgumentError('El usuario hospitalario debe tener un hospital.');
      }
      if (this.siteId != null) {
        throw ArgumentError('El usuario hospitalario no pertenece a una sede.');
      }
    } else {
      if (this.siteId == null || this.siteId!.isEmpty) {
        throw ArgumentError('El personal del banco debe tener una sede.');
      }
      if (this.hospitalId != null) {
        throw ArgumentError(
          'El personal del banco no pertenece a un hospital.',
        );
      }
    }
  }

  final String id;
  final UserRole role;
  final bool isVerified;
  final String? siteId;
  final String? hospitalId;
}
