import 'package:flutter/material.dart';

import '../../../core/access/auth_session.dart';
import '../../aptitud/data/evaluacion_repository.dart';
import '../../aptitud/domain/evaluacion_aptitud.dart';
import '../../donantes/data/donante_repository.dart';
import '../../muestras/data/muestra_repository.dart';
import '../data/donacion_repository.dart';
import '../domain/registro_donaciones.dart';
import 'donacion_detalle_page.dart';
import 'formulario_donacion_controller.dart';

String _fecha(DateTime fecha) =>
    '${fecha.day.toString().padLeft(2, '0')}/'
    '${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';

/// Formulario de registro de una donación (T03.3). La lógica vive en
/// [FormularioDonacionController]; este widget solo la presenta.
class DonacionFormularioPage extends StatefulWidget {
  const DonacionFormularioPage({
    super.key,
    required this.sesion,
    required this.donantes,
    required this.evaluaciones,
    required this.donaciones,
    required this.muestras,
    this.reloj,
  });

  final AuthSession sesion;
  final DonanteRepository donantes;
  final EvaluacionRepository evaluaciones;
  final DonacionRepository donaciones;
  final MuestraRepository muestras;
  final DateTime Function()? reloj;

  @override
  State<DonacionFormularioPage> createState() => _DonacionFormularioPageState();
}

class _DonacionFormularioPageState extends State<DonacionFormularioPage> {
  late final _formulario = FormularioDonacionController(
    usuario: widget.sesion.currentUser,
    donantes: widget.donantes,
    evaluaciones: widget.evaluaciones,
    registro: RegistroDonaciones(
      repositorio: widget.donaciones,
      reloj: widget.reloj,
    ),
    reloj: widget.reloj,
  );
  final _volumen = TextEditingController();
  final _codigo = TextEditingController();

  @override
  void initState() {
    super.initState();
    _formulario.cargarDonantes();
  }

  @override
  void dispose() {
    _formulario.dispose();
    _volumen.dispose();
    _codigo.dispose();
    super.dispose();
  }

  void _agregarUnidad() {
    if (_formulario.agregarUnidad(_codigo.text)) _codigo.clear();
  }

