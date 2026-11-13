import 'package:flutter/material.dart';
import '../../../core/access/auth_session.dart';
import '../../../domain/muestra.dart';
import '../../muestras/data/api_muestra_repository.dart';
import '../../muestras/data/muestra_repository.dart';
import '../domain/donacion.dart';

String _fecha(DateTime fecha) =>
    '${fecha.day.toString().padLeft(2, '0')}/'
    '${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';

/// Detalle de una donación con listado y formulario de registro de muestras.
class DonacionDetallePage extends StatefulWidget {
  const DonacionDetallePage({
    super.key,
    required this.sesion,
    required this.donacion,
    required this.muestraRepository,
    this.muestrasIniciales,
  });

  final AuthSession sesion;
  final Donacion donacion;
  final MuestraRepository muestraRepository;
  final List<Muestra>? muestrasIniciales;

  @override
  State<DonacionDetallePage> createState() => _DonacionDetallePageState();
}

class _DonacionDetallePageState extends State<DonacionDetallePage> {
  final _codigoController = TextEditingController();
  final List<Muestra> _muestras = [];
  bool _cargandoMuestras = false;
  bool _guardando = false;
  String? _errorFormulario;
  String? _errorCarga;

  @override
  void initState() {
    super.initState();
    if (widget.muestrasIniciales != null) {
      _muestras.addAll(widget.muestrasIniciales!);
    } else {
      _cargarMuestras();
    }
  }

  Future<void> _cargarMuestras() async {
    setState(() {
      _cargandoMuestras = true;
      _errorCarga = null;
    });
    try {
      final items = await widget.muestraRepository.buscar(
        donacionId: widget.donacion.id,
      );
      if (mounted) {
        setState(() {
          _muestras.clear();
          _muestras.addAll(items);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorCarga = e is MuestraApiException ? e.mensaje : '$e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _cargandoMuestras = false);
      }
    }
  }

  @override
  void dispose() {
    _codigoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Detalle de donación ${widget.donacion.id}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildInfoDonacion(context),
                const SizedBox(height: 24),
                _buildSeccionUnidades(context),
                const SizedBox(height: 24),
                _buildSeccionMuestras(context),
                const SizedBox(height: 24),
                _buildVinculos(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoDonacion(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Información de la donación',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text('Identificador: ${widget.donacion.id}'),
            Text('Donante ID: ${widget.donacion.donanteId}'),
            Text('Fecha de extracción: ${_fecha(widget.donacion.fechaExtraccion)}'),
            Text('Volumen: ${widget.donacion.volumenMl} mL'),
          ],
        ),
      ),
    );
  }

  // Vínculos de origen de la donación. 
  //Va al final para no mover las secciones de unidades y muestras.
  Widget _buildVinculos(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vínculos de origen',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('Evaluación utilizada: ${widget.donacion.evaluacionId}'),
            Text('Sede: ${widget.donacion.sedeId}'),
            Text('Responsable: ${widget.donacion.responsableId}'),
            Text(
              'Registrada: ${_fecha(widget.donacion.fechaRegistro.toLocal())}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeccionUnidades(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Unidades de sangre',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (widget.donacion.unidades.isEmpty)
          const Text('No hay unidades registradas para esta donación.')
        else
          for (final unidad in widget.donacion.unidades)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text('Unidad: ${unidad.codigo}'),
                subtitle: Text('Grupo: ${unidad.grupo} |' 'Donación: ${unidad.donacionId}',),
                trailing: Text('Vence: ${_fecha(unidad.fechaVencimiento)}'),
              ),
            ),
      ],
    );
  }

  Widget _buildSeccionMuestras(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Muestras',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        _buildFormularioMuestra(context),
        const SizedBox(height: 16),
        if (_cargandoMuestras)
          const CircularProgressIndicator()
        else if (_errorCarga != null)
          Text(
            _errorCarga!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          )
        else if (_muestras.isEmpty)
          const Text('No hay muestras registradas.')
        else
          for (final muestra in _muestras)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text('Muestra: ${muestra.codigo}'),
                subtitle: Text('Origen: ${muestra.donacionId}'),
              ),
            ),
      ],
    );
  }

  Widget _buildFormularioMuestra(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Registrar muestra',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('codigo-muestra-input'),
                    controller: _codigoController,
                    decoration: InputDecoration(
                      labelText: 'Código de muestra',
                      hintText: 'ej. M-001',
                      errorText: _errorFormulario,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  key: const Key('registrar-muestra-btn'),
                  onPressed: _guardando ? null : _guardarMuestra,
                  icon: const Icon(Icons.add),
                  label: const Text('Registrar muestra'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _guardarMuestra() async {
    final codigo = _codigoController.text.trim();
    if (codigo.isEmpty) {
      setState(() {
        _errorFormulario = 'Ingresa un código de muestra.';
      });
      return;
    }

    setState(() {
      _guardando = true;
      _errorFormulario = null;
    });

    try {
      final nueva = await widget.muestraRepository.guardar(
        DatosMuestra(
          codigo: codigo,
          donacionId: widget.donacion.id,
        ),
      );
      if (mounted) {
        setState(() {
          _muestras.add(nueva);
          _codigoController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Muestra registrada correctamente.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorFormulario = e is MuestraApiException ? e.mensaje : '$e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _guardando = false);
      }
    }
  }
}
