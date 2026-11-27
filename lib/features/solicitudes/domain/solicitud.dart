class ReservaSolicitud {
  const ReservaSolicitud({
    required this.id,
    required this.codigo,
    required this.sedeId,
    required this.estado,
    this.fechaVencimiento,
    this.unidadId,
  });

  factory ReservaSolicitud.fromJson(Map<String, dynamic> json) {
    final rawFecha = json['fechaVencimiento'] as String?;
    return ReservaSolicitud(
      id: (json['id'] ?? json['unidadId'] ?? '') as String,
      codigo: (json['codigo'] ?? json['id'] ?? '') as String,
      sedeId: (json['sedeId'] ?? json['scopeId'] ?? '') as String,
      estado: (json['estado'] ?? 'reservada') as String,
      fechaVencimiento: rawFecha != null && rawFecha.isNotEmpty
          ? DateTime.tryParse(rawFecha)
          : null,
      unidadId: json['unidadId'] as String?,
    );
  }

  final String id;
  final String codigo;
  final String sedeId;
  final String estado;
  final DateTime? fechaVencimiento;
  final String? unidadId;
}

class AvisoSolicitud {
  const AvisoSolicitud({
    required this.id,
    required this.cantidadFaltante,
    this.decision,
    this.fecha,
    this.fechaRegistro,
    this.usuarioRegistroId,
  });

  factory AvisoSolicitud.fromJson(Map<String, dynamic> json) {
    final rawFechaReg = json['fechaRegistro'] as String?;
    return AvisoSolicitud(
      id: (json['id'] ?? '') as String,
      decision: json['decision'] as String?,
      cantidadFaltante:
          (json['cantidadFaltante'] ?? json['faltante'] ?? 0) as int,
      fecha: json['fecha'] as String?,
      fechaRegistro: rawFechaReg != null && rawFechaReg.isNotEmpty
          ? DateTime.tryParse(rawFechaReg)
          : null,
      usuarioRegistroId: json['usuarioRegistroId'] as String?,
    );
  }

  final String id;
  final String? decision;
  final int cantidadFaltante;
  final String? fecha;
  final DateTime? fechaRegistro;
  final String? usuarioRegistroId;
}

class DespachoSolicitud {
  const DespachoSolicitud({
    required this.id,
    required this.tipo,
    required this.cantidad,
    this.sedeId,
    this.fechaPrevista,
    this.motivo,
    this.unidades = const [],
    this.responsableId,
    this.fechaRegistro,
  });

  factory DespachoSolicitud.fromJson(Map<String, dynamic> json) {
    final rawUnidades = (json['unidades'] ?? json['reservaIds']) as List<dynamic>?;
    final unidades = rawUnidades == null
        ? const <String>[]
        : rawUnidades.map((e) => e.toString()).toList();
    final rawFecha = json['fechaRegistro'] as String?;
    return DespachoSolicitud(
      id: (json['id'] ?? '') as String,
      tipo: (json['tipo'] ?? '') as String,
      sedeId: (json['sedeId'] ?? json['scopeId']) as String?,
      fechaPrevista: json['fechaPrevista'] as String?,
      motivo: json['motivo'] as String?,
      cantidad: (json['cantidad'] as int?) ?? unidades.length,
      unidades: unidades,
      responsableId:
          (json['responsableId'] ?? json['usuarioRegistroId']) as String?,
      fechaRegistro: rawFecha != null && rawFecha.isNotEmpty
          ? DateTime.tryParse(rawFecha)
          : null,
    );
  }

  final String id;
  final String tipo;
  final String? sedeId;
  final String? fechaPrevista;
  final String? motivo;
  final int cantidad;
  final List<String> unidades;
  final String? responsableId;
  final DateTime? fechaRegistro;
}

class Solicitud {
  const Solicitud({
    required this.id,
    required this.numero,
    required this.hospitalId,
    required this.responsableId,
    required this.grupoAbo,
    required this.factorRh,
    required this.prioridad,
    required this.estado,
    required this.cantidadSolicitada,
    required this.cantidadDespachada,
    required this.cantidadReservada,
    required this.pendienteAsignar,
    required this.pendienteEntregar,
    required this.fechaRegistro,
    this.reservas = const [],
    this.avisos = const [],
    this.despachos = const [],
  });

  final String id;
  final int numero;
  final String hospitalId;
  final String responsableId;
  final String grupoAbo;
  final String factorRh;
  final String prioridad;
  final String estado;
  final int cantidadSolicitada;
  final int cantidadDespachada;
  final int cantidadReservada;
  final int pendienteAsignar;
  final int pendienteEntregar;
  final DateTime fechaRegistro;
  final List<ReservaSolicitud> reservas;
  final List<AvisoSolicitud> avisos;
  final List<DespachoSolicitud> despachos;

  String get grupoCompacto =>
      '$grupoAbo${factorRh == 'positivo' ? '+' : '-'}';
}

class DatosSolicitud {
  const DatosSolicitud({
    required this.grupoAbo,
    required this.factorRh,
    required this.cantidad,
    required this.prioridad,
  });

  final String? grupoAbo;
  final String? factorRh;
  final int? cantidad;
  final String? prioridad;
}
