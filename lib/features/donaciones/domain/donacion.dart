import 'dart:convert';
import 'dart:math';

const vidaUtilDias=42;
DateTime calcularVencimiento(DateTime extraccion) => DateTime.utc(extraccion.year, extraccion.month, extraccion.day).add(Duration(days: vidaUtilDias));
String  generarClaveConfirmacion([Random? aleatorio]) {
  final rnd= aleatorio ?? Random.secure();
  final bytes=List<int>.generate(18, (_) => rnd.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=','');
}
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
  final String claveConfirmacion;
  final String donanteId;
  final String evaluacionId;
  final DateTime fechaExtraccion;
  final int volumenMl;
  final List<String> codigosUnidades;

  DatosDonacion({
    required this.claveConfirmacion,
    required this.donanteId,
    required this.evaluacionId,
    required this.fechaExtraccion,
    required this.volumenMl,
    required List<String> codigosUnidades,
  }) : codigosUnidades = List.unmodifiable(codigosUnidades);
}

class ResumenDonacion {
  final String id;
  final DateTime fechaExtraccion;
  final int volumenMl;
  final String donanteId;
  const ResumenDonacion({
    required this.id,
    required this.fechaExtraccion,
    required this.volumenMl,
    required this.donanteId,
  });  
}