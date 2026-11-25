import 'stock_inventario.dart';

class AvisoSolicitud {
  AvisoSolicitud.fromJson(Map<String, dynamic> json)
    : pedidoId = json['pedidoId'] as String,
      cantidadFaltante = json['cantidadFaltante'] as int,
      decision = json['decision'] as String,
      fechaRegistro = DateTime.tryParse(
        json['fechaRegistro'] as String? ?? '',
      );

  final String pedidoId;
  final int cantidadFaltante;
  final String decision;
  final DateTime? fechaRegistro;
}

class SolicitudInventario {
  SolicitudInventario.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      numero = json['numero'] as int,
      grupoAbo = json['grupoAbo'] as String,
      factorRh = json['factorRh'] as String,
      prioridad = json['prioridad'] as String,
      cantidadSolicitada = json['cantidadSolicitada'] as int,
      cantidadDespachada = json['cantidadDespachada'] as int? ?? 0,
      cantidadReservada = json['cantidadReservada'] as int? ?? 0,
      pendienteEntregar = json['pendienteEntregar'] as int? ??
          ((json['cantidadSolicitada'] as int) -
              (json['cantidadDespachada'] as int? ?? 0)),
      pendienteAsignar = json['pendienteAsignar'] as int? ??
          ((json['cantidadSolicitada'] as int) -
              (json['cantidadDespachada'] as int? ?? 0) -
              (json['cantidadReservada'] as int? ?? 0)),
      estado = json['estado'] as String? ?? 'pendiente',
      avisos = (json['avisos'] as List<dynamic>? ?? [])
          .map(
            (aviso) => AvisoSolicitud.fromJson(
              Map<String, dynamic>.from(aviso as Map),
            ),
          )
          .toList();

  final String id;
  final int numero;
  final String grupoAbo;
  final String factorRh;
  final String prioridad;

  final int cantidadSolicitada;
  final int cantidadDespachada;
  final int cantidadReservada;

  final int pendienteAsignar;
  final int pendienteEntregar;

  final String estado;
  final List<AvisoSolicitud> avisos;

  String get grupo =>
      '$grupoAbo${factorRh == 'positivo' ? '+' : '-'}';

  AvisoSolicitud? get ultimoAviso =>
      avisos.isEmpty ? null : avisos.last;

  int get cantidadFaltante =>
      ultimoAviso?.cantidadFaltante ?? 0;
}

class PropuestaReserva {
  PropuestaReserva.fromJson(Map<String, dynamic> json)
    : estado = json['estado'] as String,
      pendienteAsignar = json['pendienteAsignar'] as int,
      stockElegible = json['stockElegible'] as int,
      faltante = json['faltante'] as int,
      unidades = _convertirUnidades(json['unidades']);

  final String estado;
  final int pendienteAsignar;
  final int stockElegible;
  final int faltante;
  final List<UnidadStock> unidades;

  static List<UnidadStock> _convertirUnidades(dynamic valor) {
    if (valor is! List) {
      throw const FormatException(
        'La propuesta no contiene una lista de unidades.',
      );
    }

    return valor.map((item) {
      final unidad = UnidadStock.fromJson(
        Map<String, dynamic>.from(item as Map),
      );

      if (!unidad.tieneIdentificador) {
        throw const FormatException(
          'Una unidad propuesta no tiene identificador.',
        );
      }

      return unidad;
    }).toList();
  }
}
