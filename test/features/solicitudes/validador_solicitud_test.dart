import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/features/solicitudes/domain/solicitud.dart';
import 'package:hemolink/features/solicitudes/domain/validador_solicitud.dart';

void main() {
  const validador = ValidadorSolicitud();

  group('ValidadorSolicitud - UT06.2-A', () {
    test('acepta datos válidos y normaliza grupo, Rh y prioridad', () {
      final resultado = validador.validarEntrada(
        grupoAbo: ' o ',
        factorRh: 'POSITIVO',
        cantidadTexto: ' 3 ',
        prioridad: 'URGENTE',
      );

      expect(resultado.grupoAbo, 'O');
      expect(resultado.factorRh, 'positivo');
      expect(resultado.cantidad, 3);
      expect(resultado.prioridad, 'urgente');
    });

    test('rechaza cantidad 0, negativa, decimal, no numérica o vacía', () {
      for (final invalida in ['', '   ', '0', '-1', '2.5', '2,5', 'abc']) {
        expect(
          () => validador.validarEntrada(
            grupoAbo: 'A',
            factorRh: 'negativo',
            cantidadTexto: invalida,
            prioridad: 'normal',
          ),
          throwsA(
            isA<ValidacionSolicitudException>().having(
              (e) => e.errores.containsKey('cantidad'),
              'error en cantidad',
              isTrue,
            ),
          ),
          reason: 'Debe rechazar cantidad "$invalida"',
        );
      }
    });

    test('rechaza grupo ABO, factor Rh y prioridad inválidos o ausentes', () {
      expect(
        () => validador.validarEntrada(
          grupoAbo: 'Z',
          factorRh: 'neutro',
          cantidadTexto: '2',
          prioridad: 'baja',
        ),
        throwsA(
          isA<ValidacionSolicitudException>().having(
            (e) => e.errores.keys.toSet(),
            'campos con error',
            {'grupoAbo', 'factorRh', 'prioridad'},
          ),
        ),
      );

      expect(
        () => validador.validarEntrada(
          grupoAbo: null,
          factorRh: null,
          cantidadTexto: '',
          prioridad: null,
        ),
        throwsA(
          isA<ValidacionSolicitudException>().having(
            (e) => e.errores.keys.toSet(),
            'todos los campos con error',
            {'grupoAbo', 'factorRh', 'cantidad', 'prioridad'},
          ),
        ),
      );
    });

    test('ordena bandeja con urgentes primero, más antiguos y desempate por ID', () {
      Solicitud crear(String id, String prioridad, int minuto) => Solicitud(
        id: id,
        numero: 1,
        hospitalId: 'hospital-demo',
        responsableId: 'hosp-1',
        grupoAbo: 'O',
        factorRh: 'positivo',
        prioridad: prioridad,
        estado: 'pendiente',
        cantidadSolicitada: 2,
        cantidadDespachada: 0,
        cantidadReservada: 0,
        pendienteAsignar: 2,
        pendienteEntregar: 2,
        fechaRegistro: DateTime.utc(2026, 11, 20, 10, minuto),
      );

      final lista = [
        crear('sol-b', 'normal', 1),
        crear('sol-c', 'urgente', 5),
        crear('sol-a', 'urgente', 1),
        crear('sol-d', 'normal', 1),
      ];

      final ordenadas = ordenarSolicitudes(lista);
      expect(
        ordenadas.map((s) => s.id).toList(),
        ['sol-a', 'sol-c', 'sol-b', 'sol-d'],
      );
    });
  });
}
