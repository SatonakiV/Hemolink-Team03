import 'package:flutter/material.dart';

import '../../../core/access/auth_session.dart';
import '../data/stock_inventario.dart';
import 'reserva_fefo_panel.dart';

class InventarioPage extends StatefulWidget {
  const InventarioPage({super.key, required this.sesion});

  final AuthSession sesion;

  @override
  State<InventarioPage> createState() => _InventarioPageState();
}

class _InventarioPageState extends State<InventarioPage> {
  final _sedes = <String>{};
  String _sedeId = '';
  String _grupoAbo = '';
  String _factorRh = '';
  late Future<StockInventario> _consulta;

  @override
  void initState() {
    super.initState();
    final sedeSesion = widget.sesion.currentUser?.siteId;
    if (sedeSesion != null) _sedes.add(sedeSesion);
    _consulta = _consultar();
  }

  Future<StockInventario> _consultar() async {
    final stock = await StockInventario.consultar(
      widget.sesion,
      sedeId: _sedeId,
      grupoAbo: _grupoAbo,
      factorRh: _factorRh,
    );
    // Conservar las sedes conocidas al aplicar filtros o cuando se agota su stock.
    if (mounted) _sedes.addAll(stock.unidades.map((unidad) => unidad.sedeId));
    return stock;
  }

  void _actualizar() {
    final consulta = _consultar();
    setState(() {
      _consulta = consulta;
    });
  }

  Widget _selector({
    required String etiqueta,
    required String valor,
    required Map<String, String> opciones,
    required ValueChanged<String> cambiar,
    required bool habilitado,
  }) => DropdownButtonFormField<String>(
    decoration: InputDecoration(
      labelText: etiqueta,
      border: const OutlineInputBorder(),
    ),
    initialValue: valor,
    isExpanded: true,
    items: [
      for (final opcion in opciones.entries)
        DropdownMenuItem<String>(
          value: opcion.key,
          child: Text(opcion.value, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: habilitado
        ? (nuevo) {
            if (nuevo == null || nuevo == valor) return;
            cambiar(nuevo);
            _actualizar();
          }
        : null,
  );

  Widget _filtros({required bool habilitado}) {
    final sedes = _sedes.toList()..sort();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const espacio = 12.0;
            final ancho = constraints.maxWidth >= 560
                ? (constraints.maxWidth - espacio * 2) / 3
                : constraints.maxWidth;
            return Wrap(
              spacing: espacio,
              runSpacing: espacio,
              children: [
                SizedBox(
                  width: ancho,
                  child: _selector(
                    etiqueta: 'Sede',
                    valor: _sedeId,
                    opciones: {
                      '': 'Todas las sedes',
                      for (final id in sedes) id: id,
                    },
                    cambiar: (valor) => _sedeId = valor,
                    habilitado: habilitado,
                  ),
                ),
                SizedBox(
                  width: ancho,
                  child: _selector(
                    etiqueta: 'Grupo ABO',
                    valor: _grupoAbo,
                    opciones: const {
                      '': 'Todos los grupos',
                      'A': 'A',
                      'B': 'B',
                      'AB': 'AB',
                      'O': 'O',
                    },
                    cambiar: (valor) => _grupoAbo = valor,
                    habilitado: habilitado,
                  ),
                ),
                SizedBox(
                  width: ancho,
                  child: _selector(
                    etiqueta: 'Factor Rh',
                    valor: _factorRh,
                    opciones: const {
                      '': 'Todos los factores',
                      'positivo': 'Positivo',
                      'negativo': 'Negativo',
                    },
                    cambiar: (valor) => _factorRh = valor,
                    habilitado: habilitado,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _resumen(BuildContext context, AsyncSnapshot<StockInventario> estado) {
    if (estado.connectionState != ConnectionState.done) {
      return const LinearProgressIndicator(semanticsLabel: 'Cargando stock');
    }
    if (estado.hasError) {
      final error = estado.error;
      return Semantics(
        liveRegion: true,
        child: Text(
          error is AuthException
              ? error.message
              : 'No se pudo consultar el stock. Vuelve a intentar.',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }
    final total = estado.requireData.total;
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            total == 1 ? '1 unidad disponible' : '$total unidades disponibles',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (total == 0)
            const Text('No hay unidades para los filtros seleccionados.'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<StockInventario>(
    future: _consulta,
    builder: (context, estado) {
      final listo = estado.connectionState == ConnectionState.done;
      final sesionActiva = widget.sesion.currentUser != null;
      final unidades = listo ? estado.data?.unidades : null;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Inventario'),
          actions: [
            IconButton(
              tooltip: 'Actualizar stock',
              onPressed: listo && sesionActiva ? _actualizar : null,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _filtros(habilitado: listo && sesionActiva),
                          const SizedBox(height: 20),
                          _resumen(context, estado),
                          if (sesionActiva) ...[
                            const SizedBox(height: 12),
                            ReservaFefoPanel(
                              sesion: widget.sesion,
                              alCambiarStock: _actualizar,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (unidades != null)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      sliver: SliverList.separated(
                        itemCount: unidades.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _FilaUnidad(unidades[index]),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _FilaUnidad extends StatelessWidget {
  const _FilaUnidad(this.unidad);

  final UnidadStock unidad;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final fecha = unidad.vencimiento;
    final vencimiento =
        '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Semantics(
          label: 'Grupo ${unidad.grupoAbo} ${unidad.factorRh}',
          excludeSemantics: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colores.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                unidad.grupo,
                style: TextStyle(
                  color: colores.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        title: Text(unidad.codigo),
        subtitle: Text('${unidad.sedeId}\nVence el $vencimiento'),
        isThreeLine: true,
      ),
    );
  }
}
