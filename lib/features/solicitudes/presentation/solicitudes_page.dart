import 'package:flutter/material.dart';

import '../../../core/access/access_policy.dart';
import '../../../core/access/auth_session.dart';
import '../data/api_solicitud_repository.dart';
import '../data/crear_repositorio_solicitudes.dart';
import '../data/solicitud_repository.dart';
import '../domain/solicitud.dart';
import 'solicitud_ficha_page.dart';
import 'solicitud_formulario_page.dart';

String _etiquetaEstado(String estado) => switch (estado.toLowerCase()) {
  'pendiente' => 'Pendiente',
  'reservado' => 'Reservado',
  'parcial' => 'Parcial',
  'completado' => 'Completado',
  _ => estado,
};

String _etiquetaPrioridad(String prioridad) =>
    prioridad.toLowerCase() == 'urgente' ? 'Urgente' : 'Normal';

class SolicitudesPage extends StatefulWidget {
  const SolicitudesPage({
    super.key,
    required this.sesion,
    this.repositorio,
    this.accionesFichaBuilder,
  });

  final AuthSession sesion;
  final SolicitudRepository? repositorio;
  final SolicitudAccionesBuilder? accionesFichaBuilder;

  @override
  State<SolicitudesPage> createState() => _SolicitudesPageState();
}

class _SolicitudesPageState extends State<SolicitudesPage> {
  late final SolicitudRepository _repositorio =
      widget.repositorio ??
      crearRepositorioSolicitudes(sesion: widget.sesion);

  List<Solicitud> _items = const [];
  bool _cargando = false;
  String? _error;
  int _solicitudConsulta = 0;

  bool get _autorizado =>
      AccessPolicy.canViewRequests(widget.sesion.currentUser);
  bool get _puedeCrear =>
      AccessPolicy.canCreateRequests(widget.sesion.currentUser);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final consulta = ++_solicitudConsulta;
    setState(() {
      _error = null;
      _cargando = _autorizado;
      if (!_autorizado) _items = const [];
    });
    if (!_autorizado) return;

    try {
      final items = await _repositorio.listar();
      if (!mounted || consulta != _solicitudConsulta) return;
      setState(() => _items = items);
    } catch (error) {
      if (!mounted || consulta != _solicitudConsulta) return;
      setState(() {
        _error = error is SolicitudApiException
            ? error.mensaje
            : 'No se pudieron consultar las solicitudes. Vuelve a intentar.';
      });
    } finally {
      if (mounted && consulta == _solicitudConsulta) {
        setState(() => _cargando = false);
      }
    }
  }

  Future<void> _crear() async {
    if (!_puedeCrear) return;
    final creada = await Navigator.of(context).push<Solicitud>(
      MaterialPageRoute(
        builder: (_) => SolicitudFormularioPage(
          sesion: widget.sesion,
          repositorio: _repositorio,
        ),
      ),
    );
    if (!mounted || creada == null || !_autorizado) return;
    await _cargar();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Solicitud #${creada.numero} registrada correctamente.'),
      ),
    );
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SolicitudFichaPage(
          sesion: widget.sesion,
          repositorio: _repositorio,
          solicitudId: creada.id,
          solicitudInicial: creada,
          accionesBuilder: widget.accionesFichaBuilder,
        ),
      ),
    );
    if (mounted) await _cargar();
  }

  Future<void> _abrirFicha(Solicitud item) async {
    if (!_autorizado) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SolicitudFichaPage(
          sesion: widget.sesion,
          repositorio: _repositorio,
          solicitudId: item.id,
          accionesBuilder: widget.accionesFichaBuilder,
        ),
      ),
    );
    if (mounted) await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final esInventario =
        widget.sesion.currentUser?.role.name == 'inventory';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Solicitudes'),
        actions: [
          if (_autorizado)
            IconButton(
              tooltip: 'Actualizar solicitudes',
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: !_autorizado
          ? const Center(
              child: Text('Tu sesión no permite consultar solicitudes.'),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 16,
                        runSpacing: 12,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            esInventario
                                ? 'Bandeja de solicitudes'
                                : 'Solicitudes del hospital',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          if (_puedeCrear)
                            FilledButton.icon(
                              key: const Key('nueva-solicitud-btn'),
                              onPressed: _cargando ? null : _crear,
                              icon: const Icon(Icons.add),
                              label: const Text('Nueva solicitud'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        esInventario
                            ? 'Pedidos ordenados por prioridad urgente y antigüedad.'
                            : 'Consulta tus solicitudes y revisa su avance de atención.',
                      ),
                      const SizedBox(height: 24),
                      if (_cargando)
                        const LinearProgressIndicator(
                          semanticsLabel: 'Cargando solicitudes',
                        ),
                      if (_error != null)
                        Semantics(
                          liveRegion: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _error!,
                                style: TextStyle(color: colores.error),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: _cargando ? null : _cargar,
                                child: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        ),
                      if (!_cargando && _error == null) ...[
                        if (_items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Text('No hay solicitudes registradas.'),
                          )
                        else ...[
                          Text(
                            _items.length == 1
                                ? '1 solicitud'
                                : '${_items.length} solicitudes',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 12),
                          for (final item in _items)
                            _TarjetaSolicitud(
                              item: item,
                              mostrarHospital: esInventario,
                              onTap: () => _abrirFicha(item),
                            ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _TarjetaSolicitud extends StatelessWidget {
  const _TarjetaSolicitud({
    required this.item,
    required this.mostrarHospital,
    required this.onTap,
  });

  final Solicitud item;
  final bool mostrarHospital;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final urgente = item.prioridad.toLowerCase() == 'urgente';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        leading: DecoratedBox(
          decoration: BoxDecoration(
            color: urgente ? colores.errorContainer : colores.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              item.grupoCompacto,
              style: TextStyle(
                color: urgente
                    ? colores.onErrorContainer
                    : colores.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        title: Text('Solicitud #${item.numero} · ${item.grupoCompacto}'),
        subtitle: Text(
          [
            'Prioridad: ${_etiquetaPrioridad(item.prioridad)} · Estado: ${_etiquetaEstado(item.estado)}',
            if (mostrarHospital) 'Hospital: ${item.hospitalId}',
            'Solicitadas: ${item.cantidadSolicitada} · Reservadas: ${item.cantidadReservada} · Despachadas: ${item.cantidadDespachada}',
          ].join('\n'),
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
