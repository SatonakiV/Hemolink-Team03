import '../../../core/access/auth_session.dart';

/// Unidad tal como la devuelve la búsqueda por código (sin datos del donante).
class UnidadDescarte {
  UnidadDescarte({
    required this.id,
    required this.codigo,
    required this.sedeId,
    required this.grupoAbo,
    required this.factorRh,
    required this.estado,
    required this.vencimiento,
    this.pedidoReservaId,
    this.motivoDescarte,
    this.fechaDescarte,
  });

  factory UnidadDescarte.fromJson(Map<String, dynamic> json) {
    final reserva = json['reserva'] as Map<String, dynamic>?;
    final descarte = json['descarte'] as Map<String, dynamic>?;
    return UnidadDescarte(
      id: json['id'] as String,
      codigo: json['codigo'] as String,
      sedeId: json['sedeId'] as String,
      grupoAbo: json['grupoAbo'] as String,
      factorRh: json['factorRh'] as String,
      estado: json['estado'] as String,
      vencimiento: DateTime.parse(json['fechaVencimiento'] as String),
      pedidoReservaId: reserva?['pedidoId'] as String?,
      motivoDescarte: descarte?['motivo'] as String?,
      fechaDescarte: descarte == null
          ? null
          : DateTime.parse(descarte['fecha'] as String),
    );
  }

  final String id;
  final String codigo;
  final String sedeId;
  final String grupoAbo;
  final String factorRh;
  final String estado;
  final DateTime vencimiento;
  final String? pedidoReservaId;
  final String? motivoDescarte;
  final DateTime? fechaDescarte;
  String get grupo => '$grupoAbo${factorRh == 'positivo' ? '+' : '-'}';
  bool get descartable => estado == 'disponible' || estado == 'reservada';
}

class ResultadoDescarte {
  ResultadoDescarte({
    required this.unidad,
    required this.repetido,
    required this.pedidosActualizados,
  });

  factory ResultadoDescarte.fromJson(Map<String, dynamic> json) =>
      ResultadoDescarte(
        unidad: UnidadDescarte.fromJson(json['item'] as Map<String, dynamic>),
        repetido: json['repetido'] as bool? ?? false,
        pedidosActualizados: [
          for (final pedido in (json['pedidos'] as List? ?? const []))
            (pedido as Map<String, dynamic>)['id'] as String,
        ],
      );

  final UnidadDescarte unidad;

  /// true si la unidad ya estaba descartada: el servidor conserva el primer registro.
  final bool repetido;
  final List<String> pedidosActualizados;
}

abstract interface class DescarteRepository {
  /// Busca por código en la sede de la sesión. Lanza [AuthException] si no existe.
  Future<UnidadDescarte> buscar(String codigo);

  Future<ResultadoDescarte> descartar(String unidadId, String motivo);
}

class ApiDescarteRepository implements DescarteRepository {
  ApiDescarteRepository(this.sesion);

  final AuthSession sesion;

  @override
  Future<UnidadDescarte> buscar(String codigo) async {
    final datos = await sesion.loadModuleData(
      'inventory/lookup',
      queryParameters: {'codigo': codigo},
    );
    return UnidadDescarte.fromJson(datos['item'] as Map<String, dynamic>);
  }

  @override
  Future<ResultadoDescarte> descartar(String unidadId, String motivo) async =>
      ResultadoDescarte.fromJson(
        await sesion.postModuleData(
          'inventory/${Uri.encodeComponent(unidadId)}/discard',
          {'motivo': motivo},
        ),
      );
}