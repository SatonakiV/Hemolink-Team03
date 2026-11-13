import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/features/aptitud/domain/evaluacion_aptitud.dart';
import 'package:hemolink/features/donaciones/data/donacion_repository.dart';
import 'package:hemolink/features/donaciones/domain/donacion.dart';
import 'package:hemolink/features/donaciones/domain/registro_donaciones.dart';
import 'package:hemolink/features/donaciones/domain/validador_donacion.dart';
EvaluacionAptitud evaluacion({
  ResultadoAptitud resultado = ResultadoAptitud.apto,
  DateTime? fin,
  DateTime? habilitacion,
}) => EvaluacionAptitud(
  id: 'EV001',
  donanteId: 'D-1',
  resultado: resultado,
  fechaEvaluacion: DateTime(2026, 11, 2),
  fechaFinVigencia: resultado == ResultadoAptitud.apto
      ? (fin ?? DateTime(2026, 11, 13))
      : null,
  fechaHabilitacion: habilitacion,
  responsableId: 'nursing-demo',
  fechaRegistro: DateTime.utc(2026, 11, 2, 12),
);
DatosDonacion datos({
  String donanteId = 'D-1',
  DateTime? extraccion,
  int volumenMl = 450,
  List<String> codigos = const ['U-001'],
}) => DatosDonacion(
  claveConfirmacion: 'clave-de-prueba-0001',
  donanteId: donanteId,
  evaluacionId: 'EV001',
  fechaExtraccion: extraccion ?? DateTime(2026, 11, 3),
  volumenMl: volumenMl,
  codigosUnidades: codigos,
);
final hoy = DateTime(2026, 11, 4);
const validador = ValidadorDonacion();
class RepositorioFalso implements DonacionRepository {
  int guardados = 0;
  @override
  Future<Donacion> guardar(DatosDonacion d) async {
    guardados++;
    return Donacion(
      id: 'DON-1',
      donanteId: d.donanteId,
      evaluacionId: d.evaluacionId,
      fechaExtraccion: d.fechaExtraccion,
      volumenMl: d.volumenMl,
      sedeId: 'sede-central',
      responsableId: 'nursing-demo',
      fechaRegistro: DateTime.utc(2026, 11, 4),
      unidades: const [],
    );
  }

  @override
  Future<Donacion?> buscarPorId(String id) async => null;

  @override
  Future<List<ResumenDonacion>> listar() async => const[];
}

void main() {
  group('UT03.2-A: vencimiento', () {
    test('extracción del 02-11-2026 vence el 14-12-2026', () {
      expect(calcularVencimiento(DateTime(2026, 11, 2)), DateTime.utc(2026, 12, 14));
    });
    test('cruza año y febrero bisiesto sin correrse', () {
      expect(calcularVencimiento(DateTime(2026, 12, 25)), DateTime.utc(2027, 2, 5));
      expect(calcularVencimiento(DateTime(2028, 1, 20)), DateTime.utc(2028, 3, 2));
    });
    test('la hora del día no altera el resultado', () {
      expect(
        calcularVencimiento(DateTime(2026, 11, 2, 23, 59)),
        DateTime.utc(2026, 12, 14),
      );
    });
  });
  group('UT03.2-B: rechazos', () {
    test('un registro válido no tiene errores (incluye extremos del intervalo)', () {
      expect(validador.validar(datos(), evaluacion: evaluacion(), hoy: hoy), isEmpty);
      expect(
        validador.validar(
          datos(extraccion: DateTime(2026, 11, 2)),
          evaluacion: evaluacion(),
          hoy: hoy,
        ),
        isEmpty,
      );
    });
    test('fecha futura', () {
      final e = validador.validar(
        datos(extraccion: DateTime(2026, 11, 5)),
        evaluacion: evaluacion(),
        hoy: hoy,
      );
      expect(e.keys, contains('fechaExtraccion'));
    });
    test('volumen cero o negativo', () {
      for (final v in [0, -1]) {
        expect(
          validador.validar(datos(volumenMl: v), evaluacion: evaluacion(), hoy: hoy).keys,
          contains('volumenMl'),
        );
      }
    });
    test('cero unidades, código vacío o repetido', () {
      for (final codigos in [
        <String>[],
        ['  '],
        ['U-001', 'u-001'],
      ]) {
        expect(
          validador
              .validar(datos(codigos: codigos), evaluacion: evaluacion(), hoy: hoy)
              .keys,
          contains('unidades'),
          reason: codigos.toString(),
        );
      }
    });
    test('aptitud inválida usa la regla de HU02', () {
      final invalidas = <String, EvaluacionAptitud?>{
        'sin evaluación': null,
        'diferido': evaluacion(
          resultado: ResultadoAptitud.diferido,
          habilitacion: DateTime(2026, 11, 3),
        ),
        'rechazado': evaluacion(resultado: ResultadoAptitud.rechazado),
        'vigencia vencida': evaluacion(fin: DateTime(2026, 11, 2)),
      };
      invalidas.forEach((nombre, ev) {
        expect(
          validador.validar(datos(), evaluacion: ev, hoy: hoy).keys,
          contains('evaluacionId'),
          reason: nombre,
        );
      });
    });
    test('evaluación de otro donante se rechaza', () {
      expect(
        validador
            .validar(datos(donanteId: 'D-2'), evaluacion: evaluacion(), hoy: hoy)
            .keys,
        contains('evaluacionId'),
      );
    });
  });
  group('RegistroDonaciones', () {
    test('con errores no llama al repositorio', () async {
      final repo = RepositorioFalso();
      final registro = RegistroDonaciones(repositorio: repo, reloj: () => hoy);
      await expectLater(
        registro.confirmar(datos(volumenMl: 0), evaluacion: evaluacion()),
        throwsA(
          isA<ValidacionDonacionException>().having(
            (e) => e.errores.keys,
            'errores',
            contains('volumenMl'),
          ),
        ),
      );
      expect(repo.guardados, 0);
    });
    test('válido guarda una vez', () async {
      final repo = RepositorioFalso();
      final registro = RegistroDonaciones(repositorio: repo, reloj: () => hoy);
      final donacion = await registro.confirmar(datos(), evaluacion: evaluacion());
      expect(donacion.id, 'DON-1');
      expect(repo.guardados, 1);
    });
  });
  test('UT03.2-E: la clave de confirmación es única y válida para el servidor', () {
    final claves = {for (var i = 0; i < 200; i++) generarClaveConfirmacion()};
    expect(claves.length, 200);
    for (final c in claves) {
      expect(RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(c), isTrue, reason: c);
    }
    // Determinista con semilla: misma semilla, misma clave.
    expect(
      generarClaveConfirmacion(Random(1)),
      generarClaveConfirmacion(Random(1)),
    );
  });
}