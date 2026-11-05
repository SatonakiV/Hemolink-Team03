import 'package:flutter/material.dart';

import '../../core/access/app_user.dart';
import '../../core/access/demo_session.dart';

class DemoAccessPage extends StatefulWidget {
  const DemoAccessPage({super.key});

  @override
  State<DemoAccessPage> createState() => _DemoAccessPageState();
}

class _DemoAccessPageState extends State<DemoAccessPage> {
  final _session = DemoSession();

  String _roleName(UserRole role) => switch (role) {
    UserRole.nursing => 'Enfermería',
    UserRole.inventory => 'Inventario',
    UserRole.hospital => 'Hospital',
  };

  void _enter(UserRole role) {
    setState(() {
      _session.start(
        AppUser(
          id: 'demo-${role.name}',
          role: role,
          isVerified: true,
          siteId: role == UserRole.hospital ? null : 'Sede demo',
          hospitalId: role == UserRole.hospital ? 'Hospital demo' : null,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = _session.currentUser;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bloodtype, size: 48, color: colors.primary),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'HemoLink',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text('Sistema de banco de sangre'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Cuentas ficticias · sesión local',
                    style: TextStyle(fontSize: 13, color: Color(0xFF586B65)),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Color(0xFFDCE4E0)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            user == null
                                ? 'Acceso de prueba'
                                : 'Sesión de prueba',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (user == null) ...[
                            const Text(
                              'Selecciona un perfil para revisar su acceso.',
                            ),
                            const SizedBox(height: 24),
                            for (final role in UserRole.values) ...[
                              OutlinedButton.icon(
                                onPressed: () => _enter(role),
                                icon: Icon(switch (role) {
                                  UserRole.nursing =>
                                    Icons.medical_services_outlined,
                                  UserRole.inventory =>
                                    Icons.inventory_2_outlined,
                                  UserRole.hospital =>
                                    Icons.local_hospital_outlined,
                                }),
                                label: Text(_roleName(role)),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(52),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                          ] else ...[
                            Text(
                              _roleName(user.role),
                              style: const TextStyle(fontSize: 18),
                            ),
                            const SizedBox(height: 20),
                            const Text('Cuenta de prueba'),
                            Text(
                              user.id,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              user.role == UserRole.hospital
                                  ? 'Hospital asociado'
                                  : 'Sede asociada',
                            ),
                            Text(
                              user.hospitalId ?? user.siteId!,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: _session.canManageDonors
                                    ? const Color(0xFFE8F3EE)
                                    : const Color(0xFFF0F3F2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    _session.canManageDonors
                                        ? Icons.check_circle_outline
                                        : Icons.lock_outline,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _session.canManageDonors
                                          ? 'Gestión de donantes habilitada'
                                          : 'Sin acceso a datos de donantes',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            FilledButton(
                              onPressed: () => setState(_session.end),
                              child: const Text('Cerrar sesión de prueba'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'La sesión es de prueba y se pierde al recargar.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF586B65)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
