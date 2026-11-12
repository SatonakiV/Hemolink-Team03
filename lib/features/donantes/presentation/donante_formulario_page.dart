import 'package:flutter/material.dart';

import '../../../core/access/access_policy.dart';
import '../../../core/access/auth_session.dart';
import '../data/api_donante_repository.dart';
import '../data/donante_repository.dart';
import '../domain/donante.dart';
import '../domain/validador_donante.dart';

class AltaDonantePage extends StatelessWidget {
  const AltaDonantePage({
    super.key,
    required this.sesion,
    required this.repositorio,
  });
  final AuthSession sesion;
  final DonanteRepository repositorio;

  @override
  Widget build(BuildContext context) =>
      _FormularioDonantePage(sesion: sesion, repositorio: repositorio);
}

class EdicionDonantePage extends StatelessWidget {
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
  Widget build(BuildContext context) => _FormularioDonantePage(
    sesion: sesion,
    repositorio: repositorio,
    donante: donante,
  );
}

class _FormularioDonantePage extends StatefulWidget {
  const _FormularioDonantePage({
    required this.sesion,
    required this.repositorio,
    this.donante,
  });
  final AuthSession sesion;
  final DonanteRepository repositorio;
  final Donante? donante;
  @override
  State<_FormularioDonantePage> createState() => _FormularioDonantePageState();
}

class _FormularioDonantePageState extends State<_FormularioDonantePage> {
  late final Map<String, TextEditingController> _textos;
  final _anclas = {
    for (final campo in [
      'rut',
      'nombre',
      'fechaNacimiento',
      'pesoKg',
      'grupoAbo',
      'factorRh',
      'telefono',
    ])
      campo: GlobalKey(),
  };
  final _errores = <String, String>{};
  String? _grupoAbo;
  String? _factorRh;
  String? _errorGeneral;
  bool _guardando = false;
  bool get _edicion => widget.donante != null;
  bool get _autorizado =>
      AccessPolicy.canManageDonors(widget.sesion.currentUser);
  String get _prefijo => _edicion ? 'edicion' : 'alta';
  String get _titulo => _edicion ? 'Editar donante' : 'Registrar donante';

  static String _fecha(DateTime fecha) =>
      '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year.toString().padLeft(4, '0')}';

  static DateTime? _leerFecha(String texto) {
    final partes = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$')
        .firstMatch(texto.trim());
    if (partes == null) return null;
    final dia = int.parse(partes[1]!);
    final mes = int.parse(partes[2]!);
    final anio = int.parse(partes[3]!);
    if (anio < 1) return null;
    final fecha = DateTime(anio, mes, dia);
    return fecha.day == dia && fecha.month == mes && fecha.year == anio
        ? fecha
        : null;
  }

  @override
  void initState() {
    super.initState();
    final d = widget.donante;
    _textos = {
      'rut': TextEditingController(text: d?.rut),
      'nombre': TextEditingController(text: d?.nombre),
      'fechaNacimiento': TextEditingController(
        text: d == null ? '' : _fecha(d.fechaNacimiento),
      ),
      'pesoKg': TextEditingController(text: d?.pesoKg.toString()),
      'telefono': TextEditingController(text: d?.telefono),
    };
    _grupoAbo = d?.grupoAbo;
    _factorRh = d?.factorRh;
  }

  @override
  void dispose() {
    for (final controller in _textos.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _seleccionarFecha() async {
    if (_guardando) return;
    final ahora = DateTime.now();
    final anterior = _leerFecha(_textos['fechaNacimiento']!.text);
    final fecha = await showDatePicker(
      context: context,
      initialDate: anterior != null && !anterior.isAfter(ahora)
          ? anterior
          : DateTime(1990),
      firstDate: DateTime(1),
      lastDate: ahora,
      helpText: 'Fecha de nacimiento',
      cancelText: 'Cancelar',
      confirmText: 'Seleccionar',
    );
    if (!mounted || fecha == null || _guardando) return;
    setState(() {
      _textos['fechaNacimiento']!.text = _fecha(fecha);
      _errores.remove('fechaNacimiento');
      _errorGeneral = null;
    });
  }

  void _mostrarErrores() {
    final contexto = _anclas[_errores.keys.first]?.currentContext;
    if (contexto != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (contexto.mounted) {
          Scrollable.ensureVisible(
            contexto,
            duration: const Duration(milliseconds: 200),
            alignment: 0.1,
          );
        }
      });
    }
  }

