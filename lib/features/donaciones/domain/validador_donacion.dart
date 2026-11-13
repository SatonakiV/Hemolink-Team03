import '../../aptitud/domain/evaluacion_aptitud.dart';
import '../../aptitud/domain/regla_aptitud.dart';
import 'donacion.dart';

// Devuelve errores por campo, con las mismas claves que usa el servidor, para mostrarlos junto a cada dato. 
// El servidor vuelve a validar todo y es la autoridad: esto solo evita enviar algo que ya se sabe inválido.
class ValidadorDonacion {
  const ValidadorDonacion({this.regla = const ReglaAptitud()});
  final ReglaAptitud regla;
  static DateTime _dia(DateTime f) => DateTime.utc(f.year, f.month, f.day);

  Map<String, String> validar(DatosDonacion datos,{required EvaluacionAptitud? evaluacion,required DateTime hoy,}) 
  {
    final errores = <String, String>{};
    if (datos.donanteId.trim().isEmpty) {
      errores['donanteId'] = 'Selecciona un donante.';
    }
    final extraccion = _dia(datos.fechaExtraccion);
    if (extraccion.isAfter(_dia(hoy))) {
      errores['fechaExtraccion'] = 'La fecha de extracción no puede ser futura.';
    }
    if (datos.volumenMl <= 0) {
      errores['volumenMl'] = 'El volumen debe ser positivo en mililitros.';
    }
    if (datos.codigosUnidades.isEmpty) {
      errores['unidades'] = 'Agrega al menos una unidad.';
    } else {
      final vistos = <String>{};
      for (final codigo in datos.codigosUnidades) {
        final limpio = codigo.trim();
        if (limpio.isEmpty) {
          errores['unidades'] = 'Cada unidad necesita un código.';
          break;
        }
        if (!vistos.add(limpio.toLowerCase())) {
          errores['unidades'] = 'El código $limpio está repetido.';
          break;
        }
      }
    }
    if (evaluacion == null ||
        evaluacion.id != datos.evaluacionId ||
        evaluacion.donanteId != datos.donanteId) {
      errores['evaluacionId'] = 'El donante no tiene una evaluación registrada.';
    } else if (!regla.puedeDonar(evaluacion, fechaConsulta: extraccion)) {
      errores['evaluacionId'] =
          'El donante no tiene una evaluación apta para esa fecha.';
    }
    return errores;
  }
}