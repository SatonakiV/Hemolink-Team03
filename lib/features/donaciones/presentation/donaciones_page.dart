import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../core/access/auth_session.dart';
import '../../aptitud/data/crear_repositorio_evaluaciones.dart';
import '../../aptitud/data/evaluacion_repository.dart';
import '../../donantes/data/crear_repositorio_donantes.dart';
import '../../donantes/data/donante_repository.dart';
import '../../muestras/data/crear_repositorio_muestras.dart';
import '../../muestras/data/muestra_repository.dart';
import '../data/api_donacion_repository.dart';
import '../data/crear_repositorio_donaciones.dart';
import '../data/donacion_repository.dart';
import '../domain/donacion.dart';
import 'donacion_detalle_page.dart';
import 'donacion_formulario_page.dart';

String _fecha(DateTime fecha) =>
    '${fecha.day.toString().padLeft(2, '0')}/'
    '${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';

/// Entrada al módulo Donaciones: listado de la sede, registro y detalle.
/// Si no se inyectan repositorios, los crea con la sesión activa.
class DonacionesPage extends StatefulWidget {
  const DonacionesPage({
    super.key,
    required this.sesion,
    this.donaciones,
    this.donantes,
    this.evaluaciones,
    this.muestras,
    this.reloj,
  });

  final AuthSession sesion;
  final DonacionRepository? donaciones;
  final DonanteRepository? donantes;
  final EvaluacionRepository? evaluaciones;
  final MuestraRepository? muestras;
  final DateTime Function()? reloj;

  @override
  State<DonacionesPage> createState() => _DonacionesPageState();
}

class _DonacionesPageState extends State<DonacionesPage> {
  http.Client? _cliente;
  http.Client get _http => _cliente ??= http.Client();

  late final DonacionRepository _donaciones =
      widget.donaciones ??
      crearRepositorioDonaciones(sesion: widget.sesion, cliente: _http);
  late final DonanteRepository _donantes =
      widget.donantes ??
      crearRepositorioDonantes(sesion: widget.sesion, cliente: _http);
  late final EvaluacionRepository _evaluaciones =
      widget.evaluaciones ??
      crearRepositorioEvaluaciones(sesion: widget.sesion, cliente: _http);
  late final MuestraRepository _muestras =
      widget.muestras ??
      crearRepositorioMuestras(sesion: widget.sesion, cliente: _http);

  List<ResumenDonacion>? _items;
  String? _error;
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    _cargar();

  }
  @override
  void dispose() {
    _cliente?.close();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final items = await _donaciones.listar();
      if (mounted) setState(() => _items = items);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is DonacionApiException
              ? error.mensaje
              : 'No se pudo cargar el listado de donaciones.',
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _registrar() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DonacionFormularioPage(
          sesion: widget.sesion,
          donantes: _donantes,
          evaluaciones: _evaluaciones,
          donaciones: _donaciones,
          muestras: _muestras,
          reloj: widget.reloj,
        ),
      ),
    );
    if (mounted) await _cargar();
  }

  Future<void> _abrir(String id) async {
    setState(() => _error = null);
    try {
      final donacion = await _donaciones.buscarPorId(id);
      if (!mounted) return;
      if (donacion == null) {
        setState(() => _error = 'La donación ya no existe.');
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DonacionDetallePage(
            sesion: widget.sesion,
            donacion: donacion,
            muestraRepository: _muestras,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is DonacionApiException
              ? error.mensaje
              : 'No se pudo abrir el detalle de la donación.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Donaciones')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  key: const Key('donaciones-registrar'),
                  onPressed: _cargando ? null : _registrar,
                  icon: const Icon(Icons.add),
                  label: const Text('Registrar donación'),
                ),
                const SizedBox(height: 16),
                if (_cargando) const LinearProgressIndicator(),
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton(
                    onPressed: _cargando ? null : _cargar,
                    child: const Text('Reintentar'),
                  ),
                ],
                if (items != null && items.isEmpty)
                  const Text('No hay donaciones registradas en esta sede.'),
                if (items != null)
                  for (final item in items)
                    Card(
                      child: ListTile(
                        key: Key('donacion-${item.id}'),
                        title: Text(
                          'Extracción ${_fecha(item.fechaExtraccion)} · '
                          '${item.volumenMl} mL',
                        ),
                        subtitle: Text('Donante: ${item.donanteId}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _abrir(item.id),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}