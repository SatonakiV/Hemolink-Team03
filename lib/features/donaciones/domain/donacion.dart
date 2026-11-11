enum EstadoUnidad { disponible, reservada, despachada, vencida }

// Unidad obtenida de una donación. Conserva el grupo ABO/Rh de ORIGEN: es una
// copia hecha al confirmar, no una referencia al donante.
class UnidadSangre {
  final String id;
  final String codigo;
  final String donacionId;
  final String grupoAbo;
  final String factorRh;
  final String sedeId;
  final EstadoUnidad estado;
  final DateTime fechaVencimiento;

  const UnidadSangre({
    required this.id,
    required this.codigo,
    required this.donacionId,
    required this.grupoAbo,
    required this.factorRh,
    required this.sedeId,
    required this.estado,
    required this.fechaVencimiento,
  });

  String get grupo => '$grupoAbo${factorRh == 'positivo' ? '+' : '-'}';
}

/// Donación confirmada, con las relaciones que el detalle debe recuperar.
class Donacion {
  final String id;
  final String donanteId;
  final String evaluacionId;
  final DateTime fechaExtraccion;
  final int volumenMl;
  final String sedeId;
  final String responsableId;
  final DateTime fechaRegistro;
  final List<UnidadSangre> unidades;
  Donacion({
    required this.id,
    required this.donanteId,
    required this.evaluacionId,
    required this.fechaExtraccion,
    required this.volumenMl,
    required this.sedeId,
    required this.responsableId,
    required this.fechaRegistro,
    required List<UnidadSangre> unidades,
  }) : unidades = List.unmodifiable(unidades);
}

// Entrada del formulario. 
// El servidor obtiene sede,responsable,grupo y vencimiento de la sesión, del donante y del cálculo.
class DatosDonacion {
  final String donanteId;
  final String evaluacionId;
  final DateTime fechaExtraccion;
  final int volumenMl;
  final List<String> codigosUnidades;

  DatosDonacion({
    required this.donanteId,
    required this.evaluacionId,
    required this.fechaExtraccion,
    required this.volumenMl,
    required List<String> codigosUnidades,
  }) : codigosUnidades = List.unmodifiable(codigosUnidades);
}
