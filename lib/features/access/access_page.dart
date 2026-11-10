import 'package:flutter/material.dart';

import '../../core/access/access_policy.dart';
import '../../core/access/app_user.dart';
import '../../core/access/auth_session.dart';

const moduleNames = {
  'donors': 'Donantes',
  'evaluations': 'Evaluaciones',
  'inventory': 'Inventario',
  'requests': 'Solicitudes',
};

class AccessPage extends StatefulWidget {
  const AccessPage({super.key, this.session});
  final AuthSession? session;

  @override
  State<AccessPage> createState() => _AccessPageState();
}

class _AccessPageState extends State<AccessPage> {
  late final _session = widget.session ?? AuthSession();
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = true;
  bool _restoreFailed = false;
  String? _error;
  String? _module;
  List<Map<String, dynamic>>? _items;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    _restoreFailed = false;
    await _perform(() async {
      try {
        await _session.restore();
      } catch (_) {
        _restoreFailed = true;
        rethrow;
      }
    });
  }

  Future<void> _perform(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AuthException catch (error) {
      _error = error.message;
    } catch (_) {
      _error = 'No se pudo recuperar o guardar la sesión. Vuelve a intentar.';
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          if (_session.currentUser == null) {
            _module = null;
            _items = null;
          }
        });
      }
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    await _perform(() async {
      await _session.login(_email.text, _password.text);
      _password.clear();
    });
  }

  String _descripcionRegistro(Map<String, dynamic> item) {
    final label = item['label'];
    if (label is String && label.trim().isNotEmpty) return label;
    if (_module == 'evaluations') {
      final resultado = switch (item['resultado']) {
        'apto' => 'Apto',
        'diferido' => 'Diferido temporalmente',
        'rechazado' => 'Rechazado permanentemente',
        _ => 'Evaluación',
      };
      final donante = item['donanteId'];
      final fecha = item['fechaEvaluacion'];
      return [
        resultado,
        if (donante is String && donante.isNotEmpty) 'Donante $donante',
        if (fecha is String && fecha.isNotEmpty) fecha,
      ].join(' · ');
    }
    final nombre = item['nombre'];
    if (nombre is String && nombre.trim().isNotEmpty) return nombre;
    final id = item['id'];
    return id is String ? 'Registro $id' : 'Registro sin descripción.';
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    if (widget.session == null) _session.dispose();
    super.dispose();
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
                  Card(
                    margin: EdgeInsets.zero,
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            user == null ? 'Iniciar sesión' : 'Mi sesión',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_busy) ...[
                            const LinearProgressIndicator(),
                            const SizedBox(height: 16),
                          ],
                          if (_error != null) ...[
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                _error!,
                                style: TextStyle(color: colors.error),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (_restoreFailed)
                            OutlinedButton(
                              onPressed: _busy ? null : _restore,
                              child: const Text('Reintentar conexión'),
                            )
                          else if (user == null)
                            Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TextFormField(
                                    controller: _email,
                                    enabled: !_busy,
                                    decoration: const InputDecoration(
                                      labelText: 'Correo electrónico',
                                    ),
                                    keyboardType: TextInputType.emailAddress,
                                    autofillHints: const [
                                      AutofillHints.username,
                                    ],
                                    textInputAction: TextInputAction.next,
                                    validator: (value) =>
                                        value == null || !value.contains('@')
                                        ? 'Ingresa tu correo electrónico.'
                                        : null,
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _password,
                                    enabled: !_busy,
                                    decoration: const InputDecoration(
                                      labelText: 'Contraseña',
                                    ),
                                    obscureText: true,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    autofillHints: const [
                                      AutofillHints.password,
                                    ],
                                    onFieldSubmitted: (_) {
                                      if (!_busy) _login();
                                    },
                                    validator: (value) =>
                                        value == null || value.isEmpty
                                        ? 'Ingresa tu contraseña.'
                                        : null,
                                  ),
                                  const SizedBox(height: 24),
                                  FilledButton(
                                    onPressed: _busy ? null : _login,
                                    child: const Text('Entrar'),
                                  ),
                                ],
                              ),
                            )
                          else ...[
                            Text(
                              switch (user.role) {
                                UserRole.nursing => 'Enfermería',
                                UserRole.inventory => 'Inventario',
                                UserRole.hospital => 'Hospital',
                              },
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(user.id),
                            Text(
                              '${user.role == UserRole.hospital ? 'Hospital' : 'Sede'}: ${user.hospitalId ?? user.siteId}',
                            ),
                            const SizedBox(height: 24),
                            for (final module in AccessPolicy.modulesFor(user))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: OutlinedButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _perform(() async {
                                          _module = module;
                                          _items = null;
                                          _items = await _session.loadModule(
                                            module,
                                          );
                                        }),
                                  child: Text(moduleNames[module]!),
                                ),
                              ),
                            if (_module != null) ...[
                              const Divider(height: 32),
                              Text(
                                moduleNames[_module]!,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (_items != null && _items!.isEmpty)
                                const Text('Sin registros.'),
                              if (_items != null)
                                for (final item in _items!)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Text(_descripcionRegistro(item)),
                                  ),
                            ],
                            const SizedBox(height: 24),
                            FilledButton(
                              onPressed: _busy
                                  ? null
                                  : () => _perform(() async {
                                      await _session.logout();
                                      _password.clear();
                                    }),
                              child: const Text('Cerrar sesión'),
                            ),
                          ],
                        ],
                      ),
                    ),
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
