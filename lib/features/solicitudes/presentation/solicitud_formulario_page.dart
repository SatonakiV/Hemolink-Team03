import 'package:flutter/material.dart';

import '../../../core/access/access_policy.dart';
import '../../../core/access/auth_session.dart';
import '../data/api_solicitud_repository.dart';
import '../data/solicitud_repository.dart';
import '../domain/solicitud.dart';
import '../domain/validador_solicitud.dart';

class SolicitudFormularioPage extends StatefulWidget {
  const SolicitudFormularioPage({
    super.key,
    required this.sesion,
    required this.repositorio,
  });

  final AuthSession sesion;
  final SolicitudRepository repositorio;

  @override
  State<SolicitudFormularioPage> createState() =>
      _SolicitudFormularioPageState();
}

class _SolicitudFormularioPageState extends State<SolicitudFormularioPage> {
  final _cantidad = TextEditingController();
  final _errores = <String, String>{};
  String? _grupoAbo;
  String? _factorRh;
  String? _prioridad;
  String? _errorGeneral;
  bool _guardando = false;

  bool get _autorizado =>
      AccessPolicy.canCreateRequests(widget.sesion.currentUser);

  @override
  void dispose() {
    _cantidad.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_guardando || !_autorizado) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _errores.clear();
      _errorGeneral = null;
    });

    DatosSolicitud datos;
    try {
      datos = const ValidadorSolicitud().validarEntrada(
        grupoAbo: _grupoAbo,
        factorRh: _factorRh,
        cantidadTexto: _cantidad.text,
        prioridad: _prioridad,
      );
    } on ValidacionSolicitudException catch (error) {
      setState(() {
        _errores.addAll(error.errores);
      });
      return;
    }

    setState(() => _guardando = true);
    try {
      final creada = await widget.repositorio.crear(datos);
      if (!mounted || !_autorizado) return;
      setState(() => _guardando = false);
      Navigator.of(context).pop(creada);
    } on SolicitudApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _errores.addAll(error.errores);
        _errorGeneral = error.mensaje;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorGeneral =
            'No se pudo registrar la solicitud. Revisa la conexión y vuelve a intentar.';
      });
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Widget _selector({
    required String campo,
    required String keyName,
    required String etiqueta,
    required String? valor,
    required Map<String, String> opciones,
    required ValueChanged<String?> cambiar,
  }) => DropdownButtonFormField<String>(
    key: Key(keyName),
    initialValue: valor,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: etiqueta,
      errorText: _errores[campo],
      errorMaxLines: 3,
      border: const OutlineInputBorder(),
    ),
    items: [
      for (final opcion in opciones.entries)
        DropdownMenuItem(value: opcion.key, child: Text(opcion.value)),
    ],
    onChanged: _guardando
        ? null
        : (nuevo) {
            setState(() {
              cambiar(nuevo);
              _errores.remove(campo);
              _errorGeneral = null;
            });
          },
  );

  @override
  Widget build(BuildContext context) => PopScope<Solicitud>(
    canPop: !_guardando,
    child: Scaffold(
      appBar: AppBar(title: const Text('Nueva solicitud')),
      body: !_autorizado
          ? const Center(
              child: Text(
                'Solo el personal de hospital autorizado puede ingresar solicitudes.',
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Ingresar solicitud de sangre',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Indica grupo ABO/Rh, cantidad de unidades y prioridad.',
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
                        const SizedBox(height: 16),
                      ],
                      Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: LayoutBuilder(
                            builder: (context, limites) {
                              final ancho = limites.maxWidth >= 560
                                  ? (limites.maxWidth - 16) / 2
                                  : limites.maxWidth;
                              final campos = [
                                _selector(
                                  campo: 'grupoAbo',
                                  keyName: 'solicitud-grupo-abo',
                                  etiqueta: 'Grupo sanguíneo (ABO)',
                                  valor: _grupoAbo,
                                  opciones: const {
                                    'A': 'A',
                                    'B': 'B',
                                    'AB': 'AB',
                                    'O': 'O',
                                  },
                                  cambiar: (v) => _grupoAbo = v,
                                ),
                                _selector(
                                  campo: 'factorRh',
                                  keyName: 'solicitud-factor-rh',
                                  etiqueta: 'Factor Rh',
                                  valor: _factorRh,
                                  opciones: const {
                                    'positivo': 'Positivo',
                                    'negativo': 'Negativo',
                                  },
                                  cambiar: (v) => _factorRh = v,
                                ),
                                TextField(
                                  key: const Key('solicitud-cantidad'),
                                  controller: _cantidad,
                                  enabled: !_guardando,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.done,
                                  decoration: InputDecoration(
                                    labelText: 'Cantidad de unidades',
                                    hintText: 'Ej: 2',
                                    errorText: _errores['cantidad'],
                                    errorMaxLines: 3,
                                    border: const OutlineInputBorder(),
                                  ),
                                  onChanged: (_) {
                                    if (_errores.containsKey('cantidad') ||
                                        _errorGeneral != null) {
                                      setState(() {
                                        _errores.remove('cantidad');
                                        _errorGeneral = null;
                                      });
                                    }
                                  },
                                  onSubmitted: (_) => _guardar(),
                                ),
                                _selector(
                                  campo: 'prioridad',
                                  keyName: 'solicitud-prioridad',
                                  etiqueta: 'Prioridad',
                                  valor: _prioridad,
                                  opciones: const {
                                    'urgente': 'Urgente',
                                    'normal': 'Normal',
                                  },
                                  cambiar: (v) => _prioridad = v,
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
                                        semanticsLabel: 'Guardando solicitud',
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
                                        child: const Text('Guardar solicitud'),
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
