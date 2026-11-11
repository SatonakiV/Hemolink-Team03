import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/domain/muestra.dart';

void main() {
  group('T04.3 - Verificación de Muestras y Exclusión del Stock', () {
    final fecha = DateTime(2026, 11, 3);

    test('UT04.3-A: el componente de dominio ejercita y mantiene separadas las colecciones de muestras y unidades', () {
      final registro = RegistroMuestrasDominio(
        existeDonacion: (id) => id == 'DON-123',
      );
      final muestra = Muestra(
        codigo: 'M-001',
        donacionId: 'DON-123',
        responsableId: 'enfermeria-01',
        fechaRegistro: fecha,
      );
      final unidad = UnidadSangre(codigo: 'U-001', donacionId: 'DON-123');

      registro.registrarMuestra(muestra);

      final entidadesMixtas = <dynamic>[muestra, unidad];
      final unidadesElegibles = RegistroMuestrasDominio.obtenerUnidades(
        entidadesMixtas,
      );

      expect(registro.muestras, contains(muestra));
      expect(registro.muestras, isNot(contains(unidad)));
      expect(unidadesElegibles, contains(unidad));
      expect(unidadesElegibles, isNot(contains(muestra)));
    });

    test('UT04.3-B: el separador excluye la muestra aunque comparta donación con una unidad', () {
      final muestra = Muestra(
        codigo: 'M-001',
        donacionId: 'DON-999',
        responsableId: 'enfermeria-01',
        fechaRegistro: fecha,
      );
      final unidad = UnidadSangre(codigo: 'U-001', donacionId: 'DON-999');

      final entidadesDonacion = [muestra, unidad];
      final unidades = RegistroMuestrasDominio.obtenerUnidades(
        entidadesDonacion,
      );

      expect(unidades.length, 1);
      expect(unidades.first.codigo, 'U-001');
      expect(unidades, isNot(contains(muestra)));
    });

    test(
      'UT04.3-C: esUnidadSangre distingue tipos sin afirmar disponibilidad',
      () {
        final muestra = Muestra(
          codigo: 'M-001',
          donacionId: 'DON-123',
          responsableId: 'enfermeria-01',
          fechaRegistro: fecha,
        );
        final unidad = UnidadSangre(codigo: 'U-001', donacionId: 'DON-123');

        // Muestra y unidad son tipos distintos.
        expect(esUnidadSangre(muestra), isFalse);

        // Reconocer una unidad no verifica su estado ni su vencimiento.
        expect(esUnidadSangre(unidad), isTrue);

        // Cualquier otro tipo desconocido es rechazado
        expect(esUnidadSangre('objeto-invalido'), isFalse);
      },
    );

    test('UT04.3-D: rechazo de códigos duplicados y donación/código inválido en muestras', () {
      final registro = RegistroMuestrasDominio(
        existeDonacion: (id) => id == 'DON-123',
      );
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

      // Un identificador no vacío tampoco basta si no existe el origen.
      expect(
        () => registro.registrarMuestra(
          Muestra(
            codigo: 'M-HUERFANA',
            donacionId: 'DON-INEXISTENTE',
            responsableId: 'enfermeria-01',
            fechaRegistro: fecha,
          ),
        ),
        throwsArgumentError,
      );
      expect(registro.muestras, [muestraValida]);

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
