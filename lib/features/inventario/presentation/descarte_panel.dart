import 'package:flutter/material.dart';
import '../data/descarte_repository.dart';
import 'descarte_controller.dart';

String _fecha(DateTime fecha) =>
    '${fecha.day.toString().padLeft(2, '0')}/'
    '${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';

const _estados = {
  'disponible': 'Disponible',
  'reservada': 'Reservada',
  'descartada': 'Descartada',
  'despachada': 'Despachada',
};

/// HU07 / T07.2: buscar una unidad por código y descartarla con motivo.
class DescartePanel extends StatefulWidget {
  const DescartePanel({
    super.key,
    required this.repositorio,
    required this.alDescartar,
  });

  final DescarteRepository repositorio;

  /// Se llama solo después de que el servidor confirmó el descarte, para
  /// recargar el stock (la unidad deja de estar disponible).
  final VoidCallback alDescartar;

  @override
  State<DescartePanel> createState() => _DescartePanelState();
}

class _DescartePanelState extends State<DescartePanel> {
  late final _descarte = DescarteController(widget.repositorio);
  final _codigo = TextEditingController();
  final _motivo = TextEditingController();

  @override
  void dispose() {
    _descarte.dispose();
    _codigo.dispose();
    _motivo.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    _motivo.clear();
    _descarte.cambiarMotivo('');
    await _descarte.buscar(_codigo.text);
  }

  Future<void> _confirmar() async {
    final unidad = _descarte.unidad;
    if (unidad == null) return;
    final aceptar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar descarte'),
        content: Text(
          'La unidad ${unidad.codigo} dejará de estar disponible'
          '${unidad.pedidoReservaId == null ? '' : ' y se liberará su reserva'}. '
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    // UT07.2-B: cancelar (o cerrar el diálogo) no llama al servidor.
    if (!mounted || aceptar != true) return;
    if (await _descarte.descartar()) {
      _motivo.clear();
      widget.alDescartar();
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: ExpansionTile(
      title: const Text('Descartar unidad'),
      maintainState: true,
      childrenPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        ListenableBuilder(
          listenable: _descarte,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _contenido(context),
          ),
        ),
      ],
    ),
  );

  List<Widget> _contenido(BuildContext context) {
    final d = _descarte;
    final unidad = d.unidad;
    final colorError = Theme.of(context).colorScheme.error;
    final ocupado = d.buscando || d.guardando;
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              key: const Key('descarte-codigo'),
              controller: _codigo,
              enabled: !ocupado,
              decoration: const InputDecoration(
                labelText: 'Código de la unidad',
                hintText: 'ej. U-001',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _buscar(),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            key: const Key('descarte-buscar'),
            onPressed: ocupado ? null : _buscar,
            child: const Text('Buscar'),
          ),
        ],
      ),
      if (ocupado) ...[
        const SizedBox(height: 12),
        LinearProgressIndicator(
          semanticsLabel: d.guardando ? 'Guardando descarte' : 'Buscando unidad',
        ),
      ],
      if (d.error != null) ...[
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Text(
            d.error!,
            key: const Key('descarte-error'),
            style: TextStyle(color: colorError),
          ),
        ),
      ],
      if (d.exito != null) ...[
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Text(d.exito!, key: const Key('descarte-exito')),
        ),
      ],
      if (unidad != null) ...[
        const SizedBox(height: 12),
        _ficha(context, unidad),
        if (unidad.descartable) ...[
          const SizedBox(height: 12),
          TextField(
            key: const Key('descarte-motivo'),
            controller: _motivo,
            enabled: !ocupado,
            maxLength: 300,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Motivo del descarte',
              border: OutlineInputBorder(),
            ),
            onChanged: d.cambiarMotivo,
          ),
          FilledButton(
            key: const Key('descarte-confirmar'),
            onPressed: d.puedeConfirmar ? _confirmar : null,
            child: const Text('Descartar unidad'),
          ),
        ] else if (unidad.estado == 'despachada')
          Text(
            'Una unidad despachada no se puede descartar.',
            style: TextStyle(color: colorError),
          ),
      ],
    ];
  }

  Widget _ficha(BuildContext context, UnidadDescarte unidad) => Column(
    key: const Key('descarte-ficha'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(unidad.codigo, style: Theme.of(context).textTheme.titleMedium),
      Text('Estado: ${_estados[unidad.estado] ?? unidad.estado}'),
      Text('Sede: ${unidad.sedeId} · Grupo: ${unidad.grupo}'),
      Text('Vence el ${_fecha(unidad.vencimiento)}'),
      if (unidad.pedidoReservaId != null)
        Text('Reservada para la solicitud ${unidad.pedidoReservaId}'),
      if (unidad.motivoDescarte != null)
        Text(
          'Descartada el ${_fecha(unidad.fechaDescarte!)}. '
          'Motivo: ${unidad.motivoDescarte}',
        ),
    ],
  );
}