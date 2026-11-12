import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../core/access/access_policy.dart';
import '../../../core/access/auth_session.dart';
import '../../aptitud/data/api_evaluacion_repository.dart';
import '../../aptitud/presentation/evaluacion_aptitud_page.dart';
import '../data/api_donante_repository.dart';
import '../data/donante_repository.dart';
import '../domain/donante.dart';
import '../domain/validador_rut.dart';
import 'donante_formulario_page.dart';

export 'donante_formulario_page.dart'
    show AltaDonantePage, EdicionDonantePage;

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

    if (_campo == 'rut' &&
        texto.isNotEmpty &&
        !ValidadorRut.esValido(texto)) {
      setState(() {
        _errorCampo = 'Ingresa un RUT válido para buscar.';
      });
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

  Future<void> _registrar() async {
    if (!_autorizado) return;
    final creado = await Navigator.of(context).push<Donante>(
      MaterialPageRoute(
        builder: (_) => AltaDonantePage(
          sesion: widget.sesion,
          repositorio: widget.repositorio,
        ),
      ),
    );
    if (!mounted || creado == null || !_autorizado) return;
    _texto.clear();
    _buscar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Donante registrado correctamente.'),
      ),
    );
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DonanteFichaPage(
          sesion: widget.sesion,
          repositorio: widget.repositorio,
          donanteId: creado.id,
          donanteGuardado: creado,
        ),
      ),
    );
    if (mounted) _buscar();
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Donantes'),
        ),
        body: !_autorizado
            ? const Center(
                child: Text(
                  'Tu sesión no permite consultar donantes.',
                ),
              )
            : _Contenido(
                children: [
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Consultar donantes',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall,
                      ),
                      FilledButton.icon(
                        onPressed: _registrar,
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('Registrar donante'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Busca por nombre o RUT y abre la ficha '
                    'para consultar sus antecedentes.',
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
                            DropdownMenuItem(
                              value: 'rut',
                              child: Text('RUT'),
                            ),
                          ],
                          onChanged: (valor) {
                            if (valor == null) return;

                            setState(() => _campo = valor);
                            _buscar();
                          },
                        ),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 440,
                        ),
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
                  if (_error != null)
                    _Fallo(
                      mensaje: _error!,
                      reintentar: _buscar,
                    ),
                  if (!_cargando &&
                      _error == null &&
                      _errorCampo == null) ...[
                    if (_items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 32,
                        ),
                        child: Text(
                          _filtrado
                              ? 'No se encontraron donantes.'
                              : 'No hay donantes registrados en esta sede.',
                        ),
                      )
                    else ...[
                      Text(
                        '${_items.length} '
                        '${_items.length == 1 ? 'donante' : 'donantes'}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 12),
                      for (final item in _items)
                        Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            title: Text(item.nombre),
                            subtitle: Text(
                              'RUT: ${item.rut}\n'
                              'Grupo: ${item.grupoAbo} ${item.factorRh}',
                            ),
                            isThreeLine: true,
                            trailing: const Icon(
                              Icons.chevron_right,
                            ),
                            onTap: () async {
                              if (!_autorizado) {
                                setState(() => _items = []);
                                return;
                              }

                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => DonanteFichaPage(
                                    sesion: widget.sesion,
                                    repositorio: widget.repositorio,
                                    donanteId: item.id,
                                  ),
                                ),
                              );

                              if (mounted) _buscar();
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
    this.donanteGuardado,
  });
  final AuthSession sesion;
  final DonanteRepository repositorio;
  final String donanteId;
  final Donante? donanteGuardado;

  @override
  State<DonanteFichaPage> createState() =>
      _DonanteFichaPageState();
}

class _DonanteFichaPageState extends State<DonanteFichaPage> {
  late final http.Client _clienteEvaluaciones;

  late final ApiEvaluacionRepository _repositorioEvaluaciones;

  Future<Donante?>? _ficha;
  bool get _autorizado =>
      AccessPolicy.canManageDonors(widget.sesion.currentUser);

