import 'package:flutter/material.dart';

import '../../../core/access/auth_session.dart';
import '../data/reserva_fefo.dart';

class ReservaFefoPanel extends StatefulWidget {
  const ReservaFefoPanel({
    super.key,
    required this.sesion,
    required this.alCambiarStock,
  });

  final AuthSession sesion;
  final VoidCallback alCambiarStock;

  @override
  State<ReservaFefoPanel> createState() => _ReservaFefoPanelState();
}

class _ReservaFefoPanelState extends State<ReservaFefoPanel> {
  Future<List<PedidoInventario>>? _pedidos;
  String? _pedidoId;
  DetalleReserva? _detalle;
  String? _error;
  bool _ocupado = false;
  bool _confirmada = false;

  void _cargarPedidos() => setState(() {
    _pedidoId = null;
    _detalle = null;
    _error = null;
    _confirmada = false;
    _pedidos = PedidoInventario.listar(widget.sesion);
  });

  Future<void> _cargarPropuesta(String pedidoId) async {
    setState(() {
      _pedidoId = pedidoId;
      _detalle = null;
      _error = null;
      _confirmada = false;
      _ocupado = true;
    });
    try {
      final detalle = await DetalleReserva.consultar(widget.sesion, pedidoId);
      if (mounted) setState(() => _detalle = detalle);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _mensaje(error, 'No se pudo consultar la propuesta FEFO.');
        });
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _confirmar(String pedidoId, String version, int cantidad) async {
    final aceptar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar reserva'),
        content: Text(
          cantidad == 1
              ? 'Se reservará 1 unidad para esta solicitud.'
              : 'Se reservarán $cantidad unidades para esta solicitud.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (!mounted || aceptar != true) return;
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final confirmado = await DetalleReserva.confirmar(
        widget.sesion,
        pedidoId,
        version,
      );
      if (!mounted) return;
      setState(() {
        _detalle = confirmado;
        _confirmada = true;
      });
      widget.alCambiarStock();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _detalle = null;
        _error = _mensaje(error, 'No se pudo confirmar la reserva.');
      });
      if (error is AuthException && error.status == 409) {
        widget.alCambiarStock();
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  String _mensaje(Object error, String defecto) =>
      error is AuthException ? error.message : defecto;

  Widget _selector(List<PedidoInventario> pedidos) {
    if (pedidos.isEmpty) return const Text('No hay solicitudes registradas.');
    return DropdownButtonFormField<String>(
      key: ValueKey(_pedidoId),
      initialValue: _pedidoId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Solicitud',
        border: OutlineInputBorder(),
      ),
      items: [
        for (final pedido in pedidos)
          DropdownMenuItem(
            value: pedido.id,
            child: Text(
              '${pedido.nombre} · ${pedido.hospital}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: _ocupado
          ? null
          : (id) {
              if (id != null && id != _pedidoId) _cargarPropuesta(id);
            },
    );
  }

  Widget _unidades(List<UnidadReserva> unidades, {bool numerar = false}) =>
      Column(
        children: [
          for (final (indice, unidad) in unidades.indexed)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                numerar ? '${indice + 1}. ${unidad.codigo}' : unidad.codigo,
              ),
              subtitle: Text(
                '${unidad.sedeId} · Vence el '
                '${unidad.vencimiento.day.toString().padLeft(2, '0')}/'
                '${unidad.vencimiento.month.toString().padLeft(2, '0')}/'
                '${unidad.vencimiento.year}',
              ),
            ),
        ],
      );

  Widget _resultado(DetalleReserva detalle) {
    final saldos = detalle.saldos;
    final titulos = Theme.of(context).textTheme.titleMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_confirmada)
          Semantics(liveRegion: true, child: const Text('Reserva confirmada.')),
        Text('Estado: ${saldos.estado}', style: titulos),
        Text(
          'Solicitadas: ${saldos.solicitadas} · Despachadas: ${saldos.despachadas}'
          ' · Reservadas: ${saldos.reservadas}',
        ),
        Text('Pendientes por asignar: ${saldos.pendienteAsignar}'),
        Text('Pendientes por entregar: ${saldos.pendienteEntregar}'),
        if (detalle.reservas.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Reservas vigentes', style: titulos),
          _unidades(detalle.reservas),
        ],
        if (detalle.propuesta.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Propuesta FEFO', style: titulos),
          _unidades(detalle.propuesta, numerar: true),
        ],
        if (detalle.faltante > 0)
          Text(
            'Stock insuficiente. Unidades elegibles: ${detalle.stockElegible}. '
            'Faltantes: ${detalle.faltante}.',
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: ExpansionTile(
      title: const Text('Reservar unidades'),
      maintainState: true,
      onExpansionChanged: (abierto) {
        if (abierto && _pedidos == null) _cargarPedidos();
      },
      children: [
        if (_pedidos case final pedidos?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FutureBuilder<List<PedidoInventario>>(
              future: pedidos,
              builder: (context, estado) {
                if (estado.connectionState != ConnectionState.done) {
                  return const LinearProgressIndicator(
                    semanticsLabel: 'Cargando solicitudes',
                  );
                }
                final pedidoId = _pedidoId;
                final detalle = _detalle;
                final version = detalle?.version;
                final error = _error;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (estado.hasError)
                      Text(
                        _mensaje(
                          estado.error!,
                          'No se pudieron consultar las solicitudes.',
                        ),
                      )
                    else
                      _selector(estado.requireData),
                    const SizedBox(height: 12),
                    if (_ocupado)
                      const LinearProgressIndicator(
                        semanticsLabel: 'Procesando reserva',
                      ),
                    if (error != null)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (detalle != null) _resultado(detalle),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (pedidoId == null)
                          TextButton(
                            onPressed: _cargarPedidos,
                            child: const Text('Actualizar solicitudes'),
                          )
                        else ...[
                          TextButton(
                            onPressed: _ocupado
                                ? null
                                : () => _cargarPropuesta(pedidoId),
                            child: const Text('Recalcular propuesta'),
                          ),
                          if (detalle != null && version != null)
                            FilledButton(
                              onPressed: _ocupado
                                  ? null
                                  : () => _confirmar(
                                      pedidoId,
                                      version,
                                      detalle.propuesta.length,
                                    ),
                              child: const Text('Confirmar reserva'),
                            ),
                        ],
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    ),
  );
}
