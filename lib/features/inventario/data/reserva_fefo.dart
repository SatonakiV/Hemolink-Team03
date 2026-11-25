import '../../../core/access/auth_session.dart';

class PedidoInventario {
  PedidoInventario.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      nombre = json['label'] as String? ?? json['id'] as String,
      hospital = (json['hospitalId'] ?? json['scopeId']) as String;

  final String id;
  final String nombre;
  final String hospital;

  static Future<List<PedidoInventario>> listar(AuthSession sesion) async {
    final items = await sesion.loadModule('requests');
    return [
      for (final item in items)
        if (item['cantidadSolicitada'] case final int cantidad
            when cantidad > 0)
          PedidoInventario.fromJson(item),
    ];
  }
}

class UnidadReserva {
  UnidadReserva.fromJson(Map<String, dynamic> json)
    : codigo = json['codigo'] as String,
      sedeId = json['sedeId'] as String,
      vencimiento = DateTime.parse(json['fechaVencimiento'] as String);

  final String codigo;
  final String sedeId;
  final DateTime vencimiento;
}

class SaldosReserva {
  SaldosReserva.fromJson(Map<String, dynamic> json)
    : solicitadas = json['cantidadSolicitada'] as int,
      despachadas = json['cantidadDespachada'] as int,
      reservadas = json['cantidadReservada'] as int,
      pendienteAsignar = json['pendienteAsignar'] as int,
      pendienteEntregar = json['pendienteEntregar'] as int,
      estado = json['estado'] as String;

  final int solicitadas;
  final int despachadas;
  final int reservadas;
  final int pendienteAsignar;
  final int pendienteEntregar;
  final String estado;
}

class DetalleReserva {
  DetalleReserva.fromJson(Map<String, dynamic> json)
    : saldos = SaldosReserva.fromJson(json['saldos'] as Map<String, dynamic>),
      reservas = _unidades(json['reservas'] as List<dynamic>),
      propuesta = _unidades(json['propuesta']['unidades'] as List<dynamic>),
      faltante = json['propuesta']['faltante'] as int,
      stockElegible = json['propuesta']['stockElegible'] as int,
      version = json['propuesta']['version'] as String?;

  final SaldosReserva saldos;
  final List<UnidadReserva> reservas;
  final List<UnidadReserva> propuesta;
  final int faltante;
  final int stockElegible;
  final String? version;

  static List<UnidadReserva> _unidades(List<dynamic> items) =>
      items.cast<Map<String, dynamic>>().map(UnidadReserva.fromJson).toList();

  static String _ruta(String pedidoId) =>
      'requests/${Uri.encodeComponent(pedidoId)}/reservations';

  static Future<DetalleReserva> consultar(
    AuthSession sesion,
    String pedidoId,
  ) async =>
      DetalleReserva.fromJson(await sesion.loadModuleData(_ruta(pedidoId)));

  static Future<DetalleReserva> confirmar(
    AuthSession sesion,
    String pedidoId,
    String version,
  ) async => DetalleReserva.fromJson(
    await sesion.postModuleData(_ruta(pedidoId), {'version': version}),
  );
}
