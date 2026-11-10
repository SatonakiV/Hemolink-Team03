import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/domain/muestra.dart';

void main() {
  group('T04.3 - Verificación de Muestras y Exclusión del Stock', () {
    final fecha = DateTime(2026, 11, 3);

    test('UT04.3-A: el componente de dominio ejercita y mantiene separadas las colecciones de muestras y unidades', () {
      final registro = RegistroMuestrasDominio();
      final muestra = Muestra(
        codigo: 'M-001',
        donacionId: 'DON-123',
        responsableId: 'enfermeria-01',
        fechaRegistro: fecha,
      );
      final unidad = UnidadSangre(
        codigo: 'U-001',
        donacionId: 'DON-123',
      );

      registro.registrarMuestra(muestra);

      final entidadesMixtas = <dynamic>[muestra, unidad];
      final unidadesElegibles = RegistroMuestrasDominio.obtenerUnidadesElegiblesParaStock(entidadesMixtas);

      expect(registro.muestras, contains(muestra));
      expect(registro.muestras, isNot(contains(unidad)));
      expect(unidadesElegibles, contains(unidad));
      expect(unidadesElegibles, isNot(contains(muestra)));
    });

    test('UT04.3-B: la consulta de componentes de stock excluye explícitamente la muestra aunque compartan donación', () {
      final muestra = Muestra(
        codigo: 'M-001',
        donacionId: 'DON-999',
        responsableId: 'enfermeria-01',
        fechaRegistro: fecha,
      );
      final unidad = UnidadSangre(
        codigo: 'U-001',
        donacionId: 'DON-999',
      );

      final entidadesDonacion = [muestra, unidad];
      final unidadesParaInventarioReservaDespacho =
          RegistroMuestrasDominio.obtenerUnidadesElegiblesParaStock(entidadesDonacion);

      expect(unidadesParaInventarioReservaDespacho.length, 1);
      expect(unidadesParaInventarioReservaDespacho.first.codigo, 'U-001');
      expect(unidadesParaInventarioReservaDespacho, isNot(contains(muestra)));
    });

    test('UT04.3-C: el contrato esElegibleParaStock distingue entre una UnidadSangre válida (true) y una Muestra (false)', () {
      final muestra = Muestra(
        codigo: 'M-001',
        donacionId: 'DON-123',
        responsableId: 'enfermeria-01',
        fechaRegistro: fecha,
      );
      final unidad = UnidadSangre(
        codigo: 'U-001',
        donacionId: 'DON-123',
      );

      // Muestra jamás es elegible para stock, reserva ni despacho
      expect(esElegibleParaStock(muestra), isFalse);

      // Una UnidadSangre sí es elegible para stock
      expect(esElegibleParaStock(unidad), isTrue);

      // Cualquier otro tipo desconocido es rechazado
      expect(esElegibleParaStock('objeto-invalido'), isFalse);
    });

    test('UT04.3-D: rechazo de códigos duplicados y donación/código inválido en muestras', () {
      final registro = RegistroMuestrasDominio();
      final muestraValida = Muestra(
        codigo: '  M-001  ',
        donacionId: '  DON-123  ',
        responsableId: '  enfermeria-01  ',
        fechaRegistro: fecha,
      );

      expect(muestraValida.codigo, 'M-001');
      expect(muestraValida.donacionId, 'DON-123');
      registro.registrarMuestra(muestraValida);

      // Rechazar duplicado (incluso con distinta combinación de mayúsculas/minúsculas)
      final muestraDuplicada = Muestra(
        codigo: 'm-001',
        donacionId: 'DON-123',
        responsableId: 'enfermeria-01',
        fechaRegistro: fecha,
      );
      expect(
        () => registro.registrarMuestra(muestraDuplicada),
        throwsA(isA<ArgumentError>()),
      );

      // Rechazar código de muestra vacío
      expect(
        () => Muestra(
          codigo: '   ',
          donacionId: 'DON-123',
          responsableId: 'enfermeria-01',
          fechaRegistro: fecha,
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Rechazar referencia a donación vacía (origen inválido)
      expect(
        () => Muestra(
          codigo: 'M-002',
          donacionId: '',
          responsableId: 'enfermeria-01',
          fechaRegistro: fecha,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
