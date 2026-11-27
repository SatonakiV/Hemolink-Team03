import 'package:flutter/material.dart';

import '../../../core/access/access_policy.dart';
import '../../../core/access/auth_session.dart';
import '../data/api_solicitud_repository.dart';
import '../data/solicitud_repository.dart';
import '../domain/solicitud.dart';

typedef SolicitudAccionesBuilder = List<Widget> Function(
  BuildContext context,
  Solicitud solicitud,
  VoidCallback recargar,
);

String _unidadesTexto(int cantidad) =>
    cantidad == 1 ? '1 unidad' : '$cantidad unidades';

String _fechaTexto(DateTime fecha) {
  final local = fecha.toLocal();
  final d = local.day.toString().padLeft(2, '0');
  final m = local.month.toString().padLeft(2, '0');
  final y = local.year.toString().padLeft(4, '0');
  return '$d/$m/$y';
}

String _fechaHoraTexto(DateTime fecha) {
  final local = fecha.toLocal();
  final h = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '${_fechaTexto(local)} $h:$min';
}

String _etiquetaEstado(String estado) => switch (estado.toLowerCase()) {
  'pendiente' => 'Pendiente',
  'reservado' => 'Reservado',
  'parcial' => 'Parcial',
  'completado' => 'Completado',
  _ => estado,
};

String _etiquetaPrioridad(String prioridad) =>
    prioridad.toLowerCase() == 'urgente' ? 'Urgente' : 'Normal';

String _etiquetaTipoDespacho(String tipo) => switch (tipo.toLowerCase()) {
  'programado' => 'Programado',
  'urgente' => 'Urgente',
  _ => tipo,
};

class SolicitudFichaPage extends StatefulWidget {
  const SolicitudFichaPage({
    super.key,
    required this.sesion,
    required this.repositorio,
    required this.solicitudId,
    this.solicitudInicial,
    this.accionesBuilder,
  });

  final AuthSession sesion;
  final SolicitudRepository repositorio;
  final String solicitudId;
  final Solicitud? solicitudInicial;
  final SolicitudAccionesBuilder? accionesBuilder;

  @override
  State<SolicitudFichaPage> createState() => _SolicitudFichaPageState();
}

class _SolicitudFichaPageState extends State<SolicitudFichaPage> {
  Future<Solicitud?>? _ficha;

  bool get _autorizado =>
      AccessPolicy.canViewRequests(widget.sesion.currentUser);

  @override
  void initState() {
    super.initState();
    if (_autorizado && widget.solicitudInicial != null) {
      _ficha = Future.value(widget.solicitudInicial);
    } else {
      _cargar();
    }
  }

