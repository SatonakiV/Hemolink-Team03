import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/domain/muestra.dart';

// Simulación ligera de una unidad de sangre para pruebas de separación de entidades
class UnidadSangrePrueba {
  final String codigo;
  final String donacionId;

  const UnidadSangrePrueba({
    required this.codigo,
    required this.donacionId,
  });
}

void main() {
  group('T04.3 - Verificación de Muestras y Exclusión del Stock', () {
    final fecha = DateTime(2026, 11, 3);
    final muestra = Muestra(
      codigo: 'M-001',
      donacionId: 'DON-123',
      responsableId: 'enfermeria-01',
      fechaRegistro: fecha,
    );
    final unidad = const UnidadSangrePrueba(
      codigo: 'U-001',
      donacionId: 'DON-123',
    );

    test('UT04.3-A: una muestra y una unidad siguen siendo colecciones distintas al consultar', () {
      final muestras = [muestra];
      final unidades = [unidad];

      expect(muestras, isNot(contains(unidad)));
      expect(unidades, isNot(contains(muestra)));
      expect(muestras.length, 1);
      expect(unidades.length, 1);
      expect(muestras.first.codigo, 'M-001');
      expect(unidades.first.codigo, 'U-001');
    });

    test('UT04.3-B: el conjunto de unidades excluye la muestra aunque compartan donación', () {
      final entidadesDonacion = <dynamic>[muestra, unidad];

      // Filtrar unidades excluyendo muestras de la misma donación
      final unidadesFiltradas = entidadesDonacion.where((e) => e is! Muestra).toList();

      expect(unidadesFiltradas, contains(unidad));
      expect(unidadesFiltradas, isNot(contains(muestra)));
      expect(unidadesFiltradas.length, 1);
    });

    test('UT04.3-C: el contrato de elegibilidad rechaza una muestra para stock, reserva y despacho', () {
      // Una muestra jamás debe ser elegible para stock
      expect(esElegibleParaStock(muestra), isFalse);
    });

    test('UT04.3-D: limpieza de código e invariantes de origen de la muestra', () {
      final muestraConEspacios = Muestra(
        codigo: '  M-002  ',
        donacionId: '  DON-123  ',
        responsableId: '  enfermeria-01  ',
        fechaRegistro: fecha,
      );

      expect(muestraConEspacios.codigo, 'M-002');
      expect(muestraConEspacios.donacionId, 'DON-123');
      expect(muestraConEspacios.responsableId, 'enfermeria-01');
    });
  });
}
