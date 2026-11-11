import 'package:flutter/material.dart';

import '../../../core/access/access_policy.dart';
import '../../../core/access/auth_session.dart';
import '../data/api_donante_repository.dart';
import '../data/donante_repository.dart';
import '../domain/donante.dart';
import '../domain/validador_donante.dart';
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
                if (ficha.usuarioModificacionId != null)
                  'Modificado por': ficha.usuarioModificacionId!,
                if (ficha.fechaModificacion != null)
                  'Fecha de modificación': _fecha(ficha.fechaModificacion!.toLocal()),
              };
              return _Contenido(
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        ficha.nombre,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (_autorizado)
                        FilledButton.icon(
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final actualizado = await Navigator.of(context).push<Donante>(
                              MaterialPageRoute(
                                builder: (_) => EdicionDonantePage(
                                  sesion: widget.sesion,
                                  repositorio: widget.repositorio,
                                  donante: ficha,
                                ),
                              ),
                            );
                            if (actualizado != null && mounted) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Antecedentes actualizados correctamente.'),
                                ),
                              );
                              setState(() {
                                _ficha = Future.value(actualizado);
                              });
                            }
                          },
                          icon: const Icon(Icons.edit),
                          label: const Text('Editar antecedentes'),
                        ),
                    ],
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

class EdicionDonantePage extends StatefulWidget {
  const EdicionDonantePage({
    super.key,
    required this.sesion,
    required this.repositorio,
    required this.donante,
  });

  final AuthSession sesion;
  final DonanteRepository repositorio;
  final Donante donante;

  @override
  State<EdicionDonantePage> createState() => _EdicionDonantePageState();
}

class _EdicionDonantePageState extends State<EdicionDonantePage> {
  late final TextEditingController _rut;
  late final TextEditingController _nombre;
  late final TextEditingController _fechaNacimiento;
  late final TextEditingController _peso;
  late final TextEditingController _telefono;
  late String _grupoAbo;
  late String _factorRh;
  late DateTime? _nacimientoSeleccionado;

  final Map<String, String> _errores = {};
  String? _errorGeneral;
  bool _guardando = false;

  bool get _autorizado =>
      AccessPolicy.canManageDonors(widget.sesion.currentUser);

  @override
  void initState() {
    super.initState();
    final d = widget.donante;
    _rut = TextEditingController(text: d.rut);
    _nombre = TextEditingController(text: d.nombre);
    _nacimientoSeleccionado = d.fechaNacimiento;
    _fechaNacimiento = TextEditingController(text: _fecha(d.fechaNacimiento));
    _peso = TextEditingController(
      text: d.pesoKg.toStringAsFixed(d.pesoKg % 1 == 0 ? 0 : 1),
    );
    _telefono = TextEditingController(text: d.telefono);
    _grupoAbo = d.grupoAbo;
    _factorRh = d.factorRh;
  }

  @override
  void dispose() {
    _rut.dispose();
    _nombre.dispose();
    _fechaNacimiento.dispose();
    _peso.dispose();
    _telefono.dispose();
    super.dispose();
  }

  Future<void> _seleccionarFecha() async {
    final ahora = DateTime.now();
    final inicial = _nacimientoSeleccionado ?? DateTime(1990, 1, 1);
    final seleccionada = await showDatePicker(
      context: context,
      initialDate: inicial.isAfter(ahora) ? ahora : inicial,
      firstDate: DateTime(1900),
      lastDate: ahora,
    );
    if (seleccionada != null && mounted) {
      setState(() {
        _nacimientoSeleccionado = seleccionada;
        _fechaNacimiento.text = _fecha(seleccionada);
        _errores.remove('fechaNacimiento');
      });
    }
  }