  @override
  void didUpdateWidget(covariant SolicitudFichaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.solicitudId != oldWidget.solicitudId ||
        widget.solicitudInicial != oldWidget.solicitudInicial) {
      if (_autorizado && widget.solicitudInicial != null) {
        _ficha = Future.value(widget.solicitudInicial);
      } else {
        _cargar();
      }
    }
  }

  void _cargar() {
    setState(() {
      _ficha = _autorizado
          ? widget.repositorio.buscarPorId(widget.solicitudId)
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ficha de solicitud'),
        actions: [
          if (_autorizado)
            IconButton(
              tooltip: 'Actualizar ficha',
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: !_autorizado
          ? const Center(
              child: Text('Tu sesión no permite consultar solicitudes.'),
            )
          : FutureBuilder<Solicitud?>(
              future: _ficha,
              builder: (context, estado) {
                if (estado.connectionState != ConnectionState.done) {
                  return const Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: 'Cargando ficha de solicitud',
                    ),
                  );
                }

                if (estado.hasError) {
                  final error = estado.error;
                  final mensaje = error is SolicitudApiException
                      ? error.mensaje
                      : 'No se pudo consultar la solicitud. Vuelve a intentar.';
                  return _ContenidoFicha(
                    children: [
                      Semantics(
                        liveRegion: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              mensaje,
                              style: TextStyle(color: colores.error),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: _cargar,
                              child: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }

                final ficha = estado.data;
                if (ficha == null) {
                  return const _ContenidoFicha(
                    children: [Text('Solicitud no encontrada.')],
                  );
                }

                return _ContenidoFicha(
                  children: [
                    _EncabezadoFicha(ficha: ficha),
                    const SizedBox(height: 16),
                    _SeccionContadores(ficha: ficha),
                    const SizedBox(height: 16),
                    _SeccionDatosGenerales(ficha: ficha),
                    if (widget.accionesBuilder != null) ...[
                      const SizedBox(height: 16),
                      ...widget.accionesBuilder!(context, ficha, _cargar),
                    ],
                    const SizedBox(height: 16),
                    _SeccionReservas(reservas: ficha.reservas),
                    const SizedBox(height: 16),
                    _SeccionAvisos(avisos: ficha.avisos),
                    const SizedBox(height: 16),
                    _SeccionDespachos(despachos: ficha.despachos),
                  ],
                );
              },
            ),
    );
  }
}

class _ContenidoFicha extends StatelessWidget {
  const _ContenidoFicha({required this.children});

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

class _EncabezadoFicha extends StatelessWidget {
  const _EncabezadoFicha({required this.ficha});

  final Solicitud ficha;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final textos = Theme.of(context).textTheme;
    final urgente = ficha.prioridad.toLowerCase() == 'urgente';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Solicitud #${ficha.numero}',
                  style: textos.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Grupo requerido: ${ficha.grupoAbo} ${ficha.factorRh}',
                  style: textos.titleMedium,
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text('Estado: ${_etiquetaEstado(ficha.estado)}'),
                ),
                Chip(
                  backgroundColor: urgente ? colores.errorContainer : null,
                  label: Text(
                    'Prioridad: ${_etiquetaPrioridad(ficha.prioridad)}',
                    style: urgente
                        ? TextStyle(color: colores.onErrorContainer)
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SeccionContadores extends StatelessWidget {
  const _SeccionContadores({required this.ficha});

  final Solicitud ficha;

  @override
  Widget build(BuildContext context) {
    final contadores = [
      ('Solicitadas', ficha.cantidadSolicitada),
      ('Reservadas', ficha.cantidadReservada),
      ('Despachadas', ficha.cantidadDespachada),
      ('Pendientes por asignar', ficha.pendienteAsignar),
      ('Pendientes por entregar', ficha.pendienteEntregar),
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contadores de unidades',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                const espacio = 12.0;
                final ancho = constraints.maxWidth >= 600
                    ? (constraints.maxWidth - espacio * 2) / 3
                    : constraints.maxWidth >= 360
                    ? (constraints.maxWidth - espacio) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: espacio,
                  runSpacing: espacio,
                  children: [
                    for (final (etiqueta, cantidad) in contadores)
                      SizedBox(
                        width: ancho,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outlineVariant,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  etiqueta,
                                  style: Theme.of(context).textTheme.labelMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _unidadesTexto(cantidad),
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SeccionDatosGenerales extends StatelessWidget {
  const _SeccionDatosGenerales({required this.ficha});

  final Solicitud ficha;

  @override
  Widget build(BuildContext context) {
    final campos = {
      'Identificador': ficha.id,
      'Hospital': ficha.hospitalId,
      'Responsable': ficha.responsableId,
      'Fecha y hora de registro': _fechaHoraTexto(ficha.fechaRegistro),
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Datos de la solicitud',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            for (final campo in campos.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      campo.key,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 2),
                    SelectableText(campo.value),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SeccionReservas extends StatelessWidget {
  const _SeccionReservas({required this.reservas});

  final List<ReservaSolicitud> reservas;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reservas vigentes',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (reservas.isEmpty)
            const Text('No hay reservas vigentes.')
          else
            for (final reserva in reservas)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('Unidad ${reserva.codigo}'),
                subtitle: Text(
                  [
                    'Sede: ${reserva.sedeId}',
                    'Estado: ${reserva.estado}',
                    if (reserva.fechaVencimiento != null)
                      'Vence: ${_fechaTexto(reserva.fechaVencimiento!)}',
                  ].join(' · '),
                ),
              ),
        ],
      ),
    ),
  );
}

class _SeccionAvisos extends StatelessWidget {
  const _SeccionAvisos({required this.avisos});

  final List<AvisoSolicitud> avisos;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Avisos de faltante',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (avisos.isEmpty)
            const Text('No hay avisos registrados.')
          else
            for (final aviso in avisos)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  'Faltante: ${_unidadesTexto(aviso.cantidadFaltante)}',
                ),
                subtitle: Text(
                  [
                    if (aviso.decision != null) 'Decisión: ${aviso.decision}',
                    if (aviso.fecha != null) 'Fecha: ${aviso.fecha}',
                    if (aviso.usuarioRegistroId != null)
                      'Registrado por: ${aviso.usuarioRegistroId}',
                  ].join(' · '),
                ),
              ),
        ],
      ),
    ),
  );
}

class _SeccionDespachos extends StatelessWidget {
  const _SeccionDespachos({required this.despachos});

  final List<DespachoSolicitud> despachos;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Despachos',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (despachos.isEmpty)
            const Text('No hay despachos registrados.')
          else
            for (final despacho in despachos)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  '${_etiquetaTipoDespacho(despacho.tipo)} · '
                  '${_unidadesTexto(despacho.cantidad)}',
                ),
                subtitle: Text(
                  [
                    if (despacho.sedeId != null) 'Sede: ${despacho.sedeId}',
                    if (despacho.fechaPrevista != null)
                      'Fecha prevista: ${despacho.fechaPrevista}',
                    if (despacho.motivo != null) 'Motivo: ${despacho.motivo}',
                    if (despacho.fechaRegistro != null)
                      'Registrado: ${_fechaHoraTexto(despacho.fechaRegistro!)}',
                    if (despacho.responsableId != null)
                      'Responsable: ${despacho.responsableId}',
                  ].join(' · '),
                ),
              ),
        ],
      ),
    ),
  );
}