  Future<void> _guardar() async {
    if (_guardando || !_autorizado) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _errores.clear();
      _errorGeneral = null;
    });
    final textoFecha = _textos['fechaNacimiento']!.text;
    final nacimiento = _leerFecha(textoFecha);
    DatosDonante datos;
    try {
      datos = const ValidadorDonante().validarDatos(
        DatosDonante(
          rut: _textos['rut']!.text,
          nombre: _textos['nombre']!.text,
          fechaNacimiento: nacimiento,
          pesoKg: double.tryParse(
            _textos['pesoKg']!.text.trim().replaceAll(',', '.'),
          ),
          grupoAbo: _grupoAbo,
          factorRh: _factorRh,
          telefono: _textos['telefono']!.text,
        ),
      );
    } on ValidacionDonanteException catch (error) {
      setState(() {
        _errores.addAll(error.errores);
        if (textoFecha.trim().isNotEmpty && nacimiento == null) {
          _errores['fechaNacimiento'] =
              'Ingresa una fecha válida con formato DD/MM/AAAA.';
        }
      });
      _mostrarErrores();
      return;
    }
    setState(() => _guardando = true);
    try {
      final original = widget.donante;
      final guardado = original == null
          ? await widget.repositorio.guardar(datos)
          : await widget.repositorio.actualizar(original.id, datos);
      if (!mounted || !_autorizado) return;
      setState(() => _guardando = false);
      Navigator.of(context).pop(guardado);
    } on DonanteApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _errores.addAll(error.errores);
        _errorGeneral = error.mensaje;
      });
      if (_errores.isNotEmpty) _mostrarErrores();
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _errorGeneral =
            'No se pudo guardar. Revisa la conexión y vuelve a intentar.',
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  InputDecoration _decoracion(
    String campo,
    String etiqueta, {
    String? pista,
    Widget? sufijo,
  }) => InputDecoration(
    labelText: etiqueta,
    hintText: pista,
    errorText: _errores[campo],
    errorMaxLines: 3,
    border: const OutlineInputBorder(),
    suffixIcon: sufijo,
  );

  Widget _texto(
    String campo,
    String clave,
    String etiqueta, {
    TextInputType? tipo,
    String? pista,
    Widget? sufijo,
  }) => KeyedSubtree(
    key: _anclas[campo],
    child: TextField(
      key: Key('$_prefijo-$clave'),
      controller: _textos[campo],
      enabled: !_guardando,
      keyboardType: tipo,
      textInputAction: campo == 'telefono'
          ? TextInputAction.done
          : TextInputAction.next,
      decoration: _decoracion(campo, etiqueta, pista: pista, sufijo: sufijo),
      onChanged: (_) {
        if (_errores.containsKey(campo) || _errorGeneral != null) {
          setState(() {
            _errores.remove(campo);
            _errorGeneral = null;
          });
        }
      },
      onSubmitted: campo == 'telefono' ? (_) => _guardar() : null,
    ),
  );

  Widget _eleccion(
    String campo,
    String clave,
    String etiqueta,
    String? valor,
    Map<String, String> opciones,
    ValueChanged<String?> cambiar,
  ) => KeyedSubtree(
    key: _anclas[campo],
    child: DropdownButtonFormField<String>(
      key: Key('$_prefijo-$clave'),
      initialValue: valor,
      isExpanded: true,
      decoration: _decoracion(campo, etiqueta),
      items: [
        for (final opcion in opciones.entries)
          DropdownMenuItem(value: opcion.key, child: Text(opcion.value)),
      ],
      onChanged: _guardando
          ? null
          : (valor) {
              setState(() {
                cambiar(valor);
                _errores.remove(campo);
                _errorGeneral = null;
              });
            },
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope<Donante>(
    canPop: !_guardando,
    child: Scaffold(
      appBar: AppBar(title: Text(_titulo)),
      body: !_autorizado
          ? const Center(
              child: Text('Tu sesión no permite gestionar donantes.'),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _edicion
                            ? 'Editar antecedentes del donante'
                            : 'Datos del nuevo donante',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _edicion
                            ? 'Actualiza sus antecedentes conservando el historial.'
                            : 'Completa todos los campos para registrar al donante.',
                      ),
                      const SizedBox(height: 24),
                      if (_errorGeneral != null) ...[
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _errorGeneral!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                        if (_errores.isEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton(
                              onPressed: _guardando ? null : _guardar,
                              child: const Text('Reintentar'),
                            ),
                          ),
                        const SizedBox(height: 16),
                      ],
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: LayoutBuilder(
                            builder: (context, limites) {
                              final ancho = limites.maxWidth >= 600
                                  ? (limites.maxWidth - 16) / 2
                                  : limites.maxWidth;
                              final campos = [
                                _texto(
                                  'rut',
                                  'rut',
                                  'RUT',
                                  pista: '12.345.678-5',
                                ),
                                _texto('nombre', 'nombre', 'Nombre completo'),
                                _texto(
                                  'fechaNacimiento',
                                  'fecha-nacimiento',
                                  'Fecha de nacimiento',
                                  tipo: TextInputType.datetime,
                                  pista: 'DD/MM/AAAA',
                                  sufijo: IconButton(
                                    tooltip: 'Elegir fecha de nacimiento',
                                    onPressed: _guardando
                                        ? null
                                        : _seleccionarFecha,
                                    icon: const Icon(Icons.calendar_today),
                                  ),
                                ),
                                _texto(
                                  'pesoKg',
                                  'peso',
                                  'Peso (kg)',
                                  tipo: const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                ),
                                _eleccion(
                                  'grupoAbo',
                                  'grupo-abo',
                                  'Grupo sanguíneo (ABO)',
                                  _grupoAbo,
                                  const {
                                    'A': 'A',
                                    'B': 'B',
                                    'AB': 'AB',
                                    'O': 'O',
                                  },
                                  (v) => _grupoAbo = v,
                                ),
                                _eleccion(
                                  'factorRh',
                                  'factor-rh',
                                  'Factor Rh',
                                  _factorRh,
                                  const {
                                    'positivo': 'Positivo',
                                    'negativo': 'Negativo',
                                  },
                                  (v) => _factorRh = v,
                                ),
                                _texto(
                                  'telefono',
                                  'telefono',
                                  'Teléfono',
                                  tipo: TextInputType.phone,
                                ),
                              ];
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Wrap(
                                    spacing: 16,
                                    runSpacing: 20,
                                    children: [
                                      for (final campo in campos)
                                        SizedBox(width: ancho, child: campo),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                  if (_guardando)
                                    const Padding(
                                      padding: EdgeInsets.only(bottom: 16),
                                      child: LinearProgressIndicator(
                                        semanticsLabel: 'Guardando donante',
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
                                        child: Text(
                                          _edicion
                                              ? 'Guardar cambios'
                                              : 'Guardar donante',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
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