  Future<void> _guardar() async {
    if (!_autorizado) return;

    setState(() {
      _errores.clear();
      _errorGeneral = null;
    });

    final rutTexto = _rut.text.trim();
    final nombreTexto = _nombre.text.trim();
    final pesoTexto = _peso.text.trim();
    final pesoValor = double.tryParse(pesoTexto.replaceAll(',', '.'));
    final telefonoTexto = _telefono.text.trim();

    final datosAValidar = DatosDonante(
      rut: rutTexto,
      nombre: nombreTexto,
      fechaNacimiento: _nacimientoSeleccionado,
      pesoKg: pesoValor,
      grupoAbo: _grupoAbo,
      factorRh: _factorRh,
      telefono: telefonoTexto,
    );

    const validador = ValidadorDonante();
    try {
      validador.validarDatos(datosAValidar);
    } on ValidacionDonanteException catch (e) {
      setState(() {
        _errores.addAll(e.errores);
      });
      return;
    }

    setState(() => _guardando = true);
    try {
      final actualizado = await widget.repositorio.actualizar(
        widget.donante.id,
        datosAValidar,
      );
      if (!mounted) return;
      Navigator.of(context).pop(actualizado);
    } on DonanteApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.errores.isNotEmpty) {
          _errores.addAll(e.errores);
        } else {
          _errorGeneral = e.mensaje;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorGeneral = 'No se pudo guardar la corrección. Revisa los datos o vuelve a intentar.';
      });
    } finally {
      if (mounted) {
        setState(() => _guardando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_autorizado) {
      return Scaffold(
        appBar: AppBar(title: const Text('Editar donante')),
        body: const Center(
          child: Text('Tu sesión no permite consultar donantes.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Editar donante')),
      body: _Contenido(
        children: [
          Text(
            'Editar antecedentes del donante',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Corrige los antecedentes del donante. Se mantendrá el historial y la unicidad de RUT.',
          ),
          const SizedBox(height: 24),
          if (_errorGeneral != null) ...[
            _Fallo(
              mensaje: _errorGeneral!,
              reintentar: _guardar,
            ),
            const SizedBox(height: 16),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('edicion-rut'),
                    controller: _rut,
                    decoration: InputDecoration(
                      labelText: 'RUT',
                      hintText: '12.345.678-5',
                      errorText: _errores['rut'],
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (_errores.containsKey('rut')) {
                        setState(() => _errores.remove('rut'));
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('edicion-nombre'),
                    controller: _nombre,
                    decoration: InputDecoration(
                      labelText: 'Nombre completo',
                      errorText: _errores['nombre'],
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (_errores.containsKey('nombre')) {
                        setState(() => _errores.remove('nombre'));
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('edicion-fecha-nacimiento'),
                    controller: _fechaNacimiento,
                    readOnly: true,
                    onTap: _seleccionarFecha,
                    decoration: InputDecoration(
                      labelText: 'Fecha de nacimiento',
                      errorText: _errores['fechaNacimiento'],
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.calendar_today),
                        onPressed: _seleccionarFecha,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('edicion-peso'),
                    controller: _peso,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Peso (kg)',
                      errorText: _errores['pesoKg'],
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (_errores.containsKey('pesoKg')) {
                        setState(() => _errores.remove('pesoKg'));
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: const Key('edicion-grupo-abo'),
                    initialValue: _grupoAbo,
                    decoration: InputDecoration(
                      labelText: 'Grupo sanguíneo (ABO)',
                      errorText: _errores['grupoAbo'],
                      border: const OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'A', child: Text('A')),
                      DropdownMenuItem(value: 'B', child: Text('B')),
                      DropdownMenuItem(value: 'AB', child: Text('AB')),
                      DropdownMenuItem(value: 'O', child: Text('O')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _grupoAbo = val;
                          _errores.remove('grupoAbo');
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: const Key('edicion-factor-rh'),
                    initialValue: _factorRh,
                    decoration: InputDecoration(
                      labelText: 'Factor Rh',
                      errorText: _errores['factorRh'],
                      border: const OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'positivo', child: Text('Positivo')),
                      DropdownMenuItem(value: 'negativo', child: Text('Negativo')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _factorRh = val;
                          _errores.remove('factorRh');
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('edicion-telefono'),
                    controller: _telefono,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Teléfono',
                      errorText: _errores['telefono'],
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (_errores.containsKey('telefono')) {
                        setState(() => _errores.remove('telefono'));
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  if (_guardando)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: LinearProgressIndicator(
                        semanticsLabel: 'Guardando antecedentes',
                      ),
                    ),
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    alignment: WrapAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: _guardando
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: _guardando ? null : _guardar,
                        child: const Text('Guardar cambios'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
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

