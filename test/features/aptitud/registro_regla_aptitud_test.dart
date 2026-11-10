import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/features/aptitud/data/evaluacion_repository.dart';
import 'package:hemolink/features/aptitud/domain/evaluacion_aptitud.dart';
import 'package:hemolink/features/aptitud/domain/registro_evaluaciones.dart';
import 'package:hemolink/features/aptitud/domain/validador_evaluacion.dart';

// Simula el almacenamiento de evaluaciones.
class RepositorioPrueba implements EvaluacionRepository {
  final List<EvaluacionAptitud> evaluaciones;

  RepositorioPrueba(this.evaluaciones);

  @override
  Future<void> guardar(EvaluacionAptitud evaluacion) async {
    evaluaciones.add(evaluacion);
  }

  @override
  Future<EvaluacionAptitud?> buscarPorId(String id) async {
    for (final evaluacion in evaluaciones) {
      if (evaluacion.id == id) {
        return evaluacion;
      }
    }
    return null;
  }

  @override
  Future<EvaluacionAptitud?> buscarActual(String donanteId) async {
    final historial = evaluaciones
        .where((e) => e.donanteId == donanteId)
        .toList();

    if (historial.isEmpty) {
      return null;
    }

    // La evaluación más reciente debe aparecer primero.
    historial.sort((a, b) {
      final comparacion =
          b.fechaEvaluacion.compareTo(a.fechaEvaluacion);

      if (comparacion != 0) {
        return comparacion;
      }

      return b.fechaRegistro.compareTo(a.fechaRegistro);
    });

    return historial.first;
  }
}

// Implementa la consulta de donantes exigida por el validador.
class DonantesPrueba implements ConsultaDonantes {
  @override
  Future<bool> existe(String id) async {
    return id == 'D001' || id == 'D002';
  }
}

// Validador ficticio para las pruebas de consulta.
class ValidadorPrueba implements ValidadorEvaluacion {
  @override
  final ConsultaDonantes consultaDonantes = DonantesPrueba();

  @override
  Future<void> validar(
    EvaluacionAptitud evaluacion, {
    DateTime? fechaActual,
  }) async {
    // Estas pruebas no registran evaluaciones.
    // Si se intenta validar, existe un error en el flujo.
    throw StateError(
      'No se debe validar durante la consulta de aptitud.',
    );
  }
}

// Construye evaluaciones ficticias para cada prueba.
EvaluacionAptitud crearEvaluacion({
  required String id,
  required ResultadoAptitud resultado,
  required DateTime fechaEvaluacion,
  DateTime? fechaFinVigencia,
  DateTime? fechaHabilitacion,
  String donanteId = 'D001',
}) {
  return EvaluacionAptitud(
    id: id,
    donanteId: donanteId,
    resultado: resultado,
    fechaEvaluacion: fechaEvaluacion,
    fechaFinVigencia: fechaFinVigencia,
    fechaHabilitacion: fechaHabilitacion,
    responsableId: 'ENF001',
    fechaRegistro: fechaEvaluacion,
  );
}

void main() {
  final fechaConsulta = DateTime(2026, 11, 8);

  RegistroEvaluaciones crearRegistro(
    List<EvaluacionAptitud> evaluaciones,
  ) {
    return RegistroEvaluaciones(
      repositorio: RepositorioPrueba(evaluaciones),
      validador: ValidadorPrueba(),
    );
  }

  test('INT1: permite donar con evaluación actual apta', () async {
    final registro = crearRegistro([
      crearEvaluacion(
        id: 'EV001',
        resultado: ResultadoAptitud.apto,
        fechaEvaluacion: DateTime(2026, 11, 5),
        fechaFinVigencia: DateTime(2026, 11, 20),
      ),
    ]);

    final resultado = await registro.puedeDonar(
      'D001',
      fechaConsulta: fechaConsulta,
    );

    expect(resultado, isTrue);
  });

  test('INT2: una evaluación diferida reemplaza a la apta', () async {
    final registro = crearRegistro([
      crearEvaluacion(
        id: 'EV002',
        resultado: ResultadoAptitud.diferido,
        fechaEvaluacion: DateTime(2026, 11, 7),
        fechaHabilitacion: DateTime(2026, 11, 15),
      ),
      crearEvaluacion(
        id: 'EV001',
        resultado: ResultadoAptitud.apto,
        fechaEvaluacion: DateTime(2026, 11, 1),
        fechaFinVigencia: DateTime(2026, 11, 20),
      ),
    ]);

    // La evaluación más reciente es DIFERIDO.
    final resultado = await registro.puedeDonar(
      'D001',
      fechaConsulta: fechaConsulta,
    );

    expect(resultado, isFalse);
  });

  test('INT3: un rechazo posterior impide donar', () async {
    final registro = crearRegistro([
      crearEvaluacion(
        id: 'EV001',
        resultado: ResultadoAptitud.apto,
        fechaEvaluacion: DateTime(2026, 11, 1),
        fechaFinVigencia: DateTime(2026, 11, 20),
      ),
      crearEvaluacion(
        id: 'EV002',
        resultado: ResultadoAptitud.rechazado,
        fechaEvaluacion: DateTime(2026, 11, 7),
      ),
    ]);

    final resultado = await registro.puedeDonar(
      'D001',
      fechaConsulta: fechaConsulta,
    );

    expect(resultado, isFalse);
  });

  test('INT4: nueva evaluación apta habilita tras diferimiento', () async {
    final registro = crearRegistro([
      crearEvaluacion(
        id: 'EV001',
        resultado: ResultadoAptitud.diferido,
        fechaEvaluacion: DateTime(2026, 11, 1),
        fechaHabilitacion: DateTime(2026, 11, 5),
      ),
      crearEvaluacion(
        id: 'EV002',
        resultado: ResultadoAptitud.apto,
        fechaEvaluacion: DateTime(2026, 11, 7),
        fechaFinVigencia: DateTime(2026, 11, 20),
      ),
    ]);

    final resultado = await registro.puedeDonar(
      'D001',
      fechaConsulta: fechaConsulta,
    );

    expect(resultado, isTrue);
  });

  test('INT5: rechaza donantes sin evaluación', () async {
    final registro = crearRegistro([]);

    final resultado = await registro.puedeDonar(
      'D001',
      fechaConsulta: fechaConsulta,
    );

    expect(resultado, isFalse);
  });

  test('INT6: no utiliza evaluaciones de otro donante', () async {
    final registro = crearRegistro([
      crearEvaluacion(
        id: 'EV001',
        donanteId: 'D002',
        resultado: ResultadoAptitud.apto,
        fechaEvaluacion: DateTime(2026, 11, 5),
        fechaFinVigencia: DateTime(2026, 11, 20),
      ),
    ]);

    final resultado = await registro.puedeDonar(
      'D001',
      fechaConsulta: fechaConsulta,
    );

    expect(resultado, isFalse);
  });
}
