import 'package:flutter/material.dart';

import '../../../core/access/access_policy.dart';
import '../../../core/access/auth_session.dart';
import '../data/api_donante_repository.dart';
import '../data/donante_repository.dart';
import '../domain/donante.dart';
import '../domain/validador_rut.dart';

String _mensaje(Object error) => error is DonanteApiException
    ? error.mensaje
    : 'No se pudo consultar al servidor. Vuelve a intentar.';

String _fecha(DateTime fecha) =>
    '${fecha.day.toString().padLeft(2, '0')}/'
    '${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';

class DonantesPage extends StatefulWidget {
  const DonantesPage({
    super.key,
    required this.sesion,
    required this.repositorio,
  });
  final AuthSession sesion;
  final DonanteRepository repositorio;

  @override
  State<DonantesPage> createState() => _DonantesPageState();
}

class _DonantesPageState extends State<DonantesPage> {
  final _texto = TextEditingController();
  String _campo = 'nombre';
  String? _errorCampo;
  String? _error;
  List<Donante> _items = [];
  bool _cargando = false;
  bool _filtrado = false;
  int _solicitud = 0;

  bool get _autorizado =>
      AccessPolicy.canManageDonors(widget.sesion.currentUser);

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  Future<void> _buscar() async {
    final solicitud = ++_solicitud;
    final texto = _texto.text.trim();
    setState(() {
      _items = [];
      _error = null;
      _errorCampo = null;
      _cargando = false;
    });
    if (!_autorizado) return;
    if (_campo == 'rut' && texto.isNotEmpty && !ValidadorRut.esValido(texto)) {
      setState(() => _errorCampo = 'Ingresa un RUT válido para buscar.');
      return;
    }
    setState(() {
      _cargando = true;
      _filtrado = texto.isNotEmpty;
    });
    try {
      final items = await widget.repositorio.buscar(
        rut: _campo == 'rut' && texto.isNotEmpty ? texto : null,
        nombre: _campo == 'nombre' && texto.isNotEmpty ? texto : null,
      );
      if (!mounted || solicitud != _solicitud) return;
      setState(() => _items = items);
    } catch (error) {
      if (!mounted || solicitud != _solicitud) return;
      setState(() => _error = _mensaje(error));
    } finally {
      if (mounted && solicitud == _solicitud) {
        setState(() => _cargando = false);
      }
    }
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Donantes')),
    body: !_autorizado
        ? const Center(child: Text('Tu sesión no permite consultar donantes.'))
        : _Contenido(
            children: [
              Text(
                'Consultar donantes',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Busca por nombre o RUT y abre la ficha para consultar sus antecedentes.',
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 160,
                    child: DropdownButtonFormField<String>(
                      initialValue: _campo,
                      decoration: const InputDecoration(
                        labelText: 'Buscar por',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'nombre',
                          child: Text('Nombre'),
                        ),
                        DropdownMenuItem(value: 'rut', child: Text('RUT')),
                      ],
                      onChanged: (valor) {
                        if (valor == null) return;
                        setState(() => _campo = valor);
                        _buscar();
                      },
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: TextField(
                      key: const Key('busqueda-donante'),
                      controller: _texto,
                      decoration: InputDecoration(
                        labelText: _campo == 'rut'
                            ? 'RUT del donante'
                            : 'Nombre del donante',
                        hintText: _campo == 'rut'
                            ? '12.345.678-5'
                            : 'Nombre o apellido',
                        errorText: _errorCampo,
                        border: const OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _buscar(),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _buscar,
                    icon: const Icon(Icons.search),
                    label: const Text('Buscar'),
                  ),
                  TextButton(
                    onPressed: () {
                      _texto.clear();
                      _buscar();
                    },
                    child: const Text('Ver todos'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (_cargando)
                const LinearProgressIndicator(
                  semanticsLabel: 'Buscando donantes',
                ),
              if (_error != null) _Fallo(mensaje: _error!, reintentar: _buscar),
              if (!_cargando && _error == null && _errorCampo == null) ...[
                if (_items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      _filtrado
                          ? 'No se encontraron donantes.'
                          : 'No hay donantes registrados en esta sede.',
                    ),
                  )
                else ...[
                  Text(
                    '${_items.length} ${_items.length == 1 ? 'donante' : 'donantes'}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 12),
                  for (final item in _items)
                    Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        title: Text(item.nombre),
                        subtitle: Text(
                          'RUT: ${item.rut}\nGrupo: ${item.grupoAbo} ${item.factorRh}',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          if (!_autorizado) {
                            setState(() => _items = []);
                            return;
                          }
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => DonanteFichaPage(
                                sesion: widget.sesion,
                                repositorio: widget.repositorio,
                                donanteId: item.id,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ],
            ],
          ),
  );
}

class DonanteFichaPage extends StatefulWidget {
  const DonanteFichaPage({
    super.key,
    required this.sesion,
    required this.repositorio,
    required this.donanteId,
  });
  final AuthSession sesion;
  final DonanteRepository repositorio;
  final String donanteId;

  @override
  State<DonanteFichaPage> createState() => _DonanteFichaPageState();
}

class _DonanteFichaPageState extends State<DonanteFichaPage> {
  Future<Donante?>? _ficha;
  bool get _autorizado =>
      AccessPolicy.canManageDonors(widget.sesion.currentUser);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    setState(() {
      _ficha = _autorizado
          ? widget.repositorio.buscarPorId(widget.donanteId)
          : null;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ficha del donante')),
    body: !_autorizado
        ? const Center(child: Text('Tu sesión no permite consultar donantes.'))
        : FutureBuilder<Donante?>(
            future: _ficha,
            builder: (context, estado) {
              if (estado.connectionState != ConnectionState.done) {
                return const Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Cargando ficha',
                  ),
                );
              }
              if (estado.hasError) {
                return _Contenido(
                  children: [
                    _Fallo(
                      mensaje: _mensaje(estado.error!),
                      reintentar: _cargar,
                    ),
                  ],
                );
              }
              final ficha = estado.data;
              if (ficha == null) {
                return const _Contenido(
                  children: [Text('Donante no encontrado en esta sede.')],
                );
              }
              final campos = {
                'RUT': ficha.rut,
                'Fecha de nacimiento': _fecha(ficha.fechaNacimiento),
                'Peso':
                    '${ficha.pesoKg.toStringAsFixed(ficha.pesoKg % 1 == 0 ? 0 : 1)} kg',
                'Grupo sanguíneo': '${ficha.grupoAbo} ${ficha.factorRh}',
                'Teléfono': ficha.telefono,
                'Identificador': ficha.id,
                'Registrado por': ficha.usuarioRegistroId,
                'Fecha de registro': _fecha(ficha.fechaRegistro.toLocal()),
              };
              return _Contenido(
                children: [
                  Text(
                    ficha.nombre,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final campo in campos.entries)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    campo.key,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge,
                                  ),
                                  const SizedBox(height: 4),
                                  SelectableText(
                                    campo.value,
                                    semanticsLabel: '${campo.key}: ${campo.value}',
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
  );
}

class _Contenido extends StatelessWidget {
  const _Contenido({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}

class _Fallo extends StatelessWidget {
  const _Fallo({required this.mensaje, required this.reintentar});
  final String mensaje;
  final VoidCallback reintentar;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          mensaje,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: reintentar, child: const Text('Reintentar')),
      ],
    ),
  );
}
