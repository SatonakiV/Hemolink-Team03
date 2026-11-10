import 'package:flutter/material.dart';
import '../domain/evaluacion_aptitud.dart';

/// Interfaz independiente de evaluación de aptitud.
/// La ficha del donante podrá reutilizarla posteriormente.
class EvaluacionAptitudPage extends StatefulWidget {
  const EvaluacionAptitudPage({
    super.key,
    required this.donanteId,
    required this.responsableId,
    required this.onGuardar,
    this.historialInicial = const [],
  });

  final String donanteId;
  final String responsableId;
  final Future<void> Function(EvaluacionAptitud) onGuardar;
  final List<EvaluacionAptitud> historialInicial;

  @override
  State<EvaluacionAptitudPage> createState() =>
      _EvaluacionAptitudPageState();
}

class _EvaluacionAptitudPageState
    extends State<EvaluacionAptitudPage> {
  ResultadoAptitud _resultado = ResultadoAptitud.apto;

  DateTime? _fechaEvaluacion;
  DateTime? _fechaLimite;

  late final List<EvaluacionAptitud> _historial;

  bool _guardando = false;
  String? _mensaje;
  bool _esError = false;

  @override
  void initState() {
    super.initState();
    _historial = List.of(widget.historialInicial);
    _ordenarHistorial();
  }

  void _ordenarHistorial() {
    _historial.sort((a, b) {
      final comparacion =
          b.fechaEvaluacion.compareTo(a.fechaEvaluacion);

      if (comparacion != 0) return comparacion;
      return b.fechaRegistro.compareTo(a.fechaRegistro);
    });
  }

  String _formatearFecha(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    return '$dia/$mes/${fecha.year}';
  }

  String _nombreResultado(ResultadoAptitud resultado) {
    return switch (resultado) {
      ResultadoAptitud.apto => 'Apto',
      ResultadoAptitud.diferido => 'Diferido',
      ResultadoAptitud.rechazado => 'Rechazado permanentemente',
    };
  }

  Future<void> _seleccionarFecha(bool esEvaluacion) async {
    final hoy = DateUtils.dateOnly(DateTime.now());

    final primeraFecha = esEvaluacion
        ? DateTime(1900)
        : (_fechaEvaluacion ?? DateTime(1900));

    final fechaInicial = esEvaluacion
        ? (_fechaEvaluacion ?? hoy)
        : (_fechaLimite ?? _fechaEvaluacion ?? hoy);

    final seleccionada = await showDatePicker(
      context: context,
      initialDate: fechaInicial,
      firstDate: primeraFecha,
      lastDate: esEvaluacion ? hoy : DateTime(2100),
    );

    if (seleccionada == null || !mounted) return;

    setState(() {
      if (esEvaluacion) {
        _fechaEvaluacion = seleccionada;
        _fechaLimite = null;
      } else {
        _fechaLimite = seleccionada;
      }
      _mensaje = null;
    });
  }

  void _mostrarError(String mensaje) {
    setState(() {
      _mensaje = mensaje;
      _esError = true;
    });
  }

  Future<void> _guardarEvaluacion() async {
    if (_guardando) return;

    if (_fechaEvaluacion == null) {
      _mostrarError('Selecciona la fecha de evaluación.');
      return;
    }

    final requiereFecha =
        _resultado != ResultadoAptitud.rechazado;

    if (requiereFecha && _fechaLimite == null) {
      _mostrarError(
        'Completa la fecha correspondiente al resultado.',
      );
      return;
    }

    if (requiereFecha &&
        _fechaLimite!.isBefore(_fechaEvaluacion!)) {
      _mostrarError(
        'La fecha límite no puede ser anterior a la evaluación.',
      );
      return;
    }

    final ahora = DateTime.now();

    final evaluacion = EvaluacionAptitud(
      id: 'EV${ahora.microsecondsSinceEpoch}',
      donanteId: widget.donanteId,
      responsableId: widget.responsableId,
      resultado: _resultado,
      fechaEvaluacion: _fechaEvaluacion!,
      fechaFinVigencia:
          _resultado == ResultadoAptitud.apto
              ? _fechaLimite
              : null,
      fechaHabilitacion:
          _resultado == ResultadoAptitud.diferido
              ? _fechaLimite
              : null,
      fechaRegistro: ahora,
    );

    setState(() {
      _guardando = true;
      _mensaje = null;
    });

    try {
      // El guardado real se conectará posteriormente.
      await widget.onGuardar(evaluacion);

      if (!mounted) return;

      setState(() {
        _historial.add(evaluacion);
        _ordenarHistorial();
        _fechaEvaluacion = null;
        _fechaLimite = null;
        _esError = false;
        _mensaje = 'Evaluación registrada correctamente.';
      });
    } catch (_) {
      if (!mounted) return;
      _mostrarError(
        'No fue posible guardar la evaluación. Intenta nuevamente.',
      );
    } finally {
      if (mounted) {
        setState(() => _guardando = false);
      }
    }
  }

  String _detalleEvaluacion(EvaluacionAptitud evaluacion) {
    return switch (evaluacion.resultado) {
      ResultadoAptitud.apto =>
        'Vigente hasta: ${evaluacion.fechaFinVigencia == null ? "Sin fecha" : _formatearFecha(evaluacion.fechaFinVigencia!)}',
      ResultadoAptitud.diferido =>
        'Reevaluación desde: ${evaluacion.fechaHabilitacion == null ? "Sin fecha" : _formatearFecha(evaluacion.fechaHabilitacion!)}',
      ResultadoAptitud.rechazado =>
        'Rechazo permanente',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Evaluación de aptitud'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Donante: ${widget.donanteId}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),

              // PRIMERA PARTE: FORMULARIO
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Registrar evaluación',
                        style: Theme.of(context)
                            .textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),

                      DropdownButtonFormField<ResultadoAptitud>(
                        initialValue: _resultado,
                        decoration: const InputDecoration(
                          labelText: 'Resultado de aptitud',
                          border: OutlineInputBorder(),
                        ),
                        items: ResultadoAptitud.values.map((valor) {
                          return DropdownMenuItem(
                            value: valor,
                            child: Text(_nombreResultado(valor)),
                          );
                        }).toList(),
                        onChanged: _guardando
                            ? null
                            : (valor) {
                                if (valor == null) return;
                                setState(() {
                                  _resultado = valor;
                                  _fechaLimite = null;
                                  _mensaje = null;
                                });
                              },
                      ),
                      const SizedBox(height: 16),

                      OutlinedButton.icon(
                        key: const Key('fecha-evaluacion'),
                        onPressed: _guardando
                            ? null
                            : () => _seleccionarFecha(true),
                        icon: const Icon(Icons.calendar_month),
                        label: Text(
                          _fechaEvaluacion == null
                              ? 'Seleccionar fecha de evaluación'
                              : 'Evaluación: ${_formatearFecha(_fechaEvaluacion!)}',
                        ),
                      ),

                      if (_resultado != ResultadoAptitud.rechazado) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          key: const Key('fecha-limite'),
                          onPressed: _guardando
                              ? null
                              : () => _seleccionarFecha(false),
                          icon: const Icon(Icons.event),
                          label: Text(
                            _fechaLimite == null
                                ? (_resultado == ResultadoAptitud.apto
                                    ? 'Seleccionar fin de vigencia'
                                    : 'Seleccionar fecha de reevaluación')
                                : 'Fecha: ${_formatearFecha(_fechaLimite!)}',
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // TERCERA PARTE: MENSAJES Y VALIDACIÓN
                      if (_mensaje != null) ...[
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _mensaje!,
                            style: TextStyle(
                              color: _esError
                                  ? colors.error
                                  : const Color(0xFF216E39),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      FilledButton(
                        onPressed:
                            _guardando ? null : _guardarEvaluacion,
                        child: Text(
                          _guardando
                              ? 'Guardando...'
                              : 'Guardar evaluación',
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // SEGUNDA PARTE: HISTORIAL VISUAL
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Historial de evaluaciones',
                        style: Theme.of(context)
                            .textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      if (_historial.isEmpty)
                        const Text(
                          'Este donante no tiene evaluaciones registradas.',
                        )
                      else
                        for (final evaluacion in _historial)
                          ListTile(
                            key: Key('evaluacion-${evaluacion.id}'),
                            leading: Icon(
                              switch (evaluacion.resultado) {
                                ResultadoAptitud.apto =>
                                  Icons.check_circle,
                                ResultadoAptitud.diferido =>
                                  Icons.schedule,
                                ResultadoAptitud.rechazado =>
                                  Icons.cancel,
                              },
                            ),
                            title: Text(
                              _nombreResultado(evaluacion.resultado),
                            ),
                            subtitle: Text(
                              'Evaluación: ${_formatearFecha(evaluacion.fechaEvaluacion)}\n'
                              '${_detalleEvaluacion(evaluacion)}',
                            ),
                            isThreeLine: true,
                          ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