  @override
  void initState() {
    super.initState();

    _clienteEvaluaciones = http.Client();

    _repositorioEvaluaciones = ApiEvaluacionRepository(
      cliente: _clienteEvaluaciones,
      obtenerToken: () async => widget.sesion.accessToken,
    );

    if (_autorizado && widget.donanteGuardado != null) {
      _ficha = Future.value(widget.donanteGuardado);
    } else {
      _cargar();
    }
  }

  void _cargar() {
    setState(() {
      _ficha = _autorizado
          ? widget.repositorio.buscarPorId(widget.donanteId)
          : null;
    });
  }

  Future<void> _abrirEvaluaciones(Donante ficha) async {
    final usuario = widget.sesion.currentUser;

    if (!_autorizado || usuario == null) return;

    try {
      final historial =
          await _repositorioEvaluaciones.buscarHistorial(
        ficha.id,
      );

      if (!mounted) return;

      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => EvaluacionAptitudPage(
            donanteId: ficha.id,
            responsableId: usuario.id,
            historialInicial: historial,
            onGuardar: _repositorioEvaluaciones.guardar,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudieron cargar las evaluaciones: $error',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _clienteEvaluaciones.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Ficha del donante'),
        ),
        body: !_autorizado
            ? const Center(
                child: Text(
                  'Tu sesión no permite consultar donantes.',
                ),
              )
            : FutureBuilder<Donante?>(
                future: _ficha,
                builder: (context, estado) {
                  if (estado.connectionState !=
                      ConnectionState.done) {
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
                      children: [
                        Text(
                          'Donante no encontrado en esta sede.',
                        ),
                      ],
                    );
                  }

                  final campos = {
                    'RUT': ficha.rut,
                    'Fecha de nacimiento':
                        _fecha(ficha.fechaNacimiento),
                    'Peso':
                        '${ficha.pesoKg.toStringAsFixed(ficha.pesoKg % 1 == 0 ? 0 : 1)} kg',
                    'Grupo sanguíneo':
                        '${ficha.grupoAbo} ${ficha.factorRh}',
                    'Teléfono': ficha.telefono,
                    'Identificador': ficha.id,
                    'Registrado por': ficha.usuarioRegistroId,
                    'Fecha de registro':
                        _fecha(ficha.fechaRegistro.toLocal()),
                    if (ficha.usuarioModificacionId != null)
                      'Modificado por':
                          ficha.usuarioModificacionId!,
                    if (ficha.fechaModificacion != null)
                      'Fecha de modificación': _fecha(
                        ficha.fechaModificacion!.toLocal(),
                      ),
                  };

                  return _Contenido(
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment:
                            WrapCrossAlignment.center,
                        children: [
                          Text(
                            ficha.nombre,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall,
                          ),
                          if (_autorizado)
                            OutlinedButton.icon(
                              key: const Key('abrir-evaluaciones'),
                              onPressed: () =>
                                  _abrirEvaluaciones(ficha),
                              icon: const Icon(
                                Icons.fact_check_outlined,
                              ),
                              label: const Text(
                                'Evaluaciones de aptitud',
                              ),
                            ),
                          if (_autorizado)
                            FilledButton.icon(
                              onPressed: () async {
                                final messenger =
                                    ScaffoldMessenger.of(context);

                                final actualizado =
                                    await Navigator.of(context)
                                        .push<Donante>(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        EdicionDonantePage(
                                      sesion: widget.sesion,
                                      repositorio:
                                          widget.repositorio,
                                      donante: ficha,
                                    ),
                                  ),
                                );

                                if (actualizado != null &&
                                    mounted) {
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Antecedentes actualizados '
                                        'correctamente.',
                                      ),
                                    ),
                                  );

                                  setState(() {
                                    _ficha =
                                        Future.value(actualizado);
                                  });
                                }
                              },
                              icon: const Icon(Icons.edit),
                              label: const Text(
                                'Editar antecedentes',
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            children: [
                              for (final campo in campos.entries)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(
                                    bottom: 20,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                        semanticsLabel:
                                            '${campo.key}: ${campo.value}',
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
  const _Fallo({
    required this.mensaje,
    required this.reintentar,
  });

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
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: reintentar,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
}