  Future<void> _elegirFecha() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _formulario.fechaExtraccion,
      firstDate: DateTime(2000),
      lastDate: _formulario.hoy,
      helpText: 'Fecha de extracción',
      cancelText: 'Cancelar',
    );
    if (elegida != null) _formulario.cambiarFecha(elegida);
  }

  Future<void> _confirmar() async {
    final donacion = await _formulario.confirmar();
    if (donacion == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Donación registrada correctamente.')),
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => DonacionDetallePage(
          sesion: widget.sesion,
          donacion: donacion,
          muestraRepository: widget.muestras,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar donación')),
      body: ListenableBuilder(
        listenable: _formulario,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _contenido(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _contenido(BuildContext context) {
    final f = _formulario;
    final colorError = Theme.of(context).colorScheme.error;
    final bloqueado = f.edicionBloqueada || !f.autorizado;
    return [
      if (!f.autorizado)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'Tu perfil no puede registrar donaciones.',
            style: TextStyle(color: colorError),
          ),
        ),
      _dato('Sede', f.sede, const Key('donacion-sede')),
      const SizedBox(height: 16),
      if (f.cargandoDonantes) const LinearProgressIndicator(),
      DropdownButtonFormField<String>(
        key: const Key('donacion-donante'),
        initialValue: f.donante?.id,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Donante',
          border: const OutlineInputBorder(),
          errorText: f.errores['donanteId'],
        ),
        items: [
          for (final d in f.listaDonantes)
            DropdownMenuItem(
              value: d.id,
              child: Text(
                '${d.nombre} · ${d.rut} · '
                '${d.grupoAbo}${d.factorRh == 'positivo' ? '+' : '-'}',
              ),
            ),
        ],
        onChanged: bloqueado ? null : f.seleccionarDonante,
      ),
      const SizedBox(height: 12),
      _aptitud(context),
      if (f.errores['evaluacionId'] != null)
        Text(f.errores['evaluacionId']!, style: TextStyle(color: colorError)),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: _dato(
              'Fecha de extracción',
              _fecha(f.fechaExtraccion),
              const Key('donacion-fecha'),
              error: f.errores['fechaExtraccion'],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            key: const Key('donacion-cambiar-fecha'),
            onPressed: bloqueado ? null : _elegirFecha,
            child: const Text('Cambiar fecha'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      TextField(
        key: const Key('donacion-volumen'),
        controller: _volumen,
        enabled: !bloqueado,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: 'Volumen extraído (mL)',
          border: const OutlineInputBorder(),
          errorText: f.errores['volumenMl'],
        ),
        onChanged: f.cambiarVolumen,
      ),
      const SizedBox(height: 24),
      Text(
        'Unidades obtenidas',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              key: const Key('donacion-codigo-unidad'),
              controller: _codigo,
              enabled: !bloqueado,
              decoration: InputDecoration(
                labelText: 'Código de unidad',
                hintText: 'ej. U-001',
                border: const OutlineInputBorder(),
                errorText: f.errores['unidades'],
              ),
              onSubmitted: (_) => _agregarUnidad(),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            key: const Key('donacion-agregar-unidad'),
            onPressed: bloqueado ? null : _agregarUnidad,
            icon: const Icon(Icons.add),
            label: const Text('Agregar'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (f.codigos.isEmpty)
        const Text('Aún no agregas ninguna unidad.')
      else
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final codigo in f.codigos)
              InputChip(
                key: Key('unidad-$codigo'),
                label: Text(codigo),
                onDeleted: bloqueado ? null : () => f.quitarUnidad(codigo),
              ),
          ],
        ),
      const SizedBox(height: 8),
      const Text(
        'El grupo ABO/Rh de cada unidad se copia del donante al confirmar.',
      ),
      const SizedBox(height: 16),
      _dato(
        'Vencimiento de cada unidad',
        _fecha(f.vencimiento),
        const Key('donacion-vencimiento'),
      ),
      const Text(
        'Se calcula como extracción + 42 días y no se puede modificar.',
      ),
      const SizedBox(height: 24),
      if (f.confirmacionPendiente && !f.guardando)
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'No se pudo confirmar si la donación quedó registrada. '
            'Reintenta la confirmación antes de editar los datos.',
            key: Key('donacion-confirmacion-pendiente'),
          ),
        ),
      if (f.errorGeneral != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Semantics(
            liveRegion: true,
            child: Text(
              f.errorGeneral!,
              key: const Key('donacion-error'),
              style: TextStyle(color: colorError),
            ),
          ),
        ),
      FilledButton(
        key: const Key('donacion-confirmar'),
        onPressed: f.guardando || !f.autorizado ? null : _confirmar,
        child: Text(
          f.guardando
              ? 'Guardando…'
              : f.confirmacionPendiente
              ? 'Reintentar confirmación'
              : 'Confirmar donación',
        ),
      ),
    ];
  }

  Widget _aptitud(BuildContext context) {
    final f = _formulario;
    if (f.donante == null) {
      return const Text('Selecciona un donante para ver su aptitud.');
    }
    if (f.cargandoEvaluacion) return const Text('Consultando aptitud…');
    final colorError = Theme.of(context).colorScheme.error;
    final evaluacion = f.evaluacion;
    if (evaluacion == null) {
      return Text(
        'Sin evaluación registrada: no puede donar.',
        key: const Key('donacion-aptitud'),
        style: TextStyle(color: colorError),
      );
    }
    final resultado = switch (evaluacion.resultado) {
      ResultadoAptitud.apto => 'Apto',
      ResultadoAptitud.diferido => 'Diferido temporalmente',
      ResultadoAptitud.rechazado => 'Rechazado',
    };
    final fin = evaluacion.fechaFinVigencia;
    final vigencia = fin == null
        ? ''
        : ' del ${_fecha(evaluacion.fechaEvaluacion)} al ${_fecha(fin)}';
    final permite = f.aptoParaExtraccion;
    return Text(
      '$resultado$vigencia. '
      '${permite ? 'Puede donar en la fecha elegida.' : 'No puede donar en la fecha elegida.'}',
      key: const Key('donacion-aptitud'),
      style: permite ? null : TextStyle(color: colorError),
    );
  }

  Widget _dato(String etiqueta, String valor, Key key, {String? error}) =>
      InputDecorator(
        decoration: InputDecoration(
          labelText: etiqueta,
          border: const OutlineInputBorder(),
          errorText: error,
        ),
        child: Text(valor, key: key),
      );
}